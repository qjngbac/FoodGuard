import '../../core/util/text_normalizer.dart';
import '../data/knowledge_pack.dart';
import '../entity/additive.dart';
import '../entity/ingredient.dart';
import 'ingredient_parser.dart';

/// 匹配结果（内部中间结构）
class _Match {
  const _Match({this.additive, this.confidence = 0, this.method = 'M7'});
  final Additive? additive;
  final double confidence;
  final String method;
}

/// 添加剂/原料识别（docs/06 §4）
class AdditiveMatcher {
  AdditiveMatcher(this.pack) {
    _nameIndex = {
      for (final a in pack.additives) _key(a.nameZh): a,
    };
    _saltIndex = <String, Additive>{};
    for (final a in pack.additives) {
      final salts = ['酸钠', '酸钾', '酸钙', '酸镁', '酸铵', '酸锌'];
      for (final s in salts) {
        if (a.nameZh.endsWith(s)) {
          _saltIndex[_key('${a.nameZh.substring(0, a.nameZh.length - 2)}酸')] ??= a;
        }
      }
    }
  }

  final KnowledgePack pack;
  late final Map<String, Additive> _nameIndex;
  late final Map<String, Additive> _saltIndex;

  static String _key(String s) => s
      .replaceAll(RegExp(r'[\s\u3000]'), '')
      .replaceAll(RegExp(r'[（(【\[][^）)】\]]*[）)】\]]'), '')
      .toLowerCase()
      .trim();

  /// 逐项匹配
  List<Ingredient> match(List<ParsedItem> items) {
    final out = <Ingredient>[];
    for (final it in items) {
      final key = it.normalized;
      if (key.isEmpty) continue;

      final m = _matchAdditive(key);
      if (m.additive != null) {
        out.add(Ingredient(
          order: it.order,
          rawText: it.rawText,
          normalized: key,
          kind: IngredientKind.additive,
          additive: m.additive,
          matchConfidence: m.confidence,
          matchMethod: m.method,
          depth: it.depth,
          parentOrder: it.parentOrder,
          percent: it.percent,
        ));
        continue;
      }

      final rm = _matchRawMaterial(key);
      if (rm != null) {
        final isFuzzy = _key(rm.keyword) != key && !key.contains(_key(rm.keyword));
        out.add(Ingredient(
          order: it.order,
          rawText: it.rawText,
          normalized: key,
          kind: IngredientKind.rawMaterial,
          materialCategory: MaterialCategory.fromCode(rm.category),
          allergenCode: rm.allergenCode,
          matchConfidence: isFuzzy ? 0.85 : 0.9,
          matchMethod: isFuzzy ? 'MR_FUZZY' : 'MR',
          depth: it.depth,
          parentOrder: it.parentOrder,
          percent: it.percent,
        ));
        continue;
      }

      out.add(Ingredient(
        order: it.order,
        rawText: it.rawText,
        normalized: key,
        kind: IngredientKind.unknown,
        matchConfidence: 0,
        matchMethod: 'M7',
        depth: it.depth,
        parentOrder: it.parentOrder,
        percent: it.percent,
      ));
    }
    return out;
  }

  _Match _matchAdditive(String key) {
    // M1 标准名精确
    final exact = _nameIndex[key];
    if (exact != null) return _Match(additive: exact, confidence: 1.0, method: 'M1');

    // M2 别名（标准名与俗名都注册在 aliasToId 中）
    final aliasId = pack.idByAlias(key);
    if (aliasId != null) {
      final a = pack.byId(aliasId);
      if (a != null) {
        final isOfficial = _key(a.nameZh) == key;
        return _Match(
          additive: a,
          confidence: isOfficial ? 0.98 : 0.95,
          method: isOfficial ? 'M1' : 'M2',
        );
      }
    }

    // M3 盐型归一化
    // 1) 输入为酸形式（如"山梨酸"），库中有其盐（如"山梨酸钾"）
    final salt = _saltIndex[key];
    if (salt != null) return _Match(additive: salt, confidence: 0.90, method: 'M3');

    // 2) 输入为盐型（如"山梨酸钠"），剥离盐后缀检索基酸或同族盐
    const saltSuffixes = ['酸钠', '酸钾', '酸钙', '酸镁', '酸铵', '酸锌', '钠', '钾', '钙', '镁', '铵', '锌'];
    for (final s in saltSuffixes) {
      if (key.endsWith(s) && key.length > s.length + 1) {
        final base = s.startsWith('酸')
            ? '${key.substring(0, key.length - s.length)}酸'
            : key.substring(0, key.length - s.length);
        final baseMatch = _nameIndex[base] ??
            _saltIndex[base] ??
            (pack.idByAlias(base) != null ? pack.byId(pack.idByAlias(base)!) : null);
        if (baseMatch != null) {
          return _Match(additive: baseMatch, confidence: 0.90, method: 'M3');
        }
      }
    }

    // M0 OCR 易错纠偏匹配（例如碳酸氢纳 -> 碳酸氢钠）
    final corrected = TextNormalizer.correctOcrMisspellings(key);
    if (corrected != key) {
      final exactCorr = _nameIndex[corrected];
      if (exactCorr != null) return _Match(additive: exactCorr, confidence: 0.90, method: 'M6');
      final aliasIdCorr = pack.idByAlias(corrected);
      if (aliasIdCorr != null) {
        final a = pack.byId(aliasIdCorr);
        if (a != null) return _Match(additive: a, confidence: 0.88, method: 'M6');
      }
    }

    // M5 包含匹配（高风险词禁用，避免误判）
    if (!_isDangerousKeyword(key)) {
      for (final a in pack.additives) {
        final n = _key(a.nameZh);
        if (n.length < 4) continue;
        if (a.riskLevel >= 4) continue;
        if (key.contains(n) && n.length / key.length >= 0.6) {
          return _Match(additive: a, confidence: 0.75, method: 'M5');
        }
      }
    }

    // M6 模糊匹配（编辑距离 ≤ 1，且长度 ≥ 3）
    if (key.length >= 3 && !_isDangerousKeyword(key)) {
      Additive? best;
      var bestDist = 2;
      for (final a in pack.additives) {
        final n = _key(a.nameZh);
        if ((n.length - key.length).abs() > 1) continue;
        if (a.riskLevel >= 4) continue; // 高风险避免模糊误匹配
        final d = _lev(key, n);
        if (d < bestDist) {
          bestDist = d;
          best = a;
        }
      }
      if (best != null) return _Match(additive: best, confidence: 0.70, method: 'M6');
    }

    return const _Match();
  }

  RawMaterial? _matchRawMaterial(String key) {
    RawMaterial? best;
    for (final rm in pack.rawMaterials) {
      final k = _key(rm.keyword);
      if (k == key) return rm;
      if (key.contains(k) && (best == null || k.length > _key(best.keyword).length)) {
        best = rm;
      }
    }
    if (best != null) return best;

    // 果蔬汁/原浆/果肉通用派生识别：例如 [水果/蔬菜] + (原汁|浓缩汁|清汁|浊汁|果汁|果原浆|原浆|果浆|果肉|果泥|果干|果粉|浓缩液|提取液|提取物|汁|浆|泥|丁|粉)
    final juiceSuffixPattern = RegExp(
      r'(?:原汁|浓缩汁|清汁|浊汁|果汁|果原浆|原浆|果浆|果肉|果泥|果干|果粉|浓缩液|提取液|提取物|汁|浆|泥|丁|粉)$',
    );
    if (juiceSuffixPattern.hasMatch(key)) {
      var stem = key.replaceFirst(juiceSuffixPattern, '');
      stem = stem.replaceFirst(RegExp(r'^(?:浓缩|冷冻|鲜|纯)'), '');
      if (stem.isNotEmpty) {
        for (final rm in pack.rawMaterials) {
          final k = _key(rm.keyword);
          if (k == stem || stem.contains(k) || (stem.length >= 2 && k.contains(stem))) {
            return RawMaterial(
              keyword: key,
              category: rm.category.isNotEmpty ? rm.category : 'FRUIT',
              allergenCode: rm.allergenCode,
            );
          }
        }
      }
    }

    // OCR 易错纠偏后再匹配
    final corrected = TextNormalizer.correctOcrMisspellings(key);
    if (corrected != key) {
      for (final rm in pack.rawMaterials) {
        final k = _key(rm.keyword);
        if (k == corrected || corrected.contains(k)) return rm;
      }
    }

    // Levenshtein 容错匹配（针对微小错字，长度 >= 3 且编辑距离 <= 1）
    if (key.length >= 3) {
      for (final rm in pack.rawMaterials) {
        final k = _key(rm.keyword);
        if (k.length >= 3 && (k.length - key.length).abs() <= 1) {
          if (_lev(key, k) <= 1) {
            return rm;
          }
        }
      }
    }

    return null;
  }

  static bool _isDangerousKeyword(String key) =>
      key.contains('亚硝') || key.contains('硝酸') || key.contains('苯') || key.contains('偶氮');

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
