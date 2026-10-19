/// 食品形态（决定营养阈值用固体还是液体标准）
enum FoodForm { solid, liquid }

/// 营养成分表（每 100 g / 每 100 mL）
class NutritionFacts {
  const NutritionFacts({
    this.basis = FoodForm.solid,
    this.energyKj,
    this.proteinG,
    this.fatG,
    this.saturatedFatG,
    this.transFatG,
    this.carbohydrateG,
    this.sugarG,
    this.dietaryFiberG,
    this.sodiumMg,
  });

  final FoodForm basis;
  final double? energyKj;
  final double? proteinG;
  final double? fatG;
  final double? saturatedFatG;
  final double? transFatG;
  final double? carbohydrateG;
  final double? sugarG;
  final double? dietaryFiberG;
  final double? sodiumMg;

  /// 无糖（GB28050 声称条件：≤0.5 g/100g(mL)）
  bool get isSugarFree => (sugarG ?? 999) <= 0.5;

  bool get isEmpty =>
      energyKj == null &&
      proteinG == null &&
      fatG == null &&
      saturatedFatG == null &&
      transFatG == null &&
      carbohydrateG == null &&
      sugarG == null &&
      dietaryFiberG == null &&
      sodiumMg == null;

  Map<String, dynamic> toJson() => {
        'basis': basis.name,
        'energyKj': energyKj,
        'proteinG': proteinG,
        'fatG': fatG,
        'saturatedFatG': saturatedFatG,
        'transFatG': transFatG,
        'carbohydrateG': carbohydrateG,
        'sugarG': sugarG,
        'dietaryFiberG': dietaryFiberG,
        'sodiumMg': sodiumMg,
      };

  static NutritionFacts? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return NutritionFacts(
      basis: (json['basis'] == 'liquid') ? FoodForm.liquid : FoodForm.solid,
      energyKj: _d(json['energyKj']),
      proteinG: _d(json['proteinG']),
      fatG: _d(json['fatG']),
      saturatedFatG: _d(json['saturatedFatG']),
      transFatG: _d(json['transFatG']),
      carbohydrateG: _d(json['carbohydrateG']),
      sugarG: _d(json['sugarG']),
      dietaryFiberG: _d(json['dietaryFiberG']),
      sodiumMg: _d(json['sodiumMg']),
    );
  }

  static double? _d(dynamic v) => (v is num) ? v.toDouble() : null;
}

/// 营养素参考值（来自 nutrient_ref 表）
class NutrientRef {
  const NutrientRef({
    required this.code,
    required this.nameZh,
    required this.unit,
    this.nrvValue,
  });

  final String code;
  final String nameZh;
  final String unit;
  final double? nrvValue;

  double? nrvPercent(double? value) {
    if (value == null || nrvValue == null || nrvValue == 0) return null;
    return value / nrvValue! * 100;
  }
}

/// 营养评分规则（来自 nutrient_rule 表）
class NutrientRule {
  const NutrientRule({
    required this.nutrientCode,
    required this.scope,
    this.highValue,
    this.midValue,
    this.lowValue,
    required this.highPenalty,
    required this.midPenalty,
    required this.lowPenalty,
    this.isBonus = false,
  });

  final String nutrientCode;
  final String scope; // SOLID | LIQUID
  final double? highValue;
  final double? midValue;
  final double? lowValue;
  final double highPenalty;
  final double midPenalty;
  final double lowPenalty;
  final bool isBonus;
}
