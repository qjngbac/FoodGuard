import 'package:fangxinyong/domain/entity/nutrition_facts.dart';
import 'package:fangxinyong/domain/entity/score_result.dart';
import 'package:fangxinyong/domain/entity/user_profile.dart';
import 'package:fangxinyong/domain/service/additive_matcher.dart';
import 'package:fangxinyong/domain/service/ingredient_parser.dart';
import 'package:fangxinyong/domain/service/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_pack.dart';

void main() {
  final pack = buildFakePack();

  ScoreResult run({
    required String ingredients,
    NutritionFacts? nutrition,
    String? categoryCode,
    UserProfile profile = const UserProfile(),
    FoodForm form = FoodForm.solid,
  }) {
    final parsed = IngredientParser().parse(ingredients);
    final items = AdditiveMatcher(pack).match(parsed);
    return ScoringEngine(pack).evaluate(
      ScoreInput(
        ingredients: items,
        nutrition: nutrition,
        foodForm: form,
        categoryCode: categoryCode,
        profile: profile,
        knowledgeVersion: pack.version,
      ),
    );
  }

  group('文档 07 §13 演算样例', () {
    test('样例1 苏打饼干 → 42 分 / C 级', () {
      final r = run(
        ingredients: '小麦粉、植物油、白砂糖、食用盐、碳酸氢钠、焦亚硫酸钠、食用香精、特丁基对苯二酚',
        nutrition: const NutritionFacts(
          energyKj: 2100,
          proteinG: 7.5,
          fatG: 25,
          saturatedFatG: 11,
          transFatG: 0.3,
          carbohydrateG: 62,
          sugarG: 8,
          dietaryFiberG: 2.5,
          sodiumMg: 720,
        ),
        categoryCode: '07.0',
      );

      expect(r.breakdown.additive, closeTo(15.75, 0.2));
      expect(r.breakdown.nutrition, closeTo(30.0, 0.5));
      expect(r.breakdown.processing, closeTo(12.0, 0.1));
      expect(r.score, 42);
      expect(r.overallGrade, Grade.c);
      expect(r.additiveItems.length, 4);
      expect(r.nova.group, 4);
    });

    test('样例2 纯牛奶 → 94 分 / A 级（含天然糖折扣）', () {
      final r = run(
        ingredients: '生牛乳',
        nutrition: const NutritionFacts(
          basis: FoodForm.liquid,
          energyKj: 260,
          proteinG: 3.2,
          fatG: 3.6,
          saturatedFatG: 2.2,
          transFatG: 0,
          carbohydrateG: 4.8,
          sugarG: 4.8,
          sodiumMg: 50,
        ),
        categoryCode: '01.0',
        form: FoodForm.liquid,
      );

      expect(r.breakdown.additive, 0);
      // 糖 4.8g(低档 3 分) × 天然糖折扣 0.5 = 1.5；饱和脂肪 2.2g(中档 5 分)
      expect(r.breakdown.nutrition, closeTo(6.5, 0.2));
      expect(r.nova.group, 1);
      expect(r.score, 94);
      expect(r.overallGrade, Grade.a);
    });

    test('样例3 火腿肠 → C 级（亚硝酸盐 + 高钠高脂）', () {
      final r = run(
        ingredients: '猪肉、水、淀粉、食用盐、白砂糖、大豆蛋白、'
            '食品添加剂（谷氨酸钠、三聚磷酸钠、焦磷酸钠、亚硝酸钠、D-异抗坏血酸钠、红曲红）、香辛料',
        nutrition: const NutritionFacts(
          energyKj: 900,
          proteinG: 10,
          fatG: 15,
          saturatedFatG: 6,
          transFatG: 0,
          carbohydrateG: 8,
          sugarG: 3,
          sodiumMg: 1100,
        ),
        categoryCode: '08.0',
      );

      expect(r.breakdown.nutrition, closeTo(23.5, 0.2));
      expect(r.breakdown.processing, closeTo(12.0, 0.1));
      expect(r.score, inInclusiveRange(44, 52));
      expect(r.overallGrade, Grade.c);
      expect(r.additiveItems.any((e) => e.name == '亚硝酸钠'), isTrue);
    });
  });

  group('硬规则', () {
    test('R1 检出 GB2760-2024 已删除品种 → 直接 D 级', () {
      final r = run(
        ingredients: '小麦粉、水、食用盐、落葵红',
        nutrition: const NutritionFacts(sodiumMg: 100),
      );
      expect(r.overallGrade, Grade.d);
      expect(r.highlights.first, contains('禁止使用'));
    });

    test('R2 明确超范围使用 → D 级（焦亚硫酸钠在肉制品被禁）', () {
      final r = run(
        ingredients: '小麦粉、水、焦亚硫酸钠',
        categoryCode: '08.0',
      );
      expect(r.compliance.level, 'suspected');
      expect(r.overallGrade, Grade.d);
    });

    test('R8 单个 risk4 添加剂 → 至少 B-', () {
      final r = run(
        ingredients: '水、白砂糖、柠檬酸、焦亚硫酸钠',
        nutrition: const NutritionFacts(sugarG: 3, sodiumMg: 20),
        form: FoodForm.liquid,
      );
      expect(r.overallGrade.severity, greaterThanOrEqualTo(Grade.bMinus.severity));
    });
  });

  group('personalGrade 与人群', () {
    test('儿童 + 亚硝酸钠 → 升级到 C', () {
      final r = run(
        ingredients: '猪肉、水、淀粉、亚硝酸钠',
        nutrition: const NutritionFacts(sodiumMg: 100),
        profile: const UserProfile(population: Population.child),
      );
      expect(r.populationAdvices.any((a) => a.severity == 'AVOID'), isTrue);
      expect(r.personalGrade.severity, greaterThanOrEqualTo(Grade.c.severity));
    });

    test('订阅过敏原命中 → 至少 B-', () {
      final r = run(
        ingredients: '小麦粉、水、食用盐',
        nutrition: const NutritionFacts(sodiumMg: 100),
        profile: const UserProfile(allergens: ['GLUTEN']),
      );
      expect(r.allergenHits.any((a) => a.isSubscribed), isTrue);
      expect(r.personalGrade.severity, greaterThanOrEqualTo(Grade.bMinus.severity));
    });
  });

  group('快照序列化（历史记录不重算）', () {
    test('toJson → fromJson 往返后关键字段一致', () {
      final r = run(
        ingredients: '小麦粉、植物油、白砂糖、食用盐、碳酸氢钠、焦亚硫酸钠、食用香精、特丁基对苯二酚',
        nutrition: const NutritionFacts(
          energyKj: 2100,
          proteinG: 7.5,
          fatG: 25,
          saturatedFatG: 11,
          transFatG: 0.3,
          carbohydrateG: 62,
          sugarG: 8,
          sodiumMg: 720,
        ),
        categoryCode: '07.0',
      );

      final json = r.toJson();
      final back = ScoreResult.fromJson(json);

      expect(back.score, r.score);
      expect(back.overallGrade, r.overallGrade);
      expect(back.personalGrade, r.personalGrade);
      expect(back.breakdown.additive, closeTo(r.breakdown.additive, 0.001));
      expect(back.additiveItems.length, r.additiveItems.length);
      expect(back.nova.group, r.nova.group);
      expect(back.highlights, r.highlights);
      expect(back.compliance.items.length, r.compliance.items.length);
      expect(back.nutritionEval?.tags, r.nutritionEval?.tags);
      expect(back.knowledgeVersion, r.knowledgeVersion);
    });

    test('缺失字段的旧快照也能安全还原', () {
      final back = ScoreResult.fromJson(<String, dynamic>{'score': 70});
      expect(back.score, 70);
      expect(back.overallGrade, Grade.b);
      expect(back.additiveItems, isEmpty);
    });
  });

  group('边界', () {
    test('空配料表不崩溃', () {
      final r = run(ingredients: '');
      expect(r.score, greaterThanOrEqualTo(0));
    });

    test('无营养成分表时营养维度为 0 且可信度下降', () {
      final r = run(ingredients: '小麦粉、水、食用盐');
      expect(r.breakdown.nutrition, 0);
      expect(r.nutritionEval, isNull);
      expect(r.confidence, lessThan(1.0));
    });

    test('无食品类别时合规判定为 unknown，且不误报违规', () {
      final r = run(ingredients: '小麦粉、水、山梨酸钾、柠檬酸');
      expect(r.compliance.level, 'unknown');
      expect(r.compliance.items.every((i) => i.status == UsageStatus.unknown), isTrue);
    });
  });
}
