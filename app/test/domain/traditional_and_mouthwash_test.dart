import 'package:fangxinyong/core/util/checksum.dart';
import 'package:fangxinyong/core/util/text_normalizer.dart';
import 'package:fangxinyong/data/knowledge_repository.dart';
import 'package:fangxinyong/data/ocr/ocr_service.dart';
import 'package:fangxinyong/domain/entity/ingredient.dart';
import 'package:fangxinyong/domain/entity/score_result.dart';
import 'package:fangxinyong/domain/entity/user_profile.dart';
import 'package:fangxinyong/domain/service/additive_matcher.dart';
import 'package:fangxinyong/domain/service/ingredient_parser.dart';
import 'package:fangxinyong/domain/service/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_pack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Traditional Chinese to Simplified (繁转简) Tests', () {
    test('Converts high-frequency food additives and packaging terms to simplified', () {
      const trad = '食用鹽、小麥麵粉、白砂糖、棕櫚油、脫脂乳粉、山梨酸鉀、檸檬酸鈉、著色劑、甜味劑、防腐劑';
      final simp = TextNormalizer.toSimplified(trad);
      expect(simp, '食用盐、小麦面粉、白砂糖、棕榈油、脱脂乳粉、山梨酸钾、柠檬酸钠、着色剂、甜味剂、防腐剂');
    });

    test('extractIngredients cleans traditional prefix and converts to simplified', () {
      const trad = '【配料清單】：小麥粉、食用鹽、檸檬酸鈉、山梨酸鉀。(保質期12個月)生產商：食品廠';
      final cleaned = extractIngredients(trad);
      expect(cleaned, '小麦粉、食用盐、柠檬酸钠、山梨酸钾');
    });

    test('extractNutrition extracts nutrients even when OCR outputs traditional Chinese', () {
      const tradNut = '營養成分表 每100克 能量 2150千焦，蛋白質 6.8克，飽和脂肪 12.5克，總碳水化合物 60克，鈉 580毫克';
      final n = extractNutrition(tradNut);
      expect(n, isNotNull);
      expect(n!['energyKj'], 2150.0);
      expect(n['proteinG'], 6.8);
      expect(n['saturatedFatG'], 12.5);
      expect(n['carbohydrateG'], 60.0);
      expect(n['sodiumMg'], 580.0);
    });
  });

  group('Grade D Score Capping & Consistency Tests', () {
    test('Grade D products are capped to <= 35 and breakdown matches final score', () {
      final pack = buildFakePack();
      // 故意触发 R2 违规（肉制品 08.0 超范围使用焦亚硫酸钠，焦亚硫酸钠 riskLevel=4）
      final items = AdditiveMatcher(pack).match(
        IngredientParser().parse('小麦粉、水、焦亚硫酸钠'),
      );

      final result = ScoringEngine(pack).evaluate(
        ScoreInput(
          ingredients: items,
          profile: const UserProfile(),
          categoryCode: '08.0',
        ),
      );

      expect(result.overallGrade, Grade.d);
      // 安全分必须在 D 级区间 (< 40)，不得出现 77 等高分
      expect(result.score, lessThanOrEqualTo(35));
      // 扣分必须能开账：score == 100 - (添加剂 + 营养 + 加工度 + 硬规则修正)
      expect(result.breakdown.total, closeTo(100 - result.score, 0.5));
      // 硬规则的差额记在 ruleAdjust 上，不得伪造进某个添加剂的扣分
      expect(result.breakdown.additiveItemsOnly,
          closeTo(result.additiveItems.fold(0.0, (s, e) => s + e.penalty), 0.51));
    });
  });

  group('Ingredient Parser & Mouthwash Recognition Tests', () {
    test('Embedded brackets in ingredient names stay intact without broken pieces', () {
      final parser = IngredientParser();
      final items = parser.parse('水、山梨(糖)醇、香蜜桃 (PRUNUS PERSICA NECTARINA) 果提取物、薄荷醇');

      expect(items.length, 4);
      expect(items[0].rawText, '水');
      expect(items[1].rawText, '山梨(糖)醇');
      expect(items[1].normalized, '山梨醇');
      expect(items[2].rawText, '香蜜桃 (PRUNUS PERSICA NECTARINA) 果提取物');
      expect(items[2].normalized, '香蜜桃果提取物');
      expect(items[3].rawText, '薄荷醇');
    });

    test('All mouthwash ingredients are matched and recognized via KnowledgeRepository', () async {
      final repo = KnowledgeRepository();
      final pack = await repo.load();

      const mouthwashText =
          '水、山梨(糖)醇、丙二醇、PEG-40氢化蓖麻油、苯甲酸钠、羟苯甲酯、香精、薄荷醇、糖精钠、CI 14700、香蜜桃 (PRUNUS PERSICA NECTARINA) 果提取物、蜂胶提取物、乳酸杆菌';

      final parser = IngredientParser();
      final parsed = parser.parse(mouthwashText);
      final matcher = AdditiveMatcher(pack);
      final matched = matcher.match(parsed);

      final unknowns = matched.where((i) => i.kind == IngredientKind.unknown).toList();

      // 除色素 CI 号外，漱口水配料均应被正确收录；CI 14700 是着色剂，不得被当作天然原料命中
      expect(unknowns.map((e) => e.rawText).toList(), ['CI 14700'],
          reason: '色素 CI 号不允许被识别为 raw material');

      // 验证核心配料的具体分类与识别
      final sorbitol = matched.firstWhere((i) => i.rawText.contains('山梨'));
      expect(sorbitol.kind, IngredientKind.additive);
      expect(sorbitol.additive?.nameZh, '山梨糖醇');

      final paraben = matched.firstWhere((i) => i.rawText == '羟苯甲酯');
      expect(paraben.kind, IngredientKind.additive);
      expect(paraben.additive?.nameZh, '对羟基苯甲酸甲酯');

      final castor = matched.firstWhere((i) => i.rawText.contains('蓖麻油'));
      expect(castor.kind, IngredientKind.rawMaterial);

      final menthol = matched.firstWhere((i) => i.rawText == '薄荷醇');
      expect(menthol.kind, IngredientKind.rawMaterial);

      final propolis = matched.firstWhere((i) => i.rawText == '蜂胶提取物');
      expect(propolis.kind, IngredientKind.rawMaterial);

      final bacteria = matched.firstWhere((i) => i.rawText == '乳酸杆菌');
      expect(bacteria.kind, IngredientKind.rawMaterial);
    });

    test('Green grape milk drink (青提栀子奶) ingredients are 100% recognized with 0 unknowns', () async {
      final repo = KnowledgeRepository();
      final pack = await repo.load();

      // 用户真实拍照商品：生牛乳80%、水、白砂糖、青提汁1%、栀子提取液1%、食品添加剂(蔗糖脂肪酸酯)
      const text = '生牛乳80%、水、白砂糖、青提汁1%、栀子提取液1%、食品添加剂(蔗糖脂肪酸酯)';

      final parser = IngredientParser();
      final parsed = parser.parse(text);
      final matcher = AdditiveMatcher(pack);
      final matched = matcher.match(parsed);

      final unknowns = matched.where((i) => i.kind == IngredientKind.unknown).toList();
      expect(unknowns.map((e) => e.rawText).toList(), isEmpty);

      final grape = matched.firstWhere((i) => i.rawText.contains('青提'));
      expect(grape.kind, IngredientKind.rawMaterial);
      expect(grape.materialCategory, MaterialCategory.fruit);

      final gardenia = matched.firstWhere((i) => i.rawText.contains('栀子'));
      expect(gardenia.kind, IngredientKind.rawMaterial);

      final milk = matched.firstWhere((i) => i.rawText.contains('生牛乳'));
      expect(milk.kind, IngredientKind.rawMaterial);
      expect(milk.allergenCode, 'MILK');

      final ester = matched.firstWhere((i) => i.rawText.contains('蔗糖脂肪酸酯'));
      expect(ester.kind, IngredientKind.additive);
    });

    test('Derivative fruit juice/puree/pulp patterns are recognized as raw materials', () async {
      final repo = KnowledgeRepository();
      final pack = await repo.load();

      const text = '阳光玫瑰葡萄汁、西梅果泥、浓缩白桃汁、草莓果肉、浓缩青提原汁、胡萝卜浓缩汁';
      final parser = IngredientParser();
      final parsed = parser.parse(text);
      final matcher = AdditiveMatcher(pack);
      final matched = matcher.match(parsed);

      final unknowns = matched.where((i) => i.kind == IngredientKind.unknown).toList();
      expect(unknowns, isEmpty);
      for (final item in matched) {
        expect(item.kind, IngredientKind.rawMaterial);
      }
    });

    test('Offline seed barcodes are scannable EAN-13 and queryable offline', () async {
      final repo = KnowledgeRepository();

      for (final code in ['6970873200057', '6901001005817', '6902971230018']) {
        expect(BarcodeChecksum.isValidEan13(code), isTrue,
            reason: '$code 校验位非法，真实扫码器不可能产出它');
      }

      final yuanqi = await repo.findProductByBarcode('6970873200057');
      expect(yuanqi, isNotNull);
      expect(yuanqi!.nameZh, contains('元气森林'));
      expect(yuanqi.hasIngredients, isTrue);

      final masterKong = await repo.findProductByBarcode('6901001005817');
      expect(masterKong, isNotNull);
      expect(masterKong!.nameZh, contains('康师傅'));
      expect(masterKong.hasIngredients, isTrue);

      final wlj = await repo.findProductByBarcode('6902971230018');
      expect(wlj, isNotNull);
      expect(wlj!.nameZh, contains('王老吉'));

      // 校验位非法的商品码不进库：查不到，而不是假装命中
      expect(await repo.findProductByBarcode('6920700201015'), isNull);
    });
  });
}
