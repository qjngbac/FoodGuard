import '../entity/additive.dart';
import '../entity/nutrition_facts.dart';

/// 过敏原（来自 allergen 表）
class Allergen {
  const Allergen({
    required this.code,
    required this.nameZh,
    required this.aliases,
    this.noteZh,
  });

  final String code;
  final String nameZh;
  final List<String> aliases;
  final String? noteZh;
}

/// NOVA 判据词
class NovaMarker {
  const NovaMarker({required this.keyword, this.novaFloor = 4, this.weight = 1.0});

  final String keyword;
  final int novaFloor;
  final double weight;
}

/// 特殊人群规则
class PopulationRule {
  const PopulationRule({
    required this.populationCode,
    required this.targetType,
    required this.targetKey,
    required this.severity,
    this.threshold,
    this.thresholdUnit,
    required this.reasonZh,
  });

  /// ADDITIVE | NUTRIENT | INGREDIENT
  final String targetType;
  final String populationCode;
  final String targetKey;

  /// AVOID | LIMIT | CAUTION
  final String severity;
  final double? threshold;
  final String? thresholdUnit;
  final String reasonZh;
}

/// 普通原料（非添加剂）
class RawMaterial {
  const RawMaterial({
    required this.keyword,
    required this.category,
    this.allergenCode,
  });

  final String keyword;
  final String category;
  final String? allergenCode;
}

/// 装载在内存中的知识库快照（domain 层只依赖它，不依赖任何 IO）
class KnowledgePack {
  KnowledgePack({
    required this.additives,
    required this.usageByAdditive,
    required this.categories,
    required this.allergens,
    required this.nutrientRefs,
    required this.nutrientRules,
    required this.novaMarkers,
    required this.populationRules,
    required this.rawMaterials,
    required this.version,
    this.dataQuality = 'SEED',
  }) {
    for (final a in additives) {
      _byId[a.id] = a;
      _aliasToId[TextKey.of(a.nameZh)] = a.id;
    }
  }

  final List<Additive> additives;
  final Map<int, List<AdditiveUsage>> usageByAdditive;
  final List<FoodCategory> categories;
  final List<Allergen> allergens;
  final List<NutrientRef> nutrientRefs;
  final List<NutrientRule> nutrientRules;
  final List<NovaMarker> novaMarkers;
  final List<PopulationRule> populationRules;
  final List<RawMaterial> rawMaterials;
  final String version;

  /// SEED（种子数据，未核对）/ OFFICIAL（已核对）
  final String dataQuality;

  final Map<int, Additive> _byId = {};
  final Map<String, int> _aliasToId = {};
  final Map<String, List<String>> _aliasesById = {};

  void addAlias(int id, String alias, {double weight = 1.0}) {
    _aliasesById.putIfAbsent('$id', () => <String>[]).add(alias);
    final key = TextKey.of(alias);
    // 已存在时不覆盖（先注册的优先级更高：标准名 > 官方别名 > 俗名）
    _aliasToId.putIfAbsent(key, () => id);
  }

  List<String> aliasesOf(int id) => _aliasesById['$id'] ?? const [];

  Additive? byId(int id) => _byId[id];

  int? idByAlias(String normalized) => _aliasToId[normalized];

  /// 全部已知名称（用于策略 B 的最长正向匹配）
  Iterable<String> get allKnownNames => _aliasToId.keys;

  NutrientRef? refOf(String code) {
    for (final r in nutrientRefs) {
      if (r.code == code) return r;
    }
    return null;
  }

  NutrientRule? ruleOf(String nutrientCode, String scope) {
    for (final r in nutrientRules) {
      if (r.nutrientCode == nutrientCode && r.scope == scope) return r;
    }
    return null;
  }
}

/// 归一化键工具（与 TextNormalizer.normalizeKey 保持一致的最小实现，避免 domain 依赖 core）
class TextKey {
  static String of(String s) {
    var t = s.replaceAll(RegExp(r'[\s\u3000]'), '');
    t = t.replaceAll(RegExp(r'[（(【\[][^）)】\]]*[）)】\]]'), '');
    t = t.replaceAll(RegExp(r'[0-9]+\.?[0-9]*\s*%'), '');
    t = t.replaceAll(RegExp(r'含苯丙氨酸'), '');
    t = t.replaceAll(RegExp(r'(食用级|食品级|食品|食用)$'), '');
    t = t.replaceAll(RegExp(r'[、,，;；/|＋+&]'), '');
    return t.toLowerCase().trim();
  }
}
