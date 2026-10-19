import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/data/knowledge_pack.dart';
import '../domain/entity/additive.dart';
import '../domain/entity/nutrition_facts.dart';
import 'remote/off_provider.dart';

/// 知识库装载：assets → 私有目录 → 只读打开 → 载入内存 KnowledgePack
class KnowledgeRepository {
  static const _assetPath = 'assets/knowledge/foodguard.db';
  static const _fileName = 'foodguard.db';

  KnowledgePack? _cache;
  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final file = await _prepareFile();
    _db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    return _db!;
  }

  Future<KnowledgePack> load({bool forceReload = false}) async {
    if (_cache != null && !forceReload) return _cache!;
    final db = await _getDb();
    final pack = _read(db);
    _cache = pack;
    return pack;
  }

  /// 检索离线高频国货条码种子库（毫秒级直出）
  Future<ProductLookup?> findProductByBarcode(String barcode) async {
    final cleanCode = barcode.trim();
    if (cleanCode.isEmpty) return null;
    try {
      final db = await _getDb();
      final rows = db.select(
        'SELECT barcode, name_zh, brand, category_code, ingredients_text, nutrition_json, nova_group, source '
        'FROM food_product_seed WHERE barcode = ? LIMIT 1',
        [cleanCode],
      );
      if (rows.isEmpty) return null;
      final r = rows.first;
      NutritionFacts? nutrition;
      final nutStr = r['nutrition_json']?.toString();
      if (nutStr != null && nutStr.isNotEmpty) {
        try {
          final j = jsonDecode(nutStr);
          if (j is Map<String, dynamic>) {
            nutrition = NutritionFacts.fromJson(j);
          }
        } catch (_) {}
      }
      return ProductLookup(
        barcode: r['barcode']?.toString() ?? cleanCode,
        nameZh: r['name_zh']?.toString(),
        brand: r['brand']?.toString(),
        categoryHint: r['category_code']?.toString(),
        ingredientsText: r['ingredients_text']?.toString(),
        nutrition: nutrition,
        novaGroup: (r['nova_group'] as num?)?.toInt(),
        source: r['source']?.toString() ?? 'SEED_OFFLINE',
      );
    } catch (_) {
      return null;
    }
  }

  /// 检索离线万级国货条码-品名字典（0毫秒出商品名与品牌）
  Future<ProductLookup?> findProductNameFromDict(String barcode) async {
    final cleanCode = barcode.trim();
    if (cleanCode.isEmpty) return null;
    try {
      final db = await _getDb();
      final rows = db.select(
        'SELECT barcode, name_zh, brand, spec, category '
        'FROM product_name_dict WHERE barcode = ? LIMIT 1',
        [cleanCode],
      );
      if (rows.isEmpty) return null;
      final r = rows.first;
      return ProductLookup(
        barcode: r['barcode']?.toString() ?? cleanCode,
        nameZh: r['name_zh']?.toString(),
        brand: r['brand']?.toString(),
        source: 'DICT_OFFLINE',
      );
    } catch (_) {
      return null;
    }
  }

  /// 查询同品类高分健康好物（供结果页触发“货比三家”同类健康品推荐）
  /// 支持同品牌健康系列优先推荐（如扫描高糖冰红茶优先置顶推荐同品牌无糖版）
  Future<List<ProductLookup>> findHealthyAlternatives(
    String? categoryCode, {
    int limit = 2,
    String? excludeBarcode,
    String? brand,
    String? productName,
  }) async {
    try {
      final db = await _getDb();
      final catPrefix = categoryCode != null && categoryCode.isNotEmpty
          ? categoryCode.split('.').first
          : '14'; // 默认饮料类优质好物（如东方树叶、天然矿泉水）

      // 提取品牌关键词（从显式 brand 或从 productName 探测，如“康师傅”、“元气森林”、“农夫山泉”、“统一”等）
      var detectedBrand = (brand != null && brand.trim().isNotEmpty) ? brand.trim() : null;
      if (detectedBrand == null && productName != null && productName.trim().isNotEmpty) {
        final name = productName.trim();
        const commonBrands = [
          '康师傅', '元气森林', '农夫山泉', '统一', '娃哈哈', '三得利', '雀巢', '伊利', '蒙牛',
          '洽洽', '乐事', '卫龙', '可口可乐', '百事', '维他奶', '旺旺', '达利园', '喜之郎',
          '白象', '今麦郎', '思念', '三全', '湾仔码头', '光明', '奥利奥', '徐福记', 'Oatly', '菲诺'
        ];
        for (final b in commonBrands) {
          if (name.contains(b)) {
            detectedBrand = b;
            break;
          }
        }
      }

      final result = <ProductLookup>[];
      final seenBarcodes = <String>{};
      if (excludeBarcode != null && excludeBarcode.isNotEmpty) {
        seenBarcodes.add(excludeBarcode);
      }

      // 1. 优先检索同品牌高分健康好物（NOVA <= 2，优先选取带“无糖”、“0糖”、“减盐”、“纯”、“原味”等关键词）
      if (detectedBrand != null && detectedBrand.isNotEmpty) {
        final sameBrandRows = db.select(
          'SELECT barcode, name_zh, brand, category_code, ingredients_text, nutrition_json, nova_group, source '
          'FROM food_product_seed '
          'WHERE (brand LIKE ? OR name_zh LIKE ?) AND nova_group <= 2 '
          'AND (? IS NULL OR barcode != ?) '
          'ORDER BY (CASE WHEN name_zh LIKE ? OR name_zh LIKE ? OR name_zh LIKE ? THEN 0 ELSE 1 END), nova_group ASC '
          'LIMIT 1',
          [
            '%$detectedBrand%',
            '%$detectedBrand%',
            excludeBarcode,
            excludeBarcode,
            '%无糖%',
            '%0糖%',
            '%减盐%',
          ],
        );

        for (final r in sameBrandRows) {
          final code = r['barcode']?.toString() ?? '';
          if (code.isNotEmpty && seenBarcodes.add(code)) {
            NutritionFacts? nutrition;
            final rawNut = r['nutrition_json']?.toString();
            if (rawNut != null && rawNut.isNotEmpty) {
              try {
                nutrition = NutritionFacts.fromJson(jsonDecode(rawNut) as Map<String, dynamic>);
              } catch (_) {}
            }
            result.add(ProductLookup(
              barcode: code,
              nameZh: r['name_zh']?.toString(),
              brand: r['brand']?.toString() ?? detectedBrand,
              categoryHint: r['category_code']?.toString(),
              ingredientsText: r['ingredients_text']?.toString(),
              nutrition: nutrition,
              novaGroup: (r['nova_group'] as num?)?.toInt(),
              source: r['source']?.toString() ?? 'SEED_OFFLINE',
            ));
          }
        }
      }

      // 2. 补齐剩余推荐位（同品类其他优质健康好物）
      final remainingSlots = limit - result.length;
      if (remainingSlots > 0) {
        var rows = db.select(
          'SELECT barcode, name_zh, brand, category_code, ingredients_text, nutrition_json, nova_group, source '
          'FROM food_product_seed '
          'WHERE (category_code LIKE ? OR category_code LIKE ?) AND nova_group <= 2 '
          'AND (? IS NULL OR barcode != ?) '
          'ORDER BY nova_group ASC, barcode ASC LIMIT ?',
          ['$catPrefix.%', '$catPrefix%', excludeBarcode, excludeBarcode, remainingSlots + seenBarcodes.length],
        );

        if (rows.isEmpty) {
          rows = db.select(
            'SELECT barcode, name_zh, brand, category_code, ingredients_text, nutrition_json, nova_group, source '
            'FROM food_product_seed '
            'WHERE category_code LIKE ? AND nova_group <= 2 '
            'AND (? IS NULL OR barcode != ?) '
            'ORDER BY nova_group ASC, barcode ASC LIMIT ?',
            ['14.%', excludeBarcode, excludeBarcode, remainingSlots + seenBarcodes.length],
          );
        }

        for (final r in rows) {
          final code = r['barcode']?.toString() ?? '';
          if (code.isNotEmpty && seenBarcodes.add(code)) {
            NutritionFacts? nutrition;
            final rawNut = r['nutrition_json']?.toString();
            if (rawNut != null && rawNut.isNotEmpty) {
              try {
                nutrition = NutritionFacts.fromJson(jsonDecode(rawNut) as Map<String, dynamic>);
              } catch (_) {}
            }
            result.add(ProductLookup(
              barcode: code,
              nameZh: r['name_zh']?.toString(),
              brand: r['brand']?.toString(),
              categoryHint: r['category_code']?.toString(),
              ingredientsText: r['ingredients_text']?.toString(),
              nutrition: nutrition,
              novaGroup: (r['nova_group'] as num?)?.toInt(),
              source: r['source']?.toString() ?? 'SEED_OFFLINE',
            ));
            if (result.length >= limit) break;
          }
        }
      }

      return result;
    } catch (_) {
      return const [];
    }
  }

  void close() {
    _db?.close();
    _db = null;
  }

  Future<File> _prepareFile() async {
    final assetFile = File(_assetPath);
    if (assetFile.existsSync()) {
      return assetFile;
    }
    final dir = await getApplicationDocumentsDirectory();
    final target = File(p.join(dir.path, _fileName));

    final assetData = await rootBundle.load(_assetPath);
    final bytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );

    // 先把资产写到一个临时文件，读出它的 knowledge_version 再决定是否替换
    final probe = File(p.join(dir.path, '$_fileName.probe'));
    await probe.writeAsBytes(bytes, flush: true);
    final assetVersion = _readLocalVersion(probe);
    await probe.delete();

    if (!target.existsSync()) {
      await target.writeAsBytes(bytes, flush: true);
      return target;
    }

    final localVersion = _readLocalVersion(target);
    if (assetVersion != null && localVersion != assetVersion) {
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (target.existsSync()) await target.delete();
      await tmp.rename(target.path);
    }
    return target;
  }

  String? _readLocalVersion(File file) {
    Database? db;
    try {
      db = sqlite3.open(file.path, mode: OpenMode.readOnly);
      final rows = db.select(
        "SELECT value FROM knowledge_meta WHERE key='knowledge_version'",
      );
      if (rows.isEmpty) return null;
      return rows.first['value']?.toString();
    } catch (_) {
      return null;
    } finally {
      db?.close();
    }
  }

  KnowledgePack _read(Database db) {
    String? meta(String key) {
      try {
        final rows = db.select('SELECT value FROM knowledge_meta WHERE key=?', [key]);
        return rows.isEmpty ? null : rows.first['value']?.toString();
      } catch (_) {
        return null;
      }
    }

    // 逐表容错：随包库与代码版本不同步（缺表/缺列）时降级为空集合，而不是让启动页崩掉
    List<Row> safeRows(String sql) {
      try {
        return db.select(sql);
      } catch (_) {
        return const [];
      }
    }

    // additive
    final additives = <Additive>[];
    for (final r in safeRows('SELECT * FROM additive ORDER BY id')) {
      final flags = (r['population_flags']?.toString() ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      additives.add(Additive(
        id: (r['id'] as num).toInt(),
        nameZh: r['name_zh']?.toString() ?? '',
        nameEn: r['name_en']?.toString(),
        insCode: r['ins_code']?.toString(),
        euCode: r['eu_code']?.toString(),
        functionClass: r['function_class']?.toString(),
        adiValue: (r['adi_value'] as num?)?.toDouble(),
        adiType: r['adi_type']?.toString() ?? 'UNKNOWN',
        iarcGroup: r['iarc_group']?.toString(),
        iarcNote: r['iarc_note']?.toString(),
        riskLevel: (r['risk_level'] as num?)?.toInt() ?? 3,
        defaultPenalty: (r['default_penalty'] as num?)?.toDouble() ?? 3.0,
        riskReasonZh: r['risk_reason_zh']?.toString(),
        populationFlags: flags,
        isIllegal: (r['is_illegal'] as num?)?.toInt() == 1,
        removedInGb2760: (r['removed_in_gb2760_2024'] as num?)?.toInt() == 1,
        sourceRef: r['source_ref']?.toString() ?? '',
      ));
    }

    final pack = KnowledgePack(
      additives: additives,
      usageByAdditive: <int, List<AdditiveUsage>>{},
      categories: <FoodCategory>[],
      allergens: <Allergen>[],
      nutrientRefs: <NutrientRef>[],
      nutrientRules: <NutrientRule>[],
      novaMarkers: <NovaMarker>[],
      populationRules: <PopulationRule>[],
      rawMaterials: <RawMaterial>[],
      version: meta('knowledge_version') ?? 'unknown',
      dataQuality: meta('data_quality') ?? 'SEED',
    );

    // alias: 依据别名类型稳定排序（官方别名 > 缩写 > 俗名/其它，先注册者优先）
    for (final r in safeRows('''
      SELECT additive_id, alias, alias_type 
      FROM additive_alias 
      ORDER BY CASE alias_type WHEN 'OFFICIAL' THEN 0 WHEN 'ABBR' THEN 1 ELSE 2 END, id
    ''')) {
      final id = (r['additive_id'] as num).toInt();
      pack.addAlias(id, r['alias']?.toString() ?? '');
    }

    // 补齐官方通用别名俗名：必须按标准名查 ID（历史上按数字 ID 硬编码会把 CI 号指向完全错误的物质）
    const extraAdditiveAliases = <String, List<String>>{
      '山梨糖醇': ['山梨醇', '山梨(糖)醇', 'D-山梨糖醇'],
      '对羟基苯甲酸甲酯': ['羟苯甲酯', '尼泊金甲酯'],
      '对羟基苯甲酸乙酯': ['羟苯乙酯', '尼泊金乙酯'],
      '对羟基苯甲酸丙酯': ['羟苯丙酯', '尼泊金丙酯'],
      '苯甲酸钠': ['安息香酸钠'],
      '糖精钠': ['邻磺酰苯甲酰亚胺钠'],
      '丙二醇': ['1,2-丙二醇'],
      '柠檬黄': ['CI 19140'],
      '日落黄': ['CI 15985'],
      '胭脂红': ['CI 16255'],
      '诱惑红': ['CI 16035'],
      '亮蓝': ['CI 42090'],
      '二氧化钛': ['CI 77891'],
    };
    final idByName = {for (final a in additives) a.nameZh: a.id};
    for (final entry in extraAdditiveAliases.entries) {
      final id = idByName[entry.key];
      if (id == null) continue;
      for (final alias in entry.value) {
        pack.addAlias(id, alias);
      }
    }

    // usage
    for (final r in safeRows('SELECT * FROM additive_usage')) {
      final id = (r['additive_id'] as num).toInt();
      pack.usageByAdditive.putIfAbsent(id, () => <AdditiveUsage>[]).add(AdditiveUsage(
            additiveId: id,
            categoryCode: r['category_code']?.toString() ?? '',
            maxUsage: (r['max_usage'] as num?)?.toDouble(),
            unit: r['unit']?.toString(),
            note: r['usage_note']?.toString(),
            isProhibited: (r['is_prohibited'] as num?)?.toInt() == 1,
          ));
    }

    // categories
    pack.categories.addAll(safeRows('SELECT code, name_zh, keywords FROM food_category').map(
          (r) => FoodCategory(
            code: r['code']?.toString() ?? '',
            nameZh: r['name_zh']?.toString() ?? '',
            keywords: (r['keywords']?.toString() ?? '')
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          ),
        ));

    // allergens
    pack.allergens.addAll(safeRows('SELECT * FROM allergen').map(
          (r) => Allergen(
            code: r['code']?.toString() ?? '',
            nameZh: r['name_zh']?.toString() ?? '',
            aliases: (r['aliases']?.toString() ?? '')
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
            noteZh: r['note_zh']?.toString(),
          ),
        ));

    // nrv
    pack.nutrientRefs.addAll(safeRows('SELECT * FROM nutrient_ref').map(
          (r) => NutrientRef(
            code: r['code']?.toString() ?? '',
            nameZh: r['name_zh']?.toString() ?? '',
            unit: r['unit']?.toString() ?? '',
            nrvValue: (r['nrv_value'] as num?)?.toDouble(),
          ),
        ));

    // nutrient rules
    pack.nutrientRules.addAll(safeRows('SELECT * FROM nutrient_rule').map(
          (r) => NutrientRule(
            nutrientCode: r['nutrient_code']?.toString() ?? '',
            scope: r['scope']?.toString() ?? 'SOLID',
            highValue: (r['high_value'] as num?)?.toDouble(),
            midValue: (r['mid_value'] as num?)?.toDouble(),
            lowValue: (r['low_value'] as num?)?.toDouble(),
            highPenalty: (r['high_penalty'] as num?)?.toDouble() ?? 0,
            midPenalty: (r['mid_penalty'] as num?)?.toDouble() ?? 0,
            lowPenalty: (r['low_penalty'] as num?)?.toDouble() ?? 0,
            isBonus: (r['is_bonus'] as num?)?.toInt() == 1,
          ),
        ));

    // nova markers
    pack.novaMarkers.addAll(safeRows('SELECT * FROM nova_marker').map(
          (r) => NovaMarker(
            keyword: r['keyword']?.toString() ?? '',
            novaFloor: (r['nova_floor'] as num?)?.toInt() ?? 4,
            weight: (r['weight'] as num?)?.toDouble() ?? 1.0,
          ),
        ));

    // population rules
    pack.populationRules.addAll(safeRows('SELECT * FROM population_rule').map(
          (r) => PopulationRule(
            populationCode: r['population_code']?.toString() ?? '',
            targetType: r['target_type']?.toString() ?? 'ADDITIVE',
            targetKey: r['target_key']?.toString() ?? '',
            severity: r['severity']?.toString() ?? 'CAUTION',
            threshold: (r['threshold'] as num?)?.toDouble(),
            thresholdUnit: r['threshold_unit']?.toString(),
            reasonZh: r['reason_zh']?.toString() ?? '',
          ),
        ));

    // raw materials
    pack.rawMaterials.addAll(safeRows('SELECT * FROM raw_material').map(
          (r) => RawMaterial(
            keyword: r['keyword']?.toString() ?? '',
            category: r['category']?.toString() ?? 'OTHER',
            allergenCode: r['allergen_code']?.toString(),
          ),
        ));

    // 补齐常见食品与个护天然原料/草本/益生菌/风味配料
    const extraRawMaterials = [
      RawMaterial(keyword: '薄荷醇', category: '香辛料/风味'),
      RawMaterial(keyword: 'L-薄荷醇', category: '香辛料/风味'),
      RawMaterial(keyword: '薄荷脑', category: '香辛料/风味'),
      RawMaterial(keyword: '薄荷素油', category: '香辛料/风味'),
      RawMaterial(keyword: 'PEG-40氢化蓖麻油', category: '油脂/乳化'),
      RawMaterial(keyword: '氢化蓖麻油', category: '油脂/乳化'),
      RawMaterial(keyword: '蓖麻油', category: '油脂'),
      RawMaterial(keyword: '蜂胶', category: '天然提取物'),
      RawMaterial(keyword: '蜂胶提取物', category: '天然提取物'),
      RawMaterial(keyword: '乳酸杆菌', category: '益生菌'),
      RawMaterial(keyword: '乳杆菌', category: '益生菌'),
      RawMaterial(keyword: '双歧杆菌', category: '益生菌'),
      RawMaterial(keyword: '益生菌', category: '益生菌'),
      RawMaterial(keyword: '香蜜桃果提取物', category: '水果提取物'),
      RawMaterial(keyword: '蜜桃提取物', category: '水果提取物'),
      RawMaterial(keyword: '桃果提取物', category: '水果提取物'),
      RawMaterial(keyword: '桃提取物', category: '水果提取物'),
      RawMaterial(keyword: '水蜜桃提取物', category: '水果提取物'),
      RawMaterial(keyword: '果提取物', category: '水果提取物'),
      RawMaterial(keyword: '提取物', category: '天然提取物'),
      RawMaterial(keyword: '提取液', category: '天然提取物'),

      // 高频水果原料（解决青提汁、阳光玫瑰等识别问题）
      RawMaterial(keyword: '青提', category: 'FRUIT'),
      RawMaterial(keyword: '提子', category: 'FRUIT'),
      RawMaterial(keyword: '青提汁', category: 'FRUIT'),
      RawMaterial(keyword: '青提原汁', category: 'FRUIT'),
      RawMaterial(keyword: '青提浓缩汁', category: 'FRUIT'),
      RawMaterial(keyword: '浓缩青提汁', category: 'FRUIT'),
      RawMaterial(keyword: '阳光玫瑰', category: 'FRUIT'),
      RawMaterial(keyword: '阳光玫瑰葡萄', category: 'FRUIT'),
      RawMaterial(keyword: '巨峰葡萄', category: 'FRUIT'),
      RawMaterial(keyword: '葡萄', category: 'FRUIT'),
      RawMaterial(keyword: '葡萄汁', category: 'FRUIT'),
      RawMaterial(keyword: '白葡萄汁', category: 'FRUIT'),
      RawMaterial(keyword: '黑加仑', category: 'FRUIT'),
      RawMaterial(keyword: '白桃', category: 'FRUIT'),
      RawMaterial(keyword: '水蜜桃', category: 'FRUIT'),
      RawMaterial(keyword: '黄桃', category: 'FRUIT'),
      RawMaterial(keyword: '西梅', category: 'FRUIT'),
      RawMaterial(keyword: '杨梅', category: 'FRUIT'),
      RawMaterial(keyword: '荔枝', category: 'FRUIT'),
      RawMaterial(keyword: '龙眼', category: 'FRUIT'),
      RawMaterial(keyword: '桂圆', category: 'FRUIT'),
      RawMaterial(keyword: '百香果', category: 'FRUIT'),
      RawMaterial(keyword: '芒果', category: 'FRUIT'),
      RawMaterial(keyword: '草莓', category: 'FRUIT'),
      RawMaterial(keyword: '蓝莓', category: 'FRUIT'),
      RawMaterial(keyword: '树莓', category: 'FRUIT'),
      RawMaterial(keyword: '覆盆子', category: 'FRUIT'),
      RawMaterial(keyword: '桑葚', category: 'FRUIT'),
      RawMaterial(keyword: '蔓越莓', category: 'FRUIT'),
      RawMaterial(keyword: '枸杞', category: 'FRUIT'),
      RawMaterial(keyword: '番石榴', category: 'FRUIT'),
      RawMaterial(keyword: '芭乐', category: 'FRUIT'),
      RawMaterial(keyword: '椰子', category: 'FRUIT'),
      RawMaterial(keyword: '椰肉', category: 'FRUIT'),
      RawMaterial(keyword: '生椰', category: 'FRUIT'),
      RawMaterial(keyword: '生椰乳', category: 'FRUIT'),
      RawMaterial(keyword: '椰子水', category: 'FRUIT'),
      RawMaterial(keyword: '柠檬', category: 'FRUIT'),
      RawMaterial(keyword: '青柠', category: 'FRUIT'),
      RawMaterial(keyword: '金桔', category: 'FRUIT'),
      RawMaterial(keyword: '蜜桔', category: 'FRUIT'),
      RawMaterial(keyword: '柑橘', category: 'FRUIT'),
      RawMaterial(keyword: '柚子', category: 'FRUIT'),
      RawMaterial(keyword: '西柚', category: 'FRUIT'),
      RawMaterial(keyword: '红柚', category: 'FRUIT'),
      RawMaterial(keyword: '甜橙', category: 'FRUIT'),
      RawMaterial(keyword: '血橙', category: 'FRUIT'),
      RawMaterial(keyword: '雪梨', category: 'FRUIT'),
      RawMaterial(keyword: '秋梨', category: 'FRUIT'),
      RawMaterial(keyword: '哈密瓜', category: 'FRUIT'),
      RawMaterial(keyword: '西瓜', category: 'FRUIT'),

      // 高频蔬菜及植物原料
      RawMaterial(keyword: '番茄', category: 'VEGETABLE'),
      RawMaterial(keyword: '西红柿', category: 'VEGETABLE'),
      RawMaterial(keyword: '胡萝卜', category: 'VEGETABLE'),
      RawMaterial(keyword: '黄瓜', category: 'VEGETABLE'),
      RawMaterial(keyword: '芹菜', category: 'VEGETABLE'),
      RawMaterial(keyword: '甜菜', category: 'VEGETABLE'),
      RawMaterial(keyword: '栀子', category: 'PLANT'),
      RawMaterial(keyword: '栀子提取液', category: 'PLANT'),
      RawMaterial(keyword: '栀子提取物', category: 'PLANT'),
      RawMaterial(keyword: '生姜', category: '香辛料/风味'),
      RawMaterial(keyword: '茉莉花', category: 'PLANT'),
      RawMaterial(keyword: '桂花', category: 'PLANT'),
      RawMaterial(keyword: '菊花', category: 'PLANT'),
      RawMaterial(keyword: '重瓣红玫瑰', category: 'PLANT'),
    ];
    pack.rawMaterials.addAll(extraRawMaterials);

    return pack;
  }
}
