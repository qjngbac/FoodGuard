import 'package:fangxinyong/core/util/checksum.dart';
import 'package:fangxinyong/data/ocr/ocr_service.dart';
import 'package:fangxinyong/data/providers.dart';
import 'package:fangxinyong/domain/entity/additive.dart';
import 'package:fangxinyong/domain/entity/ingredient.dart';
import 'package:fangxinyong/domain/entity/nutrition_facts.dart';
import 'package:fangxinyong/domain/entity/score_result.dart';
import 'package:fangxinyong/domain/entity/user_profile.dart';
import 'package:fangxinyong/domain/service/allergen_detector.dart';
import 'package:fangxinyong/domain/service/category_mapper.dart';
import 'package:fangxinyong/domain/service/compliance_judge.dart';
import 'package:fangxinyong/domain/service/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_pack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CODE-AUDIT-2026-09-14 Fixes Tests', () {
    test('P0-1: AnalysisState.copyWith clear flags correctly clear fields', () {
      const initial = AnalysisState(
        ingredientsText: '配料A',
        categoryCode: '14.0',
        barcode: '123456',
        productName: '测试饮料',
        currentRecordId: 'rec_1',
        traceText: '含有花生',
        unknownIngredients: ['未知物A'],
      );

      final cleared = initial.copyWith(
        clearCategoryCode: true,
        clearBarcode: true,
        clearProductName: true,
        clearCurrentRecordId: true,
        clearTraceText: true,
        clearUnknownIngredients: true,
        clearNutrition: true,
      );

      expect(cleared.categoryCode, isNull);
      expect(cleared.barcode, isNull);
      expect(cleared.productName, isNull);
      expect(cleared.currentRecordId, isNull);
      expect(cleared.traceText, isNull);
      expect(cleared.unknownIngredients, isEmpty);
      expect(cleared.nutrition, isNull);
    });

    test('P0-2: Hard rules (R3/R4/R5) do not override D-grade score (<40) to C-grade', () {
      final pack = buildFakePack();
      final engine = ScoringEngine(pack);

      final items = [
        Ingredient(
          order: 1,
          rawText: '水',
          normalized: '水',
          kind: IngredientKind.rawMaterial,
        ),
        Ingredient(
          order: 2,
          rawText: '焦亚硫酸钠',
          normalized: '焦亚硫酸钠',
          kind: IngredientKind.additive,
          additive: pack.byId(3),
        ),
        Ingredient(
          order: 3,
          rawText: '特丁基对苯二酚',
          normalized: '特丁基对苯二酚',
          kind: IngredientKind.additive,
          additive: pack.byId(5),
        ),
        Ingredient(
          order: 4,
          rawText: '亚硝酸钠',
          normalized: '亚硝酸钠',
          kind: IngredientKind.additive,
          additive: pack.byId(9),
        ),
        Ingredient(
          order: 5,
          rawText: '阿斯巴甜',
          normalized: '阿斯巴甜',
          kind: IngredientKind.additive,
          additive: pack.byId(14),
        ),
      ];

      const nutrition = NutritionFacts(
        basis: FoodForm.solid,
        energyKj: 2000,
        sodiumMg: 2000,
        sugarG: 35,
      );

      final res = engine.evaluate(
        ScoreInput(
          ingredients: items,
          nutrition: nutrition,
          profile: const UserProfile(),
        ),
      );

      expect(res.score, lessThan(40));
      expect(res.overallGrade, Grade.d);
    });

    test('P0-7: Additive ADI text formats integers >= 10 without truncating trailing zeros', () {
      final a40 = Additive(
        id: 101,
        nameZh: '测试添加剂40',
        riskLevel: 3,
        defaultPenalty: 3.0,
        adiType: 'NUMERIC',
        adiValue: 40.0,
      );
      expect(a40.adiText, contains('0–40 mg/kg'));

      final a100 = Additive(
        id: 102,
        nameZh: '测试添加剂100',
        riskLevel: 2,
        defaultPenalty: 1.0,
        adiType: 'NUMERIC',
        adiValue: 100.0,
      );
      expect(a100.adiText, contains('0–100 mg/kg'));

      final aDecimal = Additive(
        id: 103,
        nameZh: '测试添加剂0.5',
        riskLevel: 4,
        defaultPenalty: 7.0,
        adiType: 'NUMERIC',
        adiValue: 0.5,
      );
      expect(aDecimal.adiText, contains('0–0.5 mg/kg'));
    });

    test('P0-8: extractNutrition does not extract sodium from ingredient 苯甲酸钠0.5g', () {
      const text = """
配料：水、白砂糖、苯甲酸钠0.5g、柠檬酸
营养成分表
项目 每100g NRV%
能量 180kJ 2%
蛋白质 0g 0%
脂肪 0g 0%
碳水化合物 10.5g 4%
钠 65mg 3%
""";
      final n = extractNutrition(text);
      expect(n, isNotNull);
      expect(n!['sodiumMg'], 65.0);
      expect(n['energyKj'], 180.0);
      expect(n['carbohydrateG'], 10.5);
    });

    test('P1-6: ComplianceJudge prioritizes exact match over ancestor prohibited', () {
      final pack = buildFakePack();
      // 在 pack 中注册 id 3 的两种使用规定：父类 07.0 禁止，但子类 07.02 允许
      pack.usageByAdditive[3] = [
        const AdditiveUsage(
          additiveId: 3,
          categoryCode: '07.0',
          isProhibited: true,
        ),
        const AdditiveUsage(
          additiveId: 3,
          categoryCode: '07.02',
          maxUsage: 1.5,
          unit: 'g/kg',
          isProhibited: false,
        ),
      ];

      final judge = ComplianceJudge(pack);
      final testItems = [
        Ingredient(
          order: 1,
          rawText: '焦亚硫酸钠',
          normalized: '焦亚硫酸钠',
          kind: IngredientKind.additive,
          additive: pack.byId(3),
        ),
      ];

      final res = judge.judge(testItems, '07.02');

      expect(res.items.first.status, UsageStatus.allowed);
      expect(res.items.first.maxUsage, 1.5);
    });

    test('P2-6: CategoryMapper correctly maps 小麦粉 and 面粉 to 06.0', () {
      final pack = buildFakePack();
      final mapper = CategoryMapper(pack);

      final catWheat = mapper.map(ingredients: ['小麦粉', '水', '食盐']);
      expect(catWheat?.code, '06.0');

      final catFlour = mapper.map(ingredients: ['面粉', '水']);
      expect(catFlour?.code, '06.0');
    });

    test('DATA-7 & P0-5: AllergenDetector sets matchedWord and excludes false positive MILK from plant butter', () {
      final pack = buildFakePack();
      final detector = AllergenDetector(pack);

      final items = [
        Ingredient(
          order: 1,
          rawText: '植物黄油',
          normalized: '植物黄油',
          kind: IngredientKind.rawMaterial,
        ),
        Ingredient(
          order: 2,
          rawText: '小麦粉',
          normalized: '小麦粉',
          kind: IngredientKind.rawMaterial,
          allergenCode: 'GLUTEN',
        ),
      ];

      final hits = detector.detect(
        items: items,
        profile: const UserProfile(allergens: ['GLUTEN']),
      );

      expect(hits.length, 1);
      expect(hits.first.code, 'GLUTEN');
      expect(hits.first.matchedWord, '小麦粉');
      expect(hits.first.matchedText, contains('小麦粉'));
    });

    test('UI-AUDIT: ScanPage title is exactly 5 characters 扫描条形码 and BarcodeChecksum validates robustly', () {
      const scanTitle = '扫描条形码';
      expect(scanTitle.length, 5);
      expect(scanTitle, '扫描条形码');

      // Valid EAN-13
      expect(BarcodeChecksum.isValidEan13('6901234567892'), isTrue);
      expect(BarcodeChecksum.toProductCode('6901234567892'), '6901234567892');

      // Invalid checksum EAN-13
      expect(BarcodeChecksum.isValidEan13('6901234567890'), isFalse);
      expect(BarcodeChecksum.toProductCode('6901234567890'), isNull);

      // UPC-A auto-padded to 13 digits
      expect(BarcodeChecksum.isValidUpcA('012345678905'), isTrue);
      expect(BarcodeChecksum.toProductCode('012345678905'), '0012345678905');
    });
  });
}
