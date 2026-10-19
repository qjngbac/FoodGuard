import '../data/knowledge_pack.dart';
import '../data/scoring_constants.dart';
import '../entity/ingredient.dart';
import '../entity/score_result.dart';
import 'additive_scorer.dart';
import 'allergen_detector.dart';
import 'compliance_judge.dart';
import 'nova_classifier.dart';
import 'nutrition_evaluator.dart';
import 'population_advisor.dart';

/// 安全评级引擎（**项目核心**）docs/07
///
/// 纯 Dart：不得依赖平台 IO / 网络 / 任何数据库实现（见 test/architecture_test.dart）。
class ScoringEngine {
  ScoringEngine(this.pack)
      : _apScorer = AdditiveScorer(),
        _nutrition = NutritionEvaluator(pack),
        _nova = NovaClassifier(pack),
        _allergen = AllergenDetector(pack),
        _population = PopulationAdvisor(pack),
        _compliance = ComplianceJudge(pack);

  final KnowledgePack pack;
  final AdditiveScorer _apScorer;
  final NutritionEvaluator _nutrition;
  final NovaClassifier _nova;
  final AllergenDetector _allergen;
  final PopulationAdvisor _population;
  final ComplianceJudge _compliance;

  ScoreResult evaluate(ScoreInput input) {
    final items = input.ingredients;

    // 1) 添加剂扣分
    final apResult = _apScorer.evaluate(items);
    final ap = apResult.ap;

    // 2) 营养扣分
    final np = _nutrition.penalty(input.nutrition, input.foodForm, items);

    // 3) 加工度
    final nova = _nova.classify(items);
    var pp = nova.penalty;
    if (items.length >= kLongIngredientListThreshold) {
      pp += kLongIngredientListPenalty;
    }
    if (pp > kPpMax) pp = kPpMax;

    // 4) 总分
    final score = (100 - (ap + np + pp)).round().clamp(0, 100);

    // 5) 合规与人群/过敏原
    final compliance = _compliance.judge(items, input.categoryCode);
    final allergenHits = _allergen.detect(
      items: items,
      profile: input.profile,
      traceText: input.traceText,
    );
    final advices = _population.advise(
      items: items,
      profile: input.profile,
      nutrition: input.nutrition,
      form: input.foodForm,
    );

    // 6) 硬规则定级
    final bMinusTrigger = items.any(
      (i) => kBMinusTriggerKeywords.any(
        (k) => i.rawText.contains(k) || (i.additive?.nameZh.contains(k) ?? false),
      ),
    );
    final hasRisk3Plus = items.any((i) => (i.additive?.riskLevel ?? 0) >= 3);
    final grade = _gradeOf(
      score,
      apResult,
      compliance,
      bMinusTrigger,
      novaGroup: nova.group,
      hasRisk3Plus: hasRisk3Plus,
    );

    // 7) 一票否决与硬规则的分数兜底（docs/07 §6：硬规则优先于分数）
    // 杜绝"D 级但安全分仍显示 77 分"这类自相矛盾：等级被硬规则压到某档时，
    // 分数必须落进同一档位；差额单独记成 ruleAdjust，而不是伪造添加剂扣分，
    // 从而保证 score == 100 - (additive + nutrition + processing + ruleAdjust)。
    var finalScore = score;
    var ruleAdjust = 0.0;
    if (grade == Grade.d && finalScore >= kScoreForD) {
      finalScore = 35;
    } else if (grade == Grade.c && finalScore >= kScoreForC) {
      finalScore = 55;
    } else if (grade == Grade.bMinus && finalScore >= kScoreForBMinus) {
      finalScore = 74;
    }
    ruleAdjust = (score - finalScore).toDouble();
    if (ruleAdjust < 0) ruleAdjust = 0;

    // 8) personalGrade
    final personal = _escalate(grade, allergenHits, advices);

    // 9) 明细
    final detailItems = items.where((i) => i.isAdditive).map((i) {
      final a = i.additive!;
      final pos = _apScorer.positionFactor(i);
      return AdditiveScoreItem(
        additiveId: a.id,
        name: a.nameZh,
        displayName: i.rawText,
        functionClass: a.functionClass,
        riskLevel: a.riskLevel,
        riskLevelText: a.riskLevelText,
        penalty: a.defaultPenalty * pos,
        positionFactor: pos,
        order: i.order,
        depth: i.depth,
        riskReasonZh: a.riskReasonZh,
        adiText: a.adiText,
        iarcText: a.iarcText,
        populationFlags: a.populationFlags,
        compliance: complianceItemFor(compliance, a.id),
        insCode: a.insCode,
        euCode: a.euCode,
      );
    }).toList()
      ..sort((x, y) => y.penalty.compareTo(x.penalty));

    final nutritionEval =
        _nutrition.evaluate(input.nutrition, input.foodForm, items);

    return ScoreResult(
      score: finalScore,
      overallGrade: grade,
      personalGrade: personal,
      confidence: _confidence(items, input),
      breakdown: PenaltyBreakdown(
        additive: ap,
        nutrition: np,
        processing: pp,
        additiveShared: apResult.shared,
        ruleAdjust: ruleAdjust,
      ),
      additiveItems: detailItems,
      nutritionEval: input.nutrition == null ? null : nutritionEval,
      nova: nova,
      allergenHits: allergenHits,
      populationAdvices: advices,
      compliance: compliance,
      highlights: _highlights(
        score: finalScore,
        apResult: apResult,
        compliance: compliance,
        allergens: allergenHits,
        advices: advices,
        nova: nova,
        nutritionEval: nutritionEval,
        items: items,
      ),
      knowledgeVersion: input.knowledgeVersion,
      algorithmVersion: kAlgorithmVersion,
      unknownIngredients: items
          .where((i) => i.kind == IngredientKind.unknown)
          .map((i) => i.rawText)
          .toList(),
    );
  }

  ComplianceItem? complianceItemFor(ComplianceResult r, int additiveId) {
    for (final e in r.items) {
      if (e.additiveId == additiveId) return e;
    }
    return null;
  }

  /// 硬规则 R1–R12（docs/07 §6）
  Grade _gradeOf(
    int score,
    ApResult ap,
    ComplianceResult compliance,
    bool bMinusTrigger, {
    required int novaGroup,
    required bool hasRisk3Plus,
  }) {
    // 1) 基于纯分数的基准分档（R6/R7/R10/R11/R12）
    Grade scoreGrade;
    if (score < kScoreForD) {
      scoreGrade = Grade.d;
    } else if (score < kScoreForC) {
      scoreGrade = Grade.c;
    } else if (score < kScoreForBMinus) {
      scoreGrade = Grade.bMinus;
    } else if (score >= kScoreForA &&
        ap.ap <= kApForA &&
        !hasRisk3Plus &&
        novaGroup <= kNovaForA) {
      scoreGrade = Grade.a;
    } else {
      scoreGrade = Grade.b;
    }

    // 2) 硬规则单向恶化判定（docs/07 §6：硬规则优先于分数，只能将评级判定为更差或相同档次，不可逆向优化）
    // R1 检出禁用/非法物质 -> 强制 D
    if (ap.risk5Count > 0) return Grade.d;

    // R2 明确超范围且该物质风险 ≥ 4 -> 强制 D
    final hasProhibitedHighRisk = compliance.items.any(
      (c) => c.status == UsageStatus.prohibited && (pack.byId(c.additiveId)?.riskLevel ?? 0) >= 4,
    );
    if (hasProhibitedHighRisk) return Grade.d;

    // R3/R4/R5 触发 C 级硬门槛 -> 至少为 C 级（若基准分数已入 D 档，保持 D 档）
    if (ap.ap >= kApThresholdForC || ap.risk4InTop || ap.risk4Count >= kRisk4CountForC) {
      return worseOf(scoreGrade, Grade.c);
    }

    // R8/R9 触发 B- 级硬门槛 -> 至少为 B- 级（若基准分数已入更差档位，保持更差档位）
    if (ap.risk4Count >= 1 || bMinusTrigger) {
      return worseOf(scoreGrade, Grade.bMinus);
    }

    return scoreGrade;
  }

  Grade _escalate(
    Grade grade,
    List<AllergenHit> allergens,
    List<PopulationAdvice> advices,
  ) {
    var g = grade;
    if (allergens.any((a) => a.isSubscribed)) {
      g = worseOf(g, Grade.bMinus);
    }
    if (advices.any((a) => a.severity == 'CAUTION')) {
      g = worseOf(g, Grade.bMinus);
    }
    if (advices.any((a) => a.severity == 'AVOID')) {
      g = worseOf(g, Grade.c);
    }
    return g;
  }

  double _confidence(List<Ingredient> items, ScoreInput input) {
    if (items.isEmpty) return 0.3;
    final unknown = items.where((i) => i.kind == IngredientKind.unknown).length;
    final ratio = unknown / items.length;
    var c = 1.0;
    if (ratio > 0.3) {
      c -= 0.20;
    } else if (ratio > 0.1) {
      c -= 0.10;
    }
    if (input.nutrition == null || input.nutrition!.isEmpty) c -= 0.15;
    if (input.categoryCode == null) c -= 0.10;
    if (items.length < 3) c -= 0.15;
    return c.clamp(0.30, 1.00);
  }

  List<String> _highlights({
    required int score,
    required ApResult apResult,
    required ComplianceResult compliance,
    required List<AllergenHit> allergens,
    required List<PopulationAdvice> advices,
    required NovaResult nova,
    required NutritionEvaluation nutritionEval,
    required List<Ingredient> items,
  }) {
    final out = <String>[];

    final risk5Names = items
        .where((i) => (i.additive?.riskLevel ?? 0) == 5)
        .map((i) => i.additive!.nameZh)
        .toSet()
        .toList();
    if (risk5Names.isNotEmpty) {
      out.add('检出国家禁止使用（或 GB 2760-2024 已删除）的物质：${risk5Names.join('、')}，不建议食用。');
    }

    final prohibited = compliance.items.where((c) => c.status == UsageStatus.prohibited).toList();
    if (prohibited.isNotEmpty) {
      out.add('${prohibited.map((e) => e.additiveName).join('、')} 在 GB 2760 中不得用于该食品类别，疑似超范围使用。');
    }

    final risk4Names = items
        .where((i) => (i.additive?.riskLevel ?? 0) == 4)
        .map((i) => i.additive!.nameZh)
        .toSet()
        .toList();
    if (risk4Names.isNotEmpty) {
      out.add('检出 ${risk4Names.length} 种较高关注度添加剂（${risk4Names.take(3).join('、')}'
          '${risk4Names.length > 3 ? ' 等' : ''}）：国标仍允许在指定范围内使用，'
          '儿童、孕妇及慢病人群建议控制摄入频次。');
    }

    final subAllergens = allergens.where((a) => a.isSubscribed).toList();
    if (subAllergens.isNotEmpty) {
      out.add('含你关注的过敏原：${subAllergens.map((e) => e.nameZh).join('、')}。');
    }

    final avoid = advices.where((a) => a.severity == 'AVOID').toList();
    if (avoid.isNotEmpty) {
      out.add('对你的情况需要避免：${avoid.take(2).map((e) => e.targetName).join('、')}。');
    }

    if (nova.group == 4) {
      out.add('属于超加工食品（NOVA 4），添加剂或深加工原料较多。');
    }

    if (nutritionEval.tags.contains('高钠')) {
      final pct = nutritionEval.sodiumNrv?.round();
      out.add('钠含量偏高${pct != null ? '（NRV $pct%）' : ''}，建议控制食用量。');
    }
    if (nutritionEval.tags.contains('高糖')) {
      out.add('糖含量偏高（${(nutritionEval.sugarG ?? 0).toStringAsFixed(1)} g/100g(mL)），建议少食。');
    }
    if (nutritionEval.tags.contains('标0但含氢化油')) {
      out.add('营养成分表标注反式脂肪为 0，但配料含氢化植物油类原料；国标允许 ≤0.3 g/100g 标示为 0。');
    }

    if (apResult.classOnlyNames.isNotEmpty) {
      out.add('配料表只标注了功能类别（${apResult.classOnlyNames.join('、')}），'
          '无法核对具体品种，已按保守方式计入扣分，建议以包装公示或问客服核实。');
    }

    if (apResult.hasMixedSweetener) {
      out.add('同时使用了多种甜味剂，GB 2760-2024 要求混合使用时总量不得超过单一甜味剂的最大使用量。');
    }
    if (apResult.count >= 5) {
      out.add('共识别到 ${apResult.count} 种食品添加剂。');
    }

    if (out.isEmpty) {
      out.add(score >= 85
          ? '配料简单，未检出高风险添加剂，营养指标无明显异常。'
          : '未发现明显的高风险添加剂，可正常食用。');
    }
    return out.take(3).toList();
  }
}
