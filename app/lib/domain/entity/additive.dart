/// 食品添加剂知识实体（来自 knowledge.db 的 additive 表）
class Additive {
  const Additive({
    required this.id,
    required this.nameZh,
    this.nameEn,
    this.insCode,
    this.euCode,
    this.functionClass,
    this.adiValue,
    this.adiType = 'UNKNOWN',
    this.iarcGroup,
    this.iarcNote,
    required this.riskLevel,
    required this.defaultPenalty,
    this.riskReasonZh,
    this.populationFlags = const [],
    this.isIllegal = false,
    this.removedInGb2760 = false,
    this.sourceRef = '',
  });

  final int id;
  final String nameZh;
  final String? nameEn;
  final String? insCode;
  final String? euCode;

  /// 功能类别中文名：防腐剂 / 甜味剂 / 着色剂 …
  final String? functionClass;

  /// ADI 数值（mg/kg bw），adiType != NUMERIC 时为 null
  final double? adiValue;

  /// NUMERIC | NS | NA | GROUP_ADI | UNKNOWN
  final String adiType;

  /// IARC 分组：1 / 2A / 2B / 3
  final String? iarcGroup;
  final String? iarcNote;

  /// 风险等级 1–5（见 docs/02 §4.1）
  final int riskLevel;

  /// 默认扣分权重：1→0、2→1、3→3、4→7、5→25
  final double defaultPenalty;

  final String? riskReasonZh;
  final List<String> populationFlags;
  final bool isIllegal;
  final bool removedInGb2760;
  final String sourceRef;

  /// 一句话的 ADI 展示文本
  String get adiText {
    switch (adiType) {
      case 'NUMERIC':
        return adiValue == null ? '未收录' : '0–${_fmt(adiValue!)} mg/kg 体重/日';
      case 'NS':
        return 'ADI 无需限定（安全性高）';
      case 'NA':
        return 'ADI 未指定（暂无充分数据）';
      case 'GROUP_ADI':
        return '分组 ADI（与其他物质合并计算）';
      default:
        return '未收录 ADI';
    }
  }

  /// 引用式的 IARC 表述（禁止断言"致癌"）
  String? get iarcText {
    if (iarcGroup == null) return null;
    return 'IARC 列为 $iarcGroup 类。该分类反映致癌性证据的充分程度，'
        '不等同于在该摄入量下的实际致癌风险。';
  }

  String get riskLevelText => switch (riskLevel) {
        1 => '极低',
        2 => '低',
        3 => '中',
        4 => '较高',
        _ => '高',
      };

  static String _fmt(double v) {
    final s = v.toStringAsFixed(v < 1 ? 3 : (v < 10 ? 2 : 0));
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }
}

/// 添加剂 × 食品类别 的使用规定
class AdditiveUsage {
  const AdditiveUsage({
    required this.additiveId,
    required this.categoryCode,
    this.maxUsage,
    this.unit,
    this.note,
    this.isProhibited = false,
  });

  final int additiveId;
  final String categoryCode;
  final double? maxUsage;
  final String? unit;
  final String? note;
  final bool isProhibited;
}

/// GB2760 食品分类节点
class FoodCategory {
  const FoodCategory({
    required this.code,
    required this.nameZh,
    this.keywords = const [],
  });

  final String code;
  final String nameZh;
  final List<String> keywords;
}
