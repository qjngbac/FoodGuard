import '../data/knowledge_pack.dart';
import '../data/scoring_constants.dart';
import '../entity/ingredient.dart';
import '../entity/nutrition_facts.dart';
import '../entity/score_result.dart';
import 'additive_scorer.dart';

/// 营养扣分与评价（docs/07 §4）
class NutritionEvaluator {
  NutritionEvaluator(this.pack);

  final KnowledgePack pack;

  /// 计算 NP（负数为正向加成）
  double penalty(NutritionFacts? facts, FoodForm form, List<Ingredient> items) {
    if (facts == null || facts.isEmpty) return 0;
    final scope = form == FoodForm.liquid ? 'LIQUID' : 'SOLID';

    double p = 0;
    p += _band('SODIUM', facts.sodiumMg, scope);
    p += _sugarPenalty(facts, scope, items);
    p += _band('SAT_FAT', facts.saturatedFatG, scope);
    p += _band('FAT', facts.fatG, scope);
    p += _band('TRANS_FAT', facts.transFatG, scope);
    p += _band('ENERGY', facts.energyKj, scope);

    // 正向加成
    p += _bonus('DF', facts.dietaryFiberG, scope);
    p += _bonus('PROTEIN', facts.proteinG, scope);
    if (facts.isSugarFree && !_hasSweetener(items)) p -= 2;

    // 反式脂肪标 0 但含氢化油
    if ((facts.transFatG ?? 0) == 0 && _hasHydrogenatedOil(items)) {
      p += kTransFatZeroButHydrogenatedPenalty;
    }

    if (p < kNpMin) p = kNpMin;
    if (p > kNpMax) p = kNpMax;
    return p;
  }

  double _band(String code, double? value, String scope) {
    if (value == null) return 0;
    final rule = pack.ruleOf(code, scope);
    if (rule == null) return 0;
    if (rule.highValue != null && value >= rule.highValue!) return rule.highPenalty;
    if (rule.midValue != null && value >= rule.midValue!) return rule.midPenalty;
    if (rule.lowValue != null && rule.lowValue! > 0 && value >= rule.lowValue!) {
      return rule.lowPenalty;
    }
    return 0;
  }

  double _sugarPenalty(NutritionFacts facts, String scope, List<Ingredient> items) {
    var sugar = facts.sugarG;
    // 营养成分表可能只有碳水化合物：用 60% 估算，并在 UI 标注
    final estimated = sugar == null && facts.carbohydrateG != null;
    sugar ??= (facts.carbohydrateG ?? 0) * 0.6;
    var p = _band('SUGAR', sugar, scope);
    if (p > 0 && _isNaturalSugarOnly(items)) p *= kNaturalSugarDiscount;
    if (estimated) p *= kNaturalSugarDiscount;
    return p;
  }

  double _bonus(String code, double? value, String scope) {
    if (value == null) return 0;
    final rule = pack.ruleOf(code, scope);
    if (rule == null) return 0;
    if (rule.highValue != null && value >= rule.highValue!) return rule.highPenalty;
    if (rule.midValue != null && value >= rule.midValue!) return rule.midPenalty;
    return 0;
  }

  /// 无任何甜味剂 且 无添加糖原料 → 视为天然糖（乳糖/果糖）
  bool _isNaturalSugarOnly(List<Ingredient> items) {
    if (_hasSweetener(items)) return false;
    for (final i in items) {
      final text = i.rawText;
      for (final k in kAddedSugarKeywords) {
        if (text.contains(k)) return false;
      }
    }
    return true;
  }

  bool _hasSweetener(List<Ingredient> items) => items.any(
        (i) => i.additive != null &&
            AdditiveScorer.functionCode(i.additive!.functionClass) == 'SWEETENER',
      );

  bool _hasHydrogenatedOil(List<Ingredient> items) {
    for (final i in items) {
      for (final k in kHydrogenatedOilKeywords) {
        if (i.rawText.contains(k)) return true;
      }
    }
    return false;
  }

  /// 生成展示用的营养评价
  NutritionEvaluation evaluate(NutritionFacts? facts, FoodForm form, List<Ingredient> items) {
    if (facts == null || facts.isEmpty) {
      return const NutritionEvaluation(items: [], tags: []);
    }
    final scope = form == FoodForm.liquid ? 'LIQUID' : 'SOLID';
    final out = <NutritionItemEval>[];
    final tags = <String>[];

    void add(String code, String name, String unit, double? value, {bool tagHigh = false}) {
      if (value == null) return;
      final ref = pack.refOf(code);
      final nrv = ref?.nrvPercent(value);
      final rule = pack.ruleOf(code, scope);
      String? level;
      if (rule != null && !rule.isBonus) {
        if (rule.highValue != null && value >= rule.highValue!) {
          level = 'high';
          if (tagHigh) tags.add('高$name');
        } else if (rule.midValue != null && value >= rule.midValue!) {
          level = 'mid';
        }
      }
      out.add(NutritionItemEval(
        code: code,
        nameZh: name,
        value: value,
        unit: unit,
        nrvPercent: nrv,
        level: level,
      ));
    }

    add('ENERGY', '能量', 'kJ', facts.energyKj);
    add('PROTEIN', '蛋白质', 'g', facts.proteinG);
    add('FAT', '脂肪', 'g', facts.fatG);
    add('SAT_FAT', '饱和脂肪', 'g', facts.saturatedFatG);
    add('TRANS_FAT', '反式脂肪', 'g', facts.transFatG);
    add('CHO', '碳水化合物', 'g', facts.carbohydrateG);
    add('SUGAR', '糖', 'g', facts.sugarG, tagHigh: true);
    add('DF', '膳食纤维', 'g', facts.dietaryFiberG);
    add('SODIUM', '钠', 'mg', facts.sodiumMg, tagHigh: true);

    if ((facts.transFatG ?? 0) > 0) tags.add('含反式脂肪');
    if ((facts.transFatG ?? 0) == 0 && _hasHydrogenatedOil(items)) {
      tags.add('标0但含氢化油');
    }
    if ((facts.dietaryFiberG ?? 0) >= (form == FoodForm.liquid ? 3 : 6)) tags.add('高纤');
    if ((facts.proteinG ?? 0) >= (form == FoodForm.liquid ? 6 : 12)) tags.add('高蛋白');

    final sodiumRef = pack.refOf('SODIUM');
    return NutritionEvaluation(
      items: out,
      tags: tags,
      sodiumNrv: sodiumRef?.nrvPercent(facts.sodiumMg ?? 0),
      sugarG: facts.sugarG,
    );
  }
}
