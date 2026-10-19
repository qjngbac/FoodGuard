import 'additive.dart';

/// 配料种类
enum IngredientKind {
  /// 食品添加剂（命中 additive 表）
  additive,

  /// 普通原料（命中 raw_material 表）
  rawMaterial,

  /// 未收录
  unknown,
}

/// 原料类别（用于营养与过敏原判定）
enum MaterialCategory {
  sugar('SUGAR', '糖/甜味物'),
  fat('FAT', '油脂'),
  grain('GRAIN', '谷物'),
  milk('MILK', '乳'),
  egg('EGG', '蛋'),
  nut('NUT', '坚果/籽'),
  soy('SOY', '大豆'),
  seafood('SEAFOOD', '水产'),
  meat('MEAT', '肉'),
  fruit('FRUIT', '果蔬'),
  salt('SALT', '盐/高钠调味'),
  water('WATER', '水'),
  other('OTHER', '其他');

  const MaterialCategory(this.code, this.label);
  final String code;
  final String label;

  static MaterialCategory fromCode(String? code) =>
      values.firstWhere((e) => e.code == code, orElse: () => other);
}

/// 单个配料
class Ingredient {
  Ingredient({
    required this.order,
    required this.rawText,
    required this.normalized,
    this.kind = IngredientKind.unknown,
    this.additive,
    this.materialCategory,
    this.allergenCode,
    this.matchConfidence = 0,
    this.matchMethod = 'M7',
    this.depth = 0,
    this.parentOrder,
    this.percent,
  });

  /// 顶层序号，1-based
  final int order;

  /// 展示用原文
  final String rawText;

  /// 归一化后的匹配键
  final String normalized;

  final IngredientKind kind;
  final Additive? additive;
  final MaterialCategory? materialCategory;
  final String? allergenCode;

  /// 匹配置信度 0–1
  final double matchConfidence;

  /// M1..M7
  final String matchMethod;

  /// 0 = 顶层；≥1 = 复合配料展开层级
  final int depth;
  final int? parentOrder;

  /// 标示的百分比（如 "小麦粉（45%）"）
  final double? percent;

  /// 含量提示，仅供排序与展示（非实测值）
  double get ratioHint {
    if (percent != null) return (percent! / 100).clamp(0.0, 1.0);
    if (depth > 0) return 0.06;
    if (order <= 1) return 0.25;
    if (order == 2) return 0.18;
    if (order == 3) return 0.12;
    if (order <= 8) return 0.07;
    return 0.02;
  }

  bool get isAdditive => kind == IngredientKind.additive;

  String get displayName => rawText.trim().isEmpty ? normalized : rawText.trim();
}
