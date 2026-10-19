import 'ingredient.dart';
import 'nutrition_facts.dart';
import 'user_profile.dart';

/// 安全等级：A 非常健康 / B 安全食用 / B- 孕童少食 / C 含有害物 / D 含致癌物或禁用物
/// unknown 仅用于"没有任何配料数据、尚未评分"的商品，绝不能显示成某个真实等级
enum Grade { a, b, bMinus, c, d, unknown }

extension GradeX on Grade {
  String get label => switch (this) {
        Grade.a => 'A',
        Grade.b => 'B',
        Grade.bMinus => 'B-',
        Grade.c => 'C',
        Grade.d => 'D',
        Grade.unknown => '?',
      };

  String get desc => switch (this) {
        Grade.a => '非常健康',
        Grade.b => '安全食用',
        Grade.bMinus => '孕童少食',
        Grade.c => '含有害物',
        Grade.d => '含禁用/高风险物质',
        Grade.unknown => '未评分（缺少配料表数据）',
      };

  /// 数值越大越差，用于比较与升级
  int get severity => switch (this) {
        Grade.unknown => -1,
        Grade.a => 0,
        Grade.b => 1,
        Grade.bMinus => 2,
        Grade.c => 3,
        Grade.d => 4,
      };

  static Grade fromLabel(String s) => switch (s) {
        'A' => Grade.a,
        'B-' => Grade.bMinus,
        'C' => Grade.c,
        'D' => Grade.d,
        '?' => Grade.unknown,
        _ => Grade.b,
      };
}

/// 取更差的一个等级
Grade worseOf(Grade x, Grade y) => x.severity >= y.severity ? x : y;

/// 合规判定状态
enum UsageStatus {
  allowed,

  /// 国标明确规定不得用于该类别
  prohibited,

  /// 该物质在库中有使用规定，但没有覆盖到当前食品类别（最接近"可能超范围"）
  notListed,

  /// 知识库对该物质没有任何使用规定条目（覆盖度问题，不能暗示违规）
  notCovered,

  unknown,
}

/// 单条添加剂在合规判定中的结果
class ComplianceItem {
  const ComplianceItem({
    required this.additiveId,
    required this.additiveName,
    required this.status,
    this.maxUsage,
    this.unit,
    this.note,
  });

  final int additiveId;
  final String additiveName;
  final UsageStatus status;
  final double? maxUsage;
  final String? unit;
  final String? note;

  factory ComplianceItem.fromJson(Map<String, dynamic> j) => ComplianceItem(
        additiveId: (j['additiveId'] as num?)?.toInt() ?? 0,
        additiveName: j['additiveName']?.toString() ?? '',
        status: UsageStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => UsageStatus.unknown,
        ),
        maxUsage: (j['maxUsage'] as num?)?.toDouble(),
        unit: j['unit']?.toString(),
        note: j['note']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'additiveId': additiveId,
        'additiveName': additiveName,
        'status': status.name,
        'maxUsage': maxUsage,
        'unit': unit,
        'note': note,
      };
}

class ComplianceResult {
  const ComplianceResult({
    required this.level,
    required this.items,
    this.categoryCode,
    this.categoryName,
  });

  /// ok | suspected | unknown
  final String level;
  final List<ComplianceItem> items;
  final String? categoryCode;
  final String? categoryName;

  bool get hasSuspected => items.any((i) => i.status == UsageStatus.prohibited);

  factory ComplianceResult.fromJson(Map<String, dynamic> j) => ComplianceResult(
        level: j['level']?.toString() ?? 'unknown',
        items: (j['items'] as List?)
                ?.map((e) => ComplianceItem.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        categoryCode: j['categoryCode']?.toString(),
        categoryName: j['categoryName']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'level': level,
        'items': items.map((e) => e.toJson()).toList(),
        'categoryCode': categoryCode,
        'categoryName': categoryName,
      };
}

/// 单个添加剂的评分明细
class AdditiveScoreItem {
  const AdditiveScoreItem({
    required this.additiveId,
    required this.name,
    required this.displayName,
    required this.functionClass,
    required this.riskLevel,
    required this.riskLevelText,
    required this.penalty,
    required this.positionFactor,
    required this.order,
    required this.depth,
    this.riskReasonZh,
    this.adiText,
    this.iarcText,
    this.populationFlags = const [],
    this.compliance,
    this.insCode,
    this.euCode,
  });

  final int additiveId;
  final String name;
  final String displayName;
  final String? functionClass;
  final int riskLevel;
  final String riskLevelText;
  final double penalty;
  final double positionFactor;
  final int order;
  final int depth;
  final String? riskReasonZh;
  final String? adiText;
  final String? iarcText;
  final List<String> populationFlags;
  final ComplianceItem? compliance;
  final String? insCode;
  final String? euCode;

  factory AdditiveScoreItem.fromJson(Map<String, dynamic> j) => AdditiveScoreItem(
        additiveId: (j['additiveId'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        displayName: j['displayName']?.toString() ?? j['name']?.toString() ?? '',
        functionClass: j['functionClass']?.toString(),
        riskLevel: (j['riskLevel'] as num?)?.toInt() ?? 3,
        riskLevelText: j['riskLevelText']?.toString() ?? '中',
        penalty: (j['penalty'] as num?)?.toDouble() ?? 0,
        positionFactor: (j['positionFactor'] as num?)?.toDouble() ?? 1,
        order: (j['order'] as num?)?.toInt() ?? 0,
        depth: (j['depth'] as num?)?.toInt() ?? 0,
        riskReasonZh: j['riskReasonZh']?.toString(),
        adiText: j['adiText']?.toString(),
        iarcText: j['iarcText']?.toString(),
        populationFlags: (j['populationFlags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        compliance: j['compliance'] is Map
            ? ComplianceItem.fromJson(Map<String, dynamic>.from(j['compliance'] as Map))
            : null,
        insCode: j['insCode']?.toString(),
        euCode: j['euCode']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'additiveId': additiveId,
        'name': name,
        'displayName': displayName,
        'functionClass': functionClass,
        'riskLevel': riskLevel,
        'riskLevelText': riskLevelText,
        'penalty': penalty,
        'positionFactor': positionFactor,
        'order': order,
        'depth': depth,
        'riskReasonZh': riskReasonZh,
        'adiText': adiText,
        'iarcText': iarcText,
        'populationFlags': populationFlags,
        'insCode': insCode,
        'euCode': euCode,
        'compliance': compliance?.toJson(),
      };
}

/// 过敏原命中
class AllergenHit {
  const AllergenHit({
    required this.code,
    required this.nameZh,
    required this.matchedText,
    this.matchedWord = '',
    this.isTrace = false,
    this.isSubscribed = false,
  });

  final String code;
  final String nameZh;
  final String matchedText;

  /// 配料表中实际匹配的词汇（如 "小麦粉"、"牛奶"），用于配料原文精准高亮
  final String matchedWord;
  final bool isTrace;
  final bool isSubscribed;

  factory AllergenHit.fromJson(Map<String, dynamic> j) => AllergenHit(
        code: j['code']?.toString() ?? '',
        nameZh: j['nameZh']?.toString() ?? '',
        matchedText: j['matchedText']?.toString() ?? '',
        matchedWord: j['matchedWord']?.toString() ?? '',
        isTrace: j['isTrace'] == true,
        isSubscribed: j['isSubscribed'] == true,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'nameZh': nameZh,
        'matchedText': matchedText,
        'matchedWord': matchedWord,
        'isTrace': isTrace,
        'isSubscribed': isSubscribed,
      };
}

/// 特殊人群建议
class PopulationAdvice {
  const PopulationAdvice({
    required this.populationCode,
    required this.severity,
    required this.targetName,
    required this.reasonZh,
  });

  /// AVOID | LIMIT | CAUTION
  final String severity;
  final String populationCode;
  final String targetName;
  final String reasonZh;

  int get severityRank => switch (severity) {
        'AVOID' => 0,
        'LIMIT' => 1,
        _ => 2,
      };

  factory PopulationAdvice.fromJson(Map<String, dynamic> j) => PopulationAdvice(
        populationCode: j['populationCode']?.toString() ?? '',
        severity: j['severity']?.toString() ?? 'CAUTION',
        targetName: j['targetName']?.toString() ?? '',
        reasonZh: j['reasonZh']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'populationCode': populationCode,
        'severity': severity,
        'targetName': targetName,
        'reasonZh': reasonZh,
      };
}

/// 营养评价
class NutritionEvaluation {
  const NutritionEvaluation({
    required this.items,
    required this.tags,
    this.sodiumNrv,
    this.sugarG,
  });

  final List<NutritionItemEval> items;
  final List<String> tags;
  final double? sodiumNrv;
  final double? sugarG;

  factory NutritionEvaluation.fromJson(Map<String, dynamic> j) => NutritionEvaluation(
        items: (j['items'] as List?)
                ?.map((e) => NutritionItemEval.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        sodiumNrv: (j['sodiumNrv'] as num?)?.toDouble(),
        sugarG: (j['sugarG'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
        'tags': tags,
        'sodiumNrv': sodiumNrv,
        'sugarG': sugarG,
      };
}

class NutritionItemEval {
  const NutritionItemEval({
    required this.code,
    required this.nameZh,
    required this.value,
    required this.unit,
    this.nrvPercent,
    this.level,
  });

  final String code;
  final String nameZh;
  final double? value;
  final String unit;

  /// NRV%
  final double? nrvPercent;

  /// high | mid | low | ok
  final String? level;

  factory NutritionItemEval.fromJson(Map<String, dynamic> j) => NutritionItemEval(
        code: j['code']?.toString() ?? '',
        nameZh: j['nameZh']?.toString() ?? '',
        value: (j['value'] as num?)?.toDouble(),
        unit: j['unit']?.toString() ?? '',
        nrvPercent: (j['nrvPercent'] as num?)?.toDouble(),
        level: j['level']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'nameZh': nameZh,
        'value': value,
        'unit': unit,
        'nrvPercent': nrvPercent,
        'level': level,
      };
}

/// NOVA 加工度结果
class NovaResult {
  const NovaResult({required this.group, required this.penalty, this.markers = const []});

  final int group; // 1..4
  final double penalty;
  final List<String> markers;

  factory NovaResult.fromJson(Map<String, dynamic> j) => NovaResult(
        group: (j['group'] as num?)?.toInt() ?? 3,
        penalty: (j['penalty'] as num?)?.toDouble() ?? 6,
        markers: (j['markers'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'group': group,
        'penalty': penalty,
        'markers': markers,
      };
}

/// 扣分构成（保证 score == 100 - total）
class PenaltyBreakdown {
  const PenaltyBreakdown({
    required this.additive,
    required this.nutrition,
    required this.processing,
    this.additiveShared = 0,
    this.ruleAdjust = 0,
  });

  final double additive;
  final double nutrition;
  final double processing;

  /// additive 里无法归到某个具体物质头上的部分（数量放大/同类叠加/只标功能类别名）
  final double additiveShared;

  /// 硬规则一票否决带来的额外扣分（等级比分数更差时，把分数拉进对应档位）
  final double ruleAdjust;

  /// 能逐条对应到具体添加剂的扣分
  double get additiveItemsOnly => additive - additiveShared;

  double get total => additive + nutrition + processing + ruleAdjust;

  factory PenaltyBreakdown.fromJson(Map<String, dynamic> j) => PenaltyBreakdown(
        additive: (j['additive'] as num?)?.toDouble() ?? 0,
        nutrition: (j['nutrition'] as num?)?.toDouble() ?? 0,
        processing: (j['processing'] as num?)?.toDouble() ?? 0,
        additiveShared: (j['additiveShared'] as num?)?.toDouble() ?? 0,
        ruleAdjust: (j['ruleAdjust'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'additive': additive,
        'nutrition': nutrition,
        'processing': processing,
        'additiveShared': additiveShared,
        'ruleAdjust': ruleAdjust,
      };
}

/// 最终评分结果（可完整 JSON 序列化，作为历史快照）
class ScoreResult {
  const ScoreResult({
    required this.score,
    required this.overallGrade,
    required this.personalGrade,
    required this.confidence,
    required this.breakdown,
    required this.additiveItems,
    required this.nova,
    required this.allergenHits,
    required this.populationAdvices,
    required this.compliance,
    required this.highlights,
    required this.knowledgeVersion,
    required this.algorithmVersion,
    this.nutritionEval,
    this.unknownIngredients = const [],
  });

  final int score;
  final Grade overallGrade;
  final Grade personalGrade;
  final double confidence;
  final PenaltyBreakdown breakdown;
  final List<AdditiveScoreItem> additiveItems;
  final NutritionEvaluation? nutritionEval;
  final NovaResult nova;
  final List<AllergenHit> allergenHits;
  final List<PopulationAdvice> populationAdvices;
  final ComplianceResult compliance;
  final List<String> highlights;
  final String knowledgeVersion;
  final String algorithmVersion;

  /// 未收录（无法识别）的配料原文列表（持久化于快照）
  final List<String> unknownIngredients;

  /// 完整快照：包含渲染结果页所需的全部字段
  /// （历史记录存这个 JSON，重新打开时直接还原，不重算）
  Map<String, dynamic> toJson() => {
        'score': score,
        'overallGrade': overallGrade.label,
        'personalGrade': personalGrade.label,
        'confidence': confidence,
        'breakdown': breakdown.toJson(),
        'additiveItems': additiveItems.map((e) => e.toJson()).toList(),
        'nova': nova.toJson(),
        'allergenHits': allergenHits.map((e) => e.toJson()).toList(),
        'populationAdvices': populationAdvices.map((e) => e.toJson()).toList(),
        'compliance': compliance.toJson(),
        'highlights': highlights,
        'knowledgeVersion': knowledgeVersion,
        'algorithmVersion': algorithmVersion,
        'nutritionEval': nutritionEval?.toJson(),
        'unknownIngredients': unknownIngredients,
      };

  factory ScoreResult.fromJson(Map<String, dynamic> j) => ScoreResult(
        score: (j['score'] as num?)?.toInt() ?? 0,
        overallGrade: GradeX.fromLabel(j['overallGrade']?.toString() ?? 'B'),
        personalGrade: GradeX.fromLabel(j['personalGrade']?.toString() ?? 'B'),
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.6,
        breakdown: j['breakdown'] is Map
            ? PenaltyBreakdown.fromJson(Map<String, dynamic>.from(j['breakdown'] as Map))
            : const PenaltyBreakdown(additive: 0, nutrition: 0, processing: 0),
        additiveItems: (j['additiveItems'] as List?)
                ?.map((e) => AdditiveScoreItem.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        nova: j['nova'] is Map
            ? NovaResult.fromJson(Map<String, dynamic>.from(j['nova'] as Map))
            : const NovaResult(group: 3, penalty: 6),
        allergenHits: (j['allergenHits'] as List?)
                ?.map((e) => AllergenHit.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        populationAdvices: (j['populationAdvices'] as List?)
                ?.map((e) => PopulationAdvice.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        compliance: j['compliance'] is Map
            ? ComplianceResult.fromJson(Map<String, dynamic>.from(j['compliance'] as Map))
            : const ComplianceResult(level: 'unknown', items: []),
        highlights: (j['highlights'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        knowledgeVersion: j['knowledgeVersion']?.toString() ?? 'unknown',
        algorithmVersion: j['algorithmVersion']?.toString() ?? 'unknown',
        nutritionEval: j['nutritionEval'] is Map
            ? NutritionEvaluation.fromJson(Map<String, dynamic>.from(j['nutritionEval'] as Map))
            : null,
        unknownIngredients: (j['unknownIngredients'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

/// 评分输入
class ScoreInput {
  const ScoreInput({
    required this.ingredients,
    required this.profile,
    this.nutrition,
    this.foodForm = FoodForm.solid,
    this.categoryCode,
    this.traceText,
    this.knowledgeVersion = 'unknown',
  });

  final List<Ingredient> ingredients;
  final NutritionFacts? nutrition;
  final FoodForm foodForm;
  final String? categoryCode;
  final UserProfile profile;
  final String knowledgeVersion;

  /// "可能含有…"交叉污染提示语（来自包装标示或 OCR）
  final String? traceText;
}
