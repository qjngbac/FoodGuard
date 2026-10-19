import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/entity/score_result.dart';

class ScanRecord {
  ScanRecord({
    required this.id,
    required this.score,
    required this.grade,
    required this.createdAt,
    required this.result,
    this.barcode,
    this.productName,
    this.brand,
    this.ingredientsText,
    this.nutritionJson,
    this.knowledgeVersion,
  });

  final String id;
  final int score;
  final String grade;
  final int createdAt;
  final Map<String, dynamic> result;
  final String? barcode;
  final String? productName;
  final String? brand;
  final String? ingredientsText;
  final String? nutritionJson;
  final String? knowledgeVersion;

  Grade get gradeEnum => GradeX.fromLabel(grade);
}

/// 本地历史记录（app.db，端上读写）
class HistoryRepository {
  HistoryRepository({Database? db}) {
    _db = db;
  }

  Database? _db;
  bool _schemaInited = false;

  Future<Database> _open() async {
    if (_db != null) {
      if (!_schemaInited) {
        _initSchema(_db!);
        _schemaInited = true;
      }
      return _db!;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'fangxinyong_app.db'));
    final db = sqlite3.open(file.path);
    db.execute('PRAGMA busy_timeout = 3000;');
    if (!_schemaInited) {
      _initSchema(db);
      _schemaInited = true;
    }
    _db = db;
    return db;
  }

  void _initSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS scan_history (
        id TEXT PRIMARY KEY,
        barcode TEXT,
        product_name TEXT,
        brand TEXT,
        ingredients_text TEXT,
        nutrition_json TEXT,
        score INTEGER NOT NULL,
        grade TEXT NOT NULL,
        result_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        knowledge_version TEXT
      )
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_hist_time ON scan_history(created_at DESC)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_hist_barcode ON scan_history(barcode)');

    // 自动清洗历史脏数据：对于条码相同（或品名+配料相同）的旧重复记录，只保留最新的一条
    try {
      db.execute('''
        DELETE FROM scan_history WHERE id NOT IN (
          SELECT id FROM (
            SELECT id, ROW_NUMBER() OVER (
              PARTITION BY COALESCE(NULLIF(barcode, ''), ingredients_text)
              ORDER BY created_at DESC
            ) as rn
            FROM scan_history
          ) WHERE rn = 1
        )
      ''');
    } catch (_) {
      // 容错处理
    }
  }

  /// 插入或就地更新历史记录。
  /// 若条码相同或品名+配料相同，直接原地更新时间戳与分析快照，永不产生双份/重复记录。
  Future<String> insert({
    required String id,
    required String ingredientsText,
    required ScoreResult result,
    String? barcode,
    String? productName,
    String? brand,
    String? nutritionJson,
  }) async {
    final db = await _open();
    final cleanBarcode = (barcode?.trim().isEmpty ?? true) ? null : barcode!.trim();
    final cleanName = (productName?.trim().isEmpty ?? true) ? null : productName!.trim();
    final cleanIngredients = ingredientsText.trim();

    // 智能去重检索：优先查同条形码，其次查同商品名+同配料
    List<Row> existing = [];
    if (cleanBarcode != null) {
      existing = db.select(
        'SELECT id FROM scan_history WHERE barcode = ? ORDER BY created_at DESC LIMIT 1',
        [cleanBarcode],
      );
    }
    if (existing.isEmpty && cleanIngredients.isNotEmpty) {
      if (cleanName != null && cleanName != '未命名商品') {
        existing = db.select(
          'SELECT id FROM scan_history WHERE ingredients_text = ? AND product_name = ? ORDER BY created_at DESC LIMIT 1',
          [cleanIngredients, cleanName],
        );
      } else {
        existing = db.select(
          'SELECT id FROM scan_history WHERE ingredients_text = ? ORDER BY created_at DESC LIMIT 1',
          [cleanIngredients],
        );
      }
    }

    if (existing.isNotEmpty) {
      final targetId = existing.first['id'].toString();
      db.execute(
        'UPDATE scan_history SET '
        'barcode = COALESCE(?, barcode), '
        'product_name = COALESCE(?, product_name), '
        'brand = COALESCE(?, brand), '
        'ingredients_text = ?, '
        'nutrition_json = COALESCE(?, nutrition_json), '
        'score = ?, '
        'grade = ?, '
        'result_json = ?, '
        'created_at = ?, '
        'knowledge_version = ? '
        'WHERE id = ?',
        [
          cleanBarcode,
          cleanName,
          brand,
          cleanIngredients,
          nutritionJson,
          result.score,
          result.personalGrade.label,
          jsonEncode(result.toJson()),
          DateTime.now().millisecondsSinceEpoch,
          result.knowledgeVersion,
          targetId,
        ],
      );
      return targetId;
    }

    db.execute(
      'INSERT OR REPLACE INTO scan_history '
      '(id, barcode, product_name, brand, ingredients_text, nutrition_json, score, grade, result_json, created_at, knowledge_version) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        cleanBarcode,
        cleanName,
        brand,
        cleanIngredients,
        nutritionJson,
        result.score,
        result.personalGrade.label,
        jsonEncode(result.toJson()),
        DateTime.now().millisecondsSinceEpoch,
        result.knowledgeVersion,
      ],
    );
    return id;
  }

  /// 更新既有历史记录的评分与分析结果（如修改食品类别后重新计算，就地覆盖）
  Future<void> updateRecordResult({
    required String id,
    required ScoreResult result,
    String? productName,
    String? barcode,
    String? ingredientsText,
    String? nutritionJson,
  }) async {
    final db = await _open();
    final cleanBarcode = (barcode?.trim().isEmpty ?? true) ? null : barcode!.trim();
    final cleanName = (productName?.trim().isEmpty ?? true) ? null : productName!.trim();
    final cleanIngredients = ingredientsText?.trim();

    db.execute(
      'UPDATE scan_history SET '
      'score = ?, '
      'grade = ?, '
      'result_json = ?, '
      'knowledge_version = ?, '
      'product_name = COALESCE(?, product_name), '
      'barcode = COALESCE(?, barcode), '
      'ingredients_text = COALESCE(?, ingredients_text), '
      'nutrition_json = COALESCE(?, nutrition_json), '
      'created_at = ? '
      'WHERE id = ?',
      [
        result.score,
        result.personalGrade.label,
        jsonEncode(result.toJson()),
        result.knowledgeVersion,
        cleanName,
        cleanBarcode,
        cleanIngredients,
        nutritionJson,
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
  }

  Future<List<ScanRecord>> list({int limit = 100}) async {
    final db = await _open();
    final rows = db.select(
      'SELECT * FROM scan_history ORDER BY created_at DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) {
      Map<String, dynamic> decoded = {};
      try {
        decoded = jsonDecode(r['result_json']?.toString() ?? '{}') as Map<String, dynamic>;
      } catch (_) {
        decoded = {};
      }
      return ScanRecord(
        id: r['id']?.toString() ?? '',
        score: (r['score'] as num?)?.toInt() ?? 0,
        grade: r['grade']?.toString() ?? 'B',
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        result: decoded,
        barcode: r['barcode']?.toString(),
        productName: r['product_name']?.toString(),
        brand: r['brand']?.toString(),
        ingredientsText: r['ingredients_text']?.toString(),
        nutritionJson: r['nutrition_json']?.toString(),
        knowledgeVersion: r['knowledge_version']?.toString(),
      );
    }).toList();
  }

  Future<void> delete(String id) async {
    final db = await _open();
    db.execute('DELETE FROM scan_history WHERE id=?', [id]);
  }

  Future<void> deleteMany(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _open();
    final placeholders = List.filled(ids.length, '?').join(',');
    db.execute('DELETE FROM scan_history WHERE id IN ($placeholders)', ids);
  }

  Future<void> updateProductInfo(String id, {String? productName, String? barcode}) async {
    final db = await _open();
    final cleanName = (productName?.trim().isEmpty ?? true) ? null : productName!.trim();
    final cleanBarcode = (barcode?.trim().isEmpty ?? true) ? null : barcode!.trim();
    db.execute(
      'UPDATE scan_history SET product_name = COALESCE(?, product_name), barcode = COALESCE(?, barcode) WHERE id=?',
      [cleanName, cleanBarcode, id],
    );
  }

  Future<ScanRecord?> findByBarcode(String barcode) async {
    final db = await _open();
    final clean = barcode.trim();
    final rows = db.select(
      "SELECT * FROM scan_history WHERE barcode=? AND ingredients_text IS NOT NULL AND TRIM(ingredients_text) != '' ORDER BY created_at DESC LIMIT 1",
      [clean],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    Map<String, dynamic> decoded = {};
    try {
      decoded = jsonDecode(r['result_json']?.toString() ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      decoded = {};
    }
    return ScanRecord(
      id: r['id']?.toString() ?? '',
      score: (r['score'] as num?)?.toInt() ?? 0,
      grade: r['grade']?.toString() ?? 'B',
      createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
      result: decoded,
      barcode: r['barcode']?.toString(),
      productName: r['product_name']?.toString(),
      brand: r['brand']?.toString(),
      ingredientsText: r['ingredients_text']?.toString(),
      nutritionJson: r['nutrition_json']?.toString(),
      knowledgeVersion: r['knowledge_version']?.toString(),
    );
  }

  Future<void> clear() async {
    final db = await _open();
    db.execute('DELETE FROM scan_history');
  }

  void dispose() {
    _db?.close();
    _db = null;
  }
}
