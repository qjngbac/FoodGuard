import '../data/knowledge_pack.dart';
import '../data/scoring_constants.dart';
import '../entity/ingredient.dart';

/// 添加剂扣分计算结果
class ApResult {
  const ApResult({
    required this.ap,
    required this.shared,
    required this.count,
    required this.risk4Count,
    required this.risk5Count,
    required this.risk4InTop,
    required this.hasMixedSweetener,
    this.classOnlyNames = const [],
  });

  final double ap;

  /// 无法摊到具体物质头上的扣分：数量放大 + 同类叠加 + 混合甜味剂 + 只标功能类别名
  final double shared;
  final int count;
  final int risk4Count;
  final int risk5Count;
  final bool risk4InTop;
  final bool hasMixedSweetener;

  /// 配料表只写了功能类别名（如"乳化剂"）而未标注具体品种
  final List<String> classOnlyNames;
}

/// 添加剂扣分（docs/07 §3）
class AdditiveScorer {
  /// 位置因子
  double positionFactor(Ingredient item) {
    if (item.percent != null) {
      final byPercent = (0.6 + item.percent! / 25).clamp(0.6, 1.4);
      final byOrder = _factorByOrder(item.order);
      return byPercent > byOrder ? byPercent : byOrder;
    }
    final f = _factorByOrder(item.order);
    return item.depth > 0 ? f * kCompositeDiscount : f;
  }

  double _factorByOrder(int order) {
    if (order <= 1) return kPositionFactorByOrder[1]!;
    if (order <= 3) return kPositionFactorByOrder[3]!;
    if (order <= 8) return kPositionFactorByOrder[8]!;
    if (order <= 15) return kPositionFactorByOrder[15]!;
    return kPositionFactorTail;
  }

  /// 数量放大系数
  double countFactor(int n) {
    if (n <= 2) return kCountFactorByCount[2]!;
    if (n <= 4) return kCountFactorByCount[4]!;
    if (n <= 7) return kCountFactorByCount[7]!;
    return kCountFactorTail;
  }

  /// 功能类别码
  static String functionCode(String? functionClassZh) =>
      kFunctionClassCode[functionClassZh] ?? 'OTHER';

  /// 同类叠加惩罚
  double stackingPenalty(List<Ingredient> additives) {
    final groups = <String, Set<int>>{};
    for (final i in additives) {
      final a = i.additive;
      if (a == null) continue;
      groups.putIfAbsent(functionCode(a.functionClass), () => <int>{}).add(a.id);
    }
    double sum = 0;
    groups.forEach((code, ids) {
      final k = ids.length;
      if (k < 2) return;
      final table = kStackingByFunction[code] ?? kStackingOther;
      sum += k == 2 ? table[0] : (k == 3 ? table[1] : table[2]);
    });
    return sum;
  }

  /// 甜味剂混合使用（GB2760-2024 总量控制）
  bool hasMixedSweeteners(List<Ingredient> additives) {
    final names = additives
        .where((i) => i.additive != null && functionCode(i.additive!.functionClass) == 'SWEETENER')
        .map((i) => i.additive!.nameZh)
        .toSet();
    final hasAspartame = names.any((n) => n.contains('阿斯巴甜'));
    final hasAceK = names.any((n) => n.contains('安赛蜜'));
    final hasSalt = names.any((n) => n.contains('天门冬酰'));
    return (hasAspartame && hasAceK) || (hasSalt && (hasAspartame || hasAceK));
  }

  /// 配料表里只写功能类别名、没写具体物质的配料（GB 2760 允许复合配料只标类别）
  static List<String> classOnlyNames(List<Ingredient> ingredients) {
    final out = <String>[];
    for (final i in ingredients) {
      if (i.isAdditive) continue;
      final t = i.normalized;
      if (kFunctionClassOnlyNames.contains(t) && !out.contains(i.rawText.trim())) {
        out.add(i.rawText.trim());
      }
    }
    return out;
  }

  ApResult evaluate(List<Ingredient> ingredients) {
    final additives = ingredients.where((i) => i.isAdditive).toList();
    final classOnly = classOnlyNames(ingredients);
    if (additives.isEmpty && classOnly.isEmpty) {
      return const ApResult(
        ap: 0,
        shared: 0,
        count: 0,
        risk4Count: 0,
        risk5Count: 0,
        risk4InTop: false,
        hasMixedSweetener: false,
      );
    }

    double itemSum = 0;
    for (final i in additives) {
      final a = i.additive!;
      itemSum += a.defaultPenalty * positionFactor(i);
    }
    final n = additives.map((i) => i.additive!.id).toSet().length;
    final scaled = itemSum * countFactor(n);
    final stacking = stackingPenalty(additives);
    final mixed = hasMixedSweeteners(additives);
    final mixedPenalty = mixed ? kMixedSweetenerPenalty : 0.0;
    final classOnlyPenalty = classOnly.length * kClassOnlyPenalty;

    var shared = (scaled - itemSum) + stacking + mixedPenalty + classOnlyPenalty;
    var total = itemSum + shared;
    if (total > kApMax) {
      shared -= (total - kApMax);
      total = kApMax;
    }

    final risk4 = additives.where((i) => (i.additive?.riskLevel ?? 0) == 4).toList();
    final risk5 = additives.where((i) => (i.additive?.riskLevel ?? 0) == 5).toList();

    return ApResult(
      ap: total,
      shared: shared < 0 ? 0 : shared,
      count: n,
      risk4Count: risk4.length,
      risk5Count: risk5.length,
      risk4InTop: risk4.any((i) => i.order <= kRisk4InTopN),
      hasMixedSweetener: mixed,
      classOnlyNames: classOnly,
    );
  }
}

/// 从知识库取功能类别码的便捷方法
String functionCodeOf(KnowledgePack pack, int additiveId) {
  final a = pack.byId(additiveId);
  return AdditiveScorer.functionCode(a?.functionClass);
}
