import '../data/knowledge_pack.dart';
import '../entity/ingredient.dart';
import '../entity/nutrition_facts.dart';
import '../entity/score_result.dart';
import '../entity/user_profile.dart';

/// 特殊人群建议（docs/07 §8）
class PopulationAdvisor {
  PopulationAdvisor(this.pack);

  final KnowledgePack pack;

  List<PopulationAdvice> advise({
    required List<Ingredient> items,
    required UserProfile profile,
    NutritionFacts? nutrition,
    FoodForm form = FoodForm.solid,
  }) {
    final out = <PopulationAdvice>[];
    if (profile.populationCodes.isEmpty) return out;

    for (final rule in pack.populationRules) {
      if (!profile.populationCodes.contains(rule.populationCode)) continue;

      switch (rule.targetType) {
        case 'ADDITIVE':
          for (final i in items) {
            final a = i.additive;
            if (a == null) continue;
            if (a.nameZh == rule.targetKey || a.nameZh.contains(rule.targetKey)) {
              out.add(PopulationAdvice(
                populationCode: rule.populationCode,
                severity: rule.severity,
                targetName: a.nameZh,
                reasonZh: rule.reasonZh,
              ));
            }
          }
          break;

        case 'INGREDIENT':
          for (final i in items) {
            if (i.rawText.contains(rule.targetKey)) {
              out.add(PopulationAdvice(
                populationCode: rule.populationCode,
                severity: rule.severity,
                targetName: rule.targetKey,
                reasonZh: rule.reasonZh,
              ));
              break;
            }
          }
          break;

        case 'NUTRIENT':
          final value = _nutrientValue(rule.targetKey, nutrition);
          if (value == null) break;
          final threshold = rule.threshold;
          if (threshold == null) break;
          bool over;
          if (rule.thresholdUnit == 'NRV_PERCENT') {
            final ref = pack.refOf(rule.targetKey);
            final pct = ref?.nrvPercent(value);
            over = (pct ?? 0) >= threshold;
          } else if (rule.thresholdUnit == 'g/100g') {
            over = value >= threshold;
          } else {
            over = value >= threshold;
          }
          if (over) {
            out.add(PopulationAdvice(
              populationCode: rule.populationCode,
              severity: rule.severity,
              targetName: _nutrientName(rule.targetKey),
              reasonZh: rule.reasonZh,
            ));
          }
          break;
      }
    }

    // 去重：同人群同目标同严重度只保留一条
    final seen = <String>{};
    final dedup = <PopulationAdvice>[];
    for (final a in out) {
      final key = '${a.populationCode}|${a.targetName}|${a.severity}';
      if (seen.add(key)) dedup.add(a);
    }
    dedup.sort((x, y) => x.severityRank.compareTo(y.severityRank));
    return dedup;
  }

  double? _nutrientValue(String code, NutritionFacts? n) {
    if (n == null) return null;
    return switch (code) {
      'SODIUM' => n.sodiumMg,
      'SUGAR' => n.sugarG,
      'FAT' => n.fatG,
      'SAT_FAT' => n.saturatedFatG,
      'PROTEIN' => n.proteinG,
      _ => null,
    };
  }

  String _nutrientName(String code) {
    final ref = pack.refOf(code);
    return ref?.nameZh ?? code;
  }
}
