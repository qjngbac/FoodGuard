import 'dart:convert';
import 'dart:io';

import 'package:fangxinyong/core/util/checksum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// 随包知识库的数据契约测试：把"重建/换库时必须成立"的约束固化下来，
/// 避免脏数据只能靠人眼发现（历史上曾因 CSV 与 .db 脱节导致重建即丢数据）。
void main() {
  const path = 'assets/knowledge/foodguard.db';

  late Database db;

  setUpAll(() {
    expect(File(path).existsSync(), isTrue, reason: '$path 必须存在');
    db = sqlite3.open(path, mode: OpenMode.readOnly);
  });

  tearDownAll(() => db.close());

  test('所有商品码都是可扫描的 EAN-13', () {
    for (final table in ['food_product_seed', 'product_name_dict']) {
      final bad = db
          .select('SELECT barcode FROM $table')
          .map((r) => r['barcode'].toString())
          .where((c) => !BarcodeChecksum.isValidEan13(c))
          .toList();
      expect(bad, isEmpty, reason: '$table 存在 ${bad.length} 条非法校验位条码，例如 ${bad.take(3)}');
    }
  });

  test('GB 类别码必须是 n n . d 形式，不留尾点', () {
    final codes = <String>[
      ...db.select('SELECT DISTINCT category_code AS c FROM additive_usage').map((r) => r['c'].toString()),
      ...db
          .select("SELECT DISTINCT category_code AS c FROM food_product_seed WHERE category_code != ''")
          .map((r) => r['c'].toString()),
    ];
    final bad = codes.where((c) => !RegExp(r'^\d{2}(\.\d+)?$').hasMatch(c)).toList();
    expect(bad, isEmpty, reason: '非法类别码：${bad.take(5)}');
  });

  test('raw_material.category 只能是 domain 层认识的枚举码', () {
    const allowed = {
      'SUGAR', 'FAT', 'GRAIN', 'MILK', 'EGG', 'NUT', 'SOY',
      'SEAFOOD', 'MEAT', 'FRUIT', 'SALT', 'WATER', 'OTHER',
    };
    final bad = db
        .select('SELECT DISTINCT category FROM raw_material')
        .map((r) => r['category'].toString())
        .where((c) => !allowed.contains(c))
        .toList();
    expect(bad, isEmpty, reason: '中文/未知类别会让 MaterialCategory.fromCode 退化为 other，直接影响 NOVA 判定：$bad');
  });

  test('别名不得占用另一种物质自己的标准名', () {
    final bad = db.select('''
      SELECT aa.alias AS alias, aa.additive_id AS aid, ad.id AS owner
      FROM additive_alias aa JOIN additive ad ON ad.name_zh = aa.alias
      WHERE ad.id != aa.additive_id
    ''');
    expect(bad, isEmpty,
        reason: '同一词指向两个物质会让扣分随行序漂移：'
            '${bad.map((r) => '${r['alias']}→${r['aid']}|${r['owner']}').take(5)}');
  });

  test('population_rule 的 ADDITIVE 目标能在添加剂字典里命中', () {
    final bad = db.select('''
      SELECT target_key FROM population_rule p
      WHERE target_type = 'ADDITIVE'
        AND NOT EXISTS (SELECT 1 FROM additive a WHERE a.name_zh = p.target_key)
    ''');
    expect(bad.map((r) => r['target_key']).toList(), isEmpty);
  });

  test('knowledge_meta.counts 与实际行数一致', () {
    final raw = db.select("SELECT value FROM knowledge_meta WHERE key='counts'").first['value'].toString();
    final counts = jsonDecode(raw) as Map<String, dynamic>;
    final tableOf = {
      'additive': 'additive', 'alias': 'additive_alias', 'usage': 'additive_usage',
      'category': 'food_category', 'allergen': 'allergen', 'nrv': 'nutrient_ref',
      'nutrient_rule': 'nutrient_rule', 'nova_marker': 'nova_marker',
      'population_rule': 'population_rule', 'raw_material': 'raw_material',
      'product_seed': 'food_product_seed', 'product_name_dict': 'product_name_dict',
    };
    for (final e in tableOf.entries) {
      final actual = (db.select('SELECT COUNT(*) AS c FROM ${e.value}').first['c'] as num).toInt();
      expect(counts[e.key], actual, reason: '元数据 counts.${e.key} 与实际行数 ${e.value} 脱节');
    }
  });
}
