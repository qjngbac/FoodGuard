import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/util/text_normalizer.dart';

/// 拍照 / 相册 → 端上中文 OCR
/// 降级：设备不支持（无 GMS 或未下载中文模型）时返回 null，UI 引导手动输入。
class OcrService {
  OcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  TextRecognizer? _recognizer;

  Future<XFile?> pickFromCamera() =>
      _picker.pickImage(source: ImageSource.camera, imageQuality: 92, maxWidth: 1600);

  Future<XFile?> pickFromGallery() =>
      _picker.pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: 1600);

  /// 识别图片文字（全流程自动繁体转简体）；失败返回 null
  Future<String?> recognize(String path) async {
    try {
      final inputImage = InputImage.fromFilePath(path);
      _recognizer?.close();
      _recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final result = await _recognizer!.processImage(inputImage);
      // 第一道防线：将 ML Kit OCR 识别出的文字（包括生僻、曲面反光识别出的繁体字）全部净化转换为简体
      final simplified = TextNormalizer.toSimplified(result.text).trim();
      return simplified.isEmpty ? null : simplified;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}

/// 从整段 OCR 文本中切出"配料表"段落并深度清洗多余前缀/尾缀（确保全简体）
String? extractIngredients(String raw) {
  final simplified = TextNormalizer.toSimplified(raw);
  final t = simplified.replaceAll(RegExp(r'\s+'), ' ');
  final start = RegExp(r'(?:配料表?|配料清单|原料与辅料|原辅料|主要成分|成分表?|原料)').firstMatch(t);
  final body = start != null ? t.substring(start.start) : t;
  final cleaned = TextNormalizer.cleanIngredientsText(body);
  return cleaned.isEmpty ? null : cleaned;
}

/// 从整段 OCR 文本中切出"可能含有"（交叉污染）提示（确保全简体）
String? extractTrace(String raw) {
  final simplified = TextNormalizer.toSimplified(raw);
  final m = RegExp(r'(可能含有|此生产线|同一生产线|本生产线)[^\n。；;]{0,80}').firstMatch(simplified);
  return m?.group(0);
}

class _NutrientDef {
  const _NutrientDef({
    required this.key,
    required this.aliases,
    this.isEnergy = false,
    this.isSodium = false,
    this.blockedLeft = const [],
  });

  final String key;
  final List<String> aliases;
  final bool isEnergy;
  final bool isSodium;

  /// 关键词左侧若这些片段紧邻，说明是另一个词（苯甲酸钠 / 麦芽糖浆 / 胶原蛋白）
  final List<String> blockedLeft;
}

final List<_NutrientDef> _nutrientDefs = [
  const _NutrientDef(key: 'energyKj', aliases: ['能量', '热量'], isEnergy: true),
  const _NutrientDef(
    key: 'proteinG',
    aliases: ['蛋白质', '蛋白'],
    blockedLeft: ['胶原', '水解', '乳清', '大豆', '豌豆', '卵', '谷', '酪', '清', '分离'],
  ),
  const _NutrientDef(
    key: 'fatG',
    aliases: ['总脂肪', '脂肪'],
    blockedLeft: ['饱和', '反式', '不饱和', '单', '多', '胆固'],
  ),
  const _NutrientDef(key: 'saturatedFatG', aliases: ['饱和脂肪酸', '饱和脂肪']),
  const _NutrientDef(key: 'transFatG', aliases: ['反式脂肪酸', '反式脂肪']),
  const _NutrientDef(key: 'carbohydrateG', aliases: ['总碳水化合物', '碳水化合物', '碳水']),
  const _NutrientDef(
    key: 'sugarG',
    aliases: ['含糖量', '其中糖', '糖'],
    blockedLeft: ['砂', '冰', '红', '黑', '麦芽', '果葡', '葡', '乳', '海藻', '枫', '玉米', '饴', '浆', '醇', '低', '代', '蔗'],
  ),
  const _NutrientDef(key: 'dietaryFiberG', aliases: ['膳食纤维', '纤维'], blockedLeft: ['羧甲基', '聚']),
  const _NutrientDef(
    key: 'sodiumMg',
    aliases: ['钠盐', '钠'],
    isSodium: true,
    blockedLeft: [
      '酸', '化', '氢', '氯', '氟', '碳', '磷', '铝', '硫', '枸', '山梨', '苯甲', '脱氢乙',
      '亚硝', '焦', '柠檬', '苹果', '抗坏血', '羧甲基纤维素', '蛋白', '谷氨酸', '呈味',
    ],
  ),
];

/// 命中位置左侧是否紧邻其它词根（避免从"苯甲酸钠""麦芽糖浆""胶原蛋白"里抠出数值）
bool _leftBlocked(String text, int at, List<String> blocks) {
  for (final b in blocks) {
    final start = at - b.length;
    if (start < 0) continue;
    if (text.substring(start, at) == b) return true;
  }
  return false;
}

/// 结构化提取营养成分表数字（能量/蛋白/脂肪/饱和脂肪/反式脂肪/碳水/糖/纤维/钠）
/// 支持：繁体转简体、单行对齐、双列/竖排多列对齐、NRV% 严格排除、kcal/kJ 自动换算、g/mg 自动换算
Map<String, double>? extractNutrition(String raw) {
  if (raw.trim().isEmpty) return null;
  final simplified = TextNormalizer.toSimplified(raw);
  final normalized = TextNormalizer.toHalfWidth(simplified);
  final out = <String, double>{};

  // 若包含营养成分表表头，优先截取营养成分表主体区域，防止配料表文字干扰
  var targetText = normalized;
  final tableIndex = targetText.indexOf(RegExp(r'(?:营养成分表|营养成分|项目\s*(?:/|每)|NRV%?)', caseSensitive: false));
  if (tableIndex != -1) {
    targetText = targetText.substring(tableIndex);
    final end = targetText.indexOf(
        RegExp(r'(?:配料|保质期|贮存|生产许可|执行标准|生产商|产地|食用方法|注意事项)', caseSensitive: false));
    if (end > 0) targetText = targetText.substring(0, end);
  }

  // 1. 策略 A：单行扫描提取（排除 NRV% 与每 100g 干扰）
  final lines = targetText.split(RegExp(r'[\r\n]+'));
  for (final line in lines) {
    if (RegExp(r'配料|添加量|致敏').hasMatch(line)) continue;
    var cleanedLine = line.replaceAll(RegExp(r'每\s*\d+\s*(?:克|g|毫升|ml|份)', caseSensitive: false), '');
    cleanedLine = cleanedLine.replaceAll(RegExp(r'\d+(?:\.\d+)?\s*(?:%|％|百分之)'), '');

    for (final def in _nutrientDefs) {
      if (out.containsKey(def.key)) continue;

      int matchedIndex = -1;
      String? matchedAlias;
      for (final a in def.aliases) {
        var startFrom = 0;
        while (true) {
          final p = cleanedLine.indexOf(a, startFrom);
          if (p == -1) break;
          if (_leftBlocked(cleanedLine, p, def.blockedLeft)) {
            startFrom = p + 1;
            continue;
          }
          matchedIndex = p;
          matchedAlias = a;
          break;
        }
        if (matchedAlias != null) break;
      }
      if (matchedAlias == null || matchedIndex == -1) continue;

      // 截取关键词之后的数字与单位
      final after = cleanedLine.substring(matchedIndex + matchedAlias.length);
      final m = RegExp(
        r'(?:<|<=|\s*)(\d+(?:\.\d+)?)\s*(kJ|千焦|kcal|千卡|大卡|g|克|mg|毫克)?',
        caseSensitive: false,
      ).firstMatch(after);

      if (m != null) {
        var val = double.tryParse(m.group(1)!);
        if (val != null) {
          final unit = (m.group(2) ?? '').toLowerCase();
          if (def.isEnergy && (unit.contains('kcal') || unit.contains('千卡') || unit.contains('大卡'))) {
            val *= 4.184;
          } else if (def.isSodium && (unit == 'g' || unit == '克')) {
            val *= 1000.0;
          }
          out[def.key] = double.parse(val.toStringAsFixed(1));
        }
      }
    }
  }

  // 2. 策略 B：双列/多列网格对齐（当 MLKit 先后分块识别指标名与数值列时）
  if (out.length < 3) {
    var valText = targetText.replaceAll(RegExp(r'每\s*\d+\s*(?:克|g|毫升|ml|份)', caseSensitive: false), '');
    final nrvIndex = valText.indexOf(RegExp(r'(?:NRV|营养素参考值|参考值)', caseSensitive: false));
    if (nrvIndex > 0) {
      valText = valText.substring(0, nrvIndex);
    }

    final posTargets = <MapEntry<int, _NutrientDef>>[];
    for (final def in _nutrientDefs) {
      for (final a in def.aliases) {
        final p = valText.indexOf(a);
        if (p != -1) {
          posTargets.add(MapEntry(p, def));
          break;
        }
      }
    }
    posTargets.sort((a, b) => a.key.compareTo(b.key));

    final valMatches = <MapEntry<int, MapEntry<double, String>>>[];
    final numIter = RegExp(
      r'(?:<|<=|\s*)(\d+(?:\.\d+)?)\s*(kJ|千焦|kcal|千卡|大卡|g|克|mg|毫克)(?!\s*%)',
      caseSensitive: false,
    ).allMatches(valText);

    for (final m in numIter) {
      final v = double.tryParse(m.group(1)!);
      if (v != null) {
        valMatches.add(MapEntry(m.start, MapEntry(v, (m.group(2) ?? '').toLowerCase())));
      }
    }

    if (posTargets.isNotEmpty && valMatches.isNotEmpty) {
      final lastTargetPos = posTargets.map((e) => e.key).reduce((a, b) => a > b ? a : b);
      final colValues = valMatches.where((e) => e.key > lastTargetPos).toList();

      if (colValues.length == posTargets.length) {
        for (var i = 0; i < posTargets.length; i++) {
          final def = posTargets[i].value;
          var numVal = colValues[i].value.key;
          final unit = colValues[i].value.value;
          if (def.isEnergy && (unit.contains('kcal') || unit.contains('千卡') || unit.contains('大卡'))) {
            numVal *= 4.184;
          } else if (def.isSodium && (unit == 'g' || unit == '克')) {
            numVal *= 1000.0;
          }
          out.putIfAbsent(def.key, () => double.parse(numVal.toStringAsFixed(1)));
        }
      }
    }
  }

  return out.isEmpty ? null : out;
}
