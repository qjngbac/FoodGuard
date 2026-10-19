import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'remote/off_provider.dart';

/// 端上轻量存储：条码缓存 + 未收录配料
/// （与 scan_history 同文件不同连接，单用户场景下无并发问题）
class LocalStore {
  LocalStore._(this.db);

  final Database db;

  static const _ttlDays = 30;
  static LocalStore? _instance;

  static Future<LocalStore> open() async {
    if (_instance != null) return _instance!;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'fangxinyong_app.db'));
    final db = sqlite3.open(file.path);
    db.execute('PRAGMA busy_timeout = 3000;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS product_cache (
        barcode TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        fetched_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS unknown_ingredient (
        raw_text TEXT PRIMARY KEY,
        hit_count INTEGER NOT NULL DEFAULT 1,
        last_seen INTEGER NOT NULL
      )
    ''');
    _instance = LocalStore._(db);
    return _instance!;
  }

  // ---------- 条码缓存 ----------
  ProductLookup? getCached(String barcode, {int ttlDays = _ttlDays}) {
    final rows = db.select('SELECT payload, fetched_at FROM product_cache WHERE barcode=?', [barcode]);
    if (rows.isEmpty) return null;
    final fetched = (rows.first['fetched_at'] as num).toInt();
    final ageMs = DateTime.now().millisecondsSinceEpoch - fetched;
    if (ageMs < 0 || ageMs > ttlDays * 86400000) return null;
    try {
      return ProductLookup.fromJson(
          jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void putCache(ProductLookup lookup) {
    db.execute(
      'INSERT OR REPLACE INTO product_cache (barcode, payload, fetched_at) VALUES (?,?,?)',
      [lookup.barcode, jsonEncode(lookup.toJson()), DateTime.now().millisecondsSinceEpoch],
    );
  }

  void clearCache() => db.execute('DELETE FROM product_cache');

  // ---------- 未收录配料 ----------
  void addUnknown(String rawText) {
    final t = rawText.trim();
    if (t.isEmpty || t.length > 60) return;
    db.execute(
      'INSERT INTO unknown_ingredient (raw_text, hit_count, last_seen) VALUES (?,1,?) '
      'ON CONFLICT(raw_text) DO UPDATE SET hit_count=hit_count+1, last_seen=excluded.last_seen',
      [t, DateTime.now().millisecondsSinceEpoch],
    );
  }

  List<(String, int)> listUnknown({int limit = 500}) {
    final rows = db.select(
      'SELECT raw_text, hit_count FROM unknown_ingredient ORDER BY hit_count DESC, last_seen DESC LIMIT ?',
      [limit],
    );
    return rows
        .map((r) => (r['raw_text'].toString(), (r['hit_count'] as num).toInt()))
        .toList();
  }

  int get unknownCount =>
      (db.select('SELECT COUNT(*) AS c FROM unknown_ingredient').first['c'] as num).toInt();

  void clearUnknown() => db.execute('DELETE FROM unknown_ingredient');

  void close() => db.close();
}
