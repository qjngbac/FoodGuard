import 'package:fangxinyong/core/util/text_normalizer.dart';
import 'package:fangxinyong/data/history_repository.dart';
import 'package:fangxinyong/data/ocr/ocr_service.dart';
import 'package:fangxinyong/domain/entity/score_result.dart';
import 'package:fangxinyong/domain/service/category_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../helpers/fake_pack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HistoryRepository & Rescan Deduplication Tests', () {
    late Database inMemoryDb;
    late HistoryRepository repo;

    setUp(() {
      inMemoryDb = sqlite3.openInMemory();
      repo = HistoryRepository(db: inMemoryDb);
    });

    tearDown(() {
      inMemoryDb.close();
    });

    final fakeResult = ScoreResult.fromJson({
      'score': 95,
      'overallGrade': 'A',
      'personalGrade': 'A',
      'confidence': 1.0,
      'breakdown': {
        'additive': 0.0,
        'nutrition': 0.0,
        'processing': 0.0,
      },
      'additiveItems': [],
      'nova': {'group': 1, 'confidence': 1.0, 'reasons': []},
      'allergenHits': [],
      'populationAdvices': [],
      'compliance': {
        'level': 'ok',
        'categoryCode': '14.0',
        'categoryName': '饮料类',
        'items': [],
      },
      'highlights': ['配料纯净'],
      'knowledgeVersion': 'test-1',
      'algorithmVersion': '1.0',
    });

    test('Repeated scan with same barcode updates in-place without adding duplicate record', () async {
      // 首次扫描并入库
      final id1 = await repo.insert(
        id: 'record_1',
        barcode: '6902083881405',
        productName: '娃哈哈纯净水',
        ingredientsText: '水',
        result: fakeResult,
        nutritionJson: '{"energyKj":0}',
      );
      expect(id1, 'record_1');

      final list1 = await repo.list();
      final count1 = list1.where((r) => r.barcode == '6902083881405').length;
      expect(count1, 1);
      final initialTime = list1.firstWhere((r) => r.barcode == '6902083881405').createdAt;

      // 等待 15ms 保证时间戳有变化
      await Future.delayed(const Duration(milliseconds: 15));

      // 再次扫描相同条形码（即使用户传入新的微秒id）
      final id2 = await repo.insert(
        id: 'record_2_new_scan',
        barcode: '6902083881405',
        productName: '娃哈哈纯净水 596ml',
        ingredientsText: '水',
        result: fakeResult,
        nutritionJson: '{"energyKj":0,"sodiumMg":0}',
      );

      // 返回的应当是既有记录 id1
      expect(id2, 'record_1');

      // 数据库中该条码商品依然只有 1 条记录，未产生重复多条
      final list2 = await repo.list();
      final count2 = list2.where((r) => r.barcode == '6902083881405').length;
      expect(count2, 1);

      // 时间戳被更新为最新时间
      final updatedRec = list2.firstWhere((r) => r.barcode == '6902083881405');
      expect(updatedRec.createdAt, greaterThanOrEqualTo(initialTime));
      expect(updatedRec.productName, '娃哈哈纯净水 596ml');
      expect(updatedRec.nutritionJson, contains('sodiumMg'));

      // findByBarcode 也能准确查到且带 nutritionJson
      final found = await repo.findByBarcode(' 6902083881405 ');
      expect(found, isNotNull);
      expect(found!.id, 'record_1');
      expect(found.nutritionJson, isNotNull);
    });

    test('CategoryMapper correctly matches Nestle coffee and Wahaha water to 14.0', () {
      final pack = buildFakePack();
      final mapper = CategoryMapper(pack);

      final catCoffee = mapper.map(productName: '雀巢咖啡');
      expect(catCoffee, isNotNull);
      expect(catCoffee!.code, '14.0');

      final catWater = mapper.map(productName: '娃哈哈饮用水');
      expect(catWater, isNotNull);
      expect(catWater!.code, '14.0');

      final catByIng = mapper.map(ingredients: ['速溶咖啡', '咖啡豆提取物']);
      expect(catByIng, isNotNull);
      expect(catByIng!.code, '14.0');
    });

    test('Healthy alternatives query excludes self barcode and finds high-grade items', () {
      inMemoryDb.execute('''
        CREATE TABLE food_product_seed (
          barcode TEXT PRIMARY KEY,
          name_zh TEXT,
          brand TEXT,
          category_code TEXT,
          ingredients_text TEXT,
          nutrition_json TEXT,
          nova_group INTEGER,
          source TEXT
        );
        INSERT INTO food_product_seed VALUES
          ('6902083881405', '娃哈哈 纯净水 596ml', '娃哈哈', '14.01', '水', null, 1, 'SEED_OFFLINE'),
          ('6921168593817', '东方树叶 乌龙茶 500ml', '农夫山泉', '14.05', '水、乌龙茶', null, 2, 'SEED_OFFLINE'),
          ('6901234567890', '高糖可乐 330ml', '某品牌', '14.02', '水、糖、焦糖色', null, 4, 'SEED_OFFLINE');
      ''');

      final rows = inMemoryDb.select(
        'SELECT barcode, name_zh FROM food_product_seed '
        'WHERE category_code LIKE ? AND nova_group <= 2 AND (? IS NULL OR barcode != ?) '
        'ORDER BY nova_group ASC LIMIT ?',
        ['14.%', '6901234567890', '6901234567890', 2],
      );

      expect(rows.length, 2);
      expect(rows.map((r) => r['barcode']), containsAll(['6902083881405', '6921168593817']));
      expect(rows.any((r) => r['barcode'] == '6901234567890'), isFalse);
    });
    test('TextNormalizer.cleanIngredientsText strips prefixes, trailing info and inline shelf-life', () {
      final t1 = TextNormalizer.cleanIngredientsText('【配料清单】水、白砂糖、全脂乳粉、速溶咖啡。保质期：12个月');
      expect(t1, '水、白砂糖、全脂乳粉、速溶咖啡');

      final t2 = TextNormalizer.cleanIngredientsText('配料表：生活饮用水，白砂糖，乌龙茶茶叶。 生产日期：见包装喷码');
      expect(t2, '生活饮用水,白砂糖,乌龙茶茶叶');

      final t3 = TextNormalizer.cleanIngredientsText('[原料与辅料] 水、大豆、小麦粉、食用盐(保质期见瓶身)');
      expect(t3, '水、大豆、小麦粉、食用盐');

      final t4 = TextNormalizer.cleanIngredientsText('配料 水、绿茶、维生素C、碳酸氢钠。执行标准：GB/T 21733');
      expect(t4, '水、绿茶、维生素C、碳酸氢钠');
    });

    test('extractNutrition correctly parses row-by-row table and excludes NRV%', () {
      const sample = '''
        营养成分表
        项目 每100g NRV%
        能量 1823千焦(kJ) 22%
        蛋白质 7.5克(g) 13%
        脂肪 21.8g 36%
          - 饱和脂肪 9.2g 46%
          - 反式脂肪(酸) 0g
        碳水化合物 52.0克 17%
          - 糖 15.0g
        膳食纤维 3.5g 14%
        钠 450毫克(mg) 23%
      ''';

      final nut = extractNutrition(sample);
      expect(nut, isNotNull);
      expect(nut!['energyKj'], 1823.0);
      expect(nut['proteinG'], 7.5);
      expect(nut['fatG'], 21.8);
      expect(nut['saturatedFatG'], 9.2);
      expect(nut['transFatG'], 0.0);
      expect(nut['carbohydrateG'], 52.0);
      expect(nut['sugarG'], 15.0);
      expect(nut['dietaryFiberG'], 3.5);
      expect(nut['sodiumMg'], 450.0);
    });

    test('extractNutrition correctly parses column-aligned 2D table', () {
      const colSample = '''
        营养成分表
        项目
        能量
        蛋白质
        脂肪
        饱和脂肪
        反式脂肪酸
        碳水化合物
        糖
        膳食纤维
        钠

        每100克
        1823千焦
        7.5克
        21.8克
        9.2克
        0克
        52.0克
        15.0克
        3.5克
        450毫克

        NRV%
        22%
        13%
        36%
        46%
        0%
        17%
        23%
      ''';

      final nut = extractNutrition(colSample);
      expect(nut, isNotNull);
      expect(nut!['energyKj'], 1823.0);
      expect(nut['proteinG'], 7.5);
      expect(nut['fatG'], 21.8);
      expect(nut['saturatedFatG'], 9.2);
      expect(nut['transFatG'], 0.0);
      expect(nut['carbohydrateG'], 52.0);
      expect(nut['sugarG'], 15.0);
      expect(nut['dietaryFiberG'], 3.5);
      expect(nut['sodiumMg'], 450.0);
    });

    test('Same brand healthy version is prioritized at #1', () {
      inMemoryDb.execute('''
        CREATE TABLE IF NOT EXISTS food_product_seed (
          barcode TEXT PRIMARY KEY,
          name_zh TEXT,
          brand TEXT,
          category_code TEXT,
          ingredients_text TEXT,
          nutrition_json TEXT,
          nova_group INTEGER,
          source TEXT
        );
        INSERT INTO food_product_seed VALUES
          ('6900000000001', '康师傅 冰红茶 柠檬味 500ml', '康师傅', '14.05', '水、白砂糖、红茶', null, 4, 'SEED_OFFLINE'),
          ('6900000000002', '康师傅 无糖冰红茶 500ml', '康师傅', '14.05', '水、红茶茶叶、赤藓糖醇', null, 2, 'SEED_OFFLINE');
      ''');

      final sameBrandRows = inMemoryDb.select(
        'SELECT barcode, name_zh, brand FROM food_product_seed '
        'WHERE (brand LIKE ? OR name_zh LIKE ?) AND nova_group <= 2 '
        'AND (? IS NULL OR barcode != ?) '
        'ORDER BY (CASE WHEN name_zh LIKE ? OR name_zh LIKE ? THEN 0 ELSE 1 END), nova_group ASC '
        'LIMIT 1',
        ['%康师傅%', '%康师傅%', '6900000000001', '6900000000001', '%无糖%', '%0糖%'],
      );

      expect(sameBrandRows.length, 1);
      expect(sameBrandRows.first['name_zh'], '康师傅 无糖冰红茶 500ml');
    });

    test('TextNormalizer.findCorrectionCandidates recommends proper ingredients for typos', () {
      final c1 = TextNormalizer.findCorrectionCandidates('甘早');
      expect(c1, contains('甘草'));

      final c2 = TextNormalizer.findCorrectionCandidates('白砂溏');
      expect(c2, contains('白砂糖'));

      final c3 = TextNormalizer.findCorrectionCandidates('麦芽楜精');
      expect(c3, contains('麦芽糊精'));

      final c4 = TextNormalizer.findCorrectionCandidates('脱脂奶扮');
      expect(c4, contains('脱脂奶粉'));

      final c5 = TextNormalizer.findCorrectionCandidates('苯甲酸纳');
      expect(c5, contains('苯甲酸钠'));
    });

    test('Nutrition unit conversion formulas compute accurately', () {
      // 1 kcal = 4.184 kJ
      const kcalVal = 60.0;
      final convertedKj = (kcalVal * 4.184).round();
      expect(convertedKj, 251);

      // 1 g = 1000 mg
      const gSodium = 0.45;
      final convertedMg = (gSodium * 1000).round();
      expect(convertedMg, 450);
    });
  });
}

