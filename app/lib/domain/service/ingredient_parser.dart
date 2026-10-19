import '../../core/util/text_normalizer.dart';
import '../data/scoring_constants.dart';

/// 解析出的原始配料项（尚未匹配知识库）
class ParsedItem {
  ParsedItem({
    required this.order,
    required this.rawText,
    this.depth = 0,
    this.parentOrder,
    this.percent,
  });

  final int order;
  final String rawText;
  final int depth;
  final int? parentOrder;
  final double? percent;

  String get normalized => TextNormalizer.normalizeKey(rawText);
}

/// 配料表解析器（纯 Dart，不依赖 IO）
/// 见 docs/06
class IngredientParser {
  IngredientParser({this.maxDepth = 3, this.dictionary});

  final int maxDepth;
  final Set<String>? dictionary;

  /// 解析配料表文本
  List<ParsedItem> parse(String rawText) {
    final text = TextNormalizer.fixOcrTypos(rawText);
    final body = TextNormalizer.extractIngredientsBody(text);
    if (body.trim().isEmpty) return const [];

    final items = <ParsedItem>[];
    final top = _splitTopLevelSeparator(body);
    if (top.length > 1) {
      _parseStrategyA(top, items);
    } else {
      // 分隔符缺失（OCR 常见）时，先按括号切段，段内用已知词典或最长正向匹配
      final segments = _splitTopLevelByBracket(body);
      var order = 0;
      for (final seg in segments) {
        final segItems = _expandBrackets(seg, 0);
        for (final it in segItems) {
          final words = (dictionary != null && dictionary!.isNotEmpty && !_isSeparatorPresent(it))
              ? _splitByKnownWords(it, dictionary!)
              : [it];
          for (final w in words) {
            items.add(ParsedItem(
              order: ++order,
              rawText: w,
              depth: 0,
              percent: TextNormalizer.extractPercent(w),
            ));
          }
        }
      }
    }
    return items;
  }

  static bool _isSeparatorPresent(String s) =>
      s.contains('、') || s.contains(',') || s.contains('，') || s.contains(';') || s.contains('；');

  /// 括号感知的顶层切分：只切括号外的分隔符
  List<String> _splitTopLevelSeparator(String text) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '（' || ch == '(' || ch == '【' || ch == '[') {
        depth++;
      } else if (ch == '）' || ch == ')' || ch == '】' || ch == ']') {
        if (depth > 0) depth--;
      } else if (depth == 0 && _isSeparator(ch)) {
        if (buf.toString().trim().isNotEmpty) {
          out.add(buf.toString().trim());
          buf.clear();
        }
        continue;
      }
      buf.write(ch);
    }
    if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
    return out;
  }

  static bool _isSeparator(String ch) => '、,，;；:：/|＋+&'.contains(ch);

  /// 策略 A：按分隔符切分 + 括号展开
  void _parseStrategyA(List<String> top, List<ParsedItem> out) {
    var order = 0;

    void handle(String raw, {int depth = 0, int? forcedOrder}) {
      final text = raw.trim();
      if (text.isEmpty) return;
      final myOrder = forcedOrder ?? ++order;
      final percent = TextNormalizer.extractPercent(text);
      final bracket = _matchBracket(text) ?? _matchUnclosedBracket(text);

      if (bracket == null || depth >= maxDepth) {
        out.add(ParsedItem(
          order: myOrder,
          rawText: text,
          depth: depth,
          parentOrder: forcedOrder,
          percent: percent,
        ));
        return;
      }

      final head = text.substring(0, bracket.start).trim();
      final inner = text.substring(bracket.innerStart, bracket.innerEnd).trim();
      final suffix = _stripLeadPunct(text.substring(bracket.end + 1));
      final isHeader = _isPureContainerHeader(head);
      final isContainer = isHeader || _isContainer(head);

      // 名称内嵌别名/化学式/拉丁学名（山梨(糖)醇、维生素E(dl-α-醋酸生育酚)）：
      // 括号两侧仍是同一个词，绝不可拆碎。
      if (!isContainer &&
          suffix.isNotEmpty &&
          !_hasListSeparator(inner) &&
          !_hasListSeparator(suffix)) {
        out.add(ParsedItem(
          order: myOrder,
          rawText: text,
          depth: depth,
          parentOrder: forcedOrder,
          percent: percent,
        ));
        return;
      }

      if (head.isNotEmpty && !isHeader) {
        out.add(ParsedItem(
          order: myOrder,
          rawText: head,
          depth: depth,
          parentOrder: forcedOrder,
          percent: percent,
        ));
      }

      if (inner.isNotEmpty) {
        for (final sub in _splitTopLevelSeparator(inner)) {
          final s = sub.trim();
          if (s.isEmpty || _isAnnotation(s)) continue;
          handle(s, depth: isContainer ? depth : depth + 1, forcedOrder: isContainer ? null : myOrder);
        }
      }

      if (suffix.isNotEmpty) {
        for (final s in _splitTopLevelSeparator(suffix)) {
          final t = _stripLeadPunct(s);
          if (t.isEmpty) continue;
          handle(t, depth: depth);
        }
      }
    }

    for (final raw in top) {
      handle(raw);
    }
  }

  static final RegExp _leadPunct = RegExp(r'^[\s:：,，、;；。+＋]+');

  static String _stripLeadPunct(String s) => s.replaceAll(_leadPunct, '').trim();

  static bool _hasListSeparator(String s) => RegExp(r'[、,，;；:：/|&]').hasMatch(s);

  /// 策略 B：括号递归展开（无分隔符场景，如 OCR 丢顿号）
  List<String> _expandBrackets(String segment, int depth) {
    if (depth >= maxDepth) return [segment.trim()];
    final bracket = _matchBracket(segment);
    if (bracket == null) return [segment.trim()];

    final head = segment.substring(0, bracket.start).trim();
    final inner = segment.substring(bracket.innerStart, bracket.innerEnd).trim();
    final tail = segment.substring(bracket.end + 1).trim();

    final results = <String>[];
    if (head.isNotEmpty && !_isPureContainerHeader(head)) results.add(head);

    if (inner.isNotEmpty && !_isAnnotation(inner)) {
      if (_isContainer(head)) {
        for (final w in _splitByKnownWords(inner, dictionary ?? const <String>{})) {
          results.addAll(_expandBrackets(w, depth + 1));
        }
      } else {
        for (final s in _splitTopLevelSeparator(inner)) {
          if (_isAnnotation(s)) continue;
          results.addAll(_expandBrackets(s, depth + 1));
        }
      }
    }

    if (tail.isNotEmpty) results.addAll(_expandBrackets(tail, depth));
    return results.where((e) => e.isNotEmpty).toList();
  }

  /// 括号里是"注解"而非独立配料：如"（45%）"、"（含苯丙氨酸）"、"（甜味剂）"、拉丁学名
  bool _isAnnotation(String s) {
    final t = s.trim();
    if (t.isEmpty) return true;
    if (RegExp(r'^\d+(\.\d+)?\s*%$').hasMatch(t)) return true;
    if (RegExp(r'^含.{0,10}$').hasMatch(t)) return true;
    if (RegExp(r'^(?:甜味剂|着色剂|防腐剂|增稠剂|乳化剂|酸度调节剂|抗氧化剂|膨松剂|水分保持剂|稳定剂|抗结剂|消泡剂|被膜剂|营养强化剂|保湿剂|调味剂|食品用香料|食用香料|香精|香料)$').hasMatch(t)) return true;
    // 纯拉丁文学名、英文翻译、CAS号、INCI 代码（如 PRUNUS PERSICA, STEVIOL GLYCOSIDES 等）
    if (RegExp(r'^[a-zA-Z0-9\s\-_\.,:/()&]{3,}$').hasMatch(t)) return true;
    return false;
  }

  /// 用已知词典切分无分隔符文本（最长正向匹配 + 长度分桶）
  List<String> _splitByKnownWords(String text, Set<String> dict) {
    if (dict.isEmpty) {
      // 无词典时退化为按 2–6 字的启发式切分（保守）：直接返回整段
      return text.isEmpty ? const [] : [text];
    }
    final buckets = <int, List<String>>{};
    for (final w in dict) {
      buckets.putIfAbsent(w.length, () => <String>[]).add(w);
    }
    final lens = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    final out = <String>[];
    var i = 0;
    var buf = '';
    while (i < text.length) {
      String? hit;
      for (final len in lens) {
        if (i + len > text.length) continue;
        final cand = text.substring(i, i + len);
        if (buckets[len]!.contains(cand)) {
          hit = cand;
          break;
        }
      }
      if (hit != null) {
        if (buf.isNotEmpty) {
          out.add(buf);
          buf = '';
        }
        out.add(hit);
        i += hit.length;
      } else {
        buf += text[i];
        i++;
      }
    }
    if (buf.isNotEmpty) out.add(buf);
    return out;
  }

  /// 是否为"容器型"引导词（括号内内容提升为顶层）
  bool _isContainer(String parentName) {
    if (parentName.isEmpty) return false;
    for (final p in kContainerPrefixes) {
      if (parentName.startsWith(p)) return true;
    }
    return false;
  }

  /// 是否为纯容器级引导名（仅用于引导括号内添加剂，自身不属于独立配料）
  bool _isPureContainerHeader(String name) {
    final clean = name.replaceAll(RegExp(r'[:：\s]'), '');
    return clean == '食品添加剂' ||
        clean.startsWith('复配食品添加剂') ||
        clean.startsWith('复配') ||
        clean == '食品工业用加工助剂';
  }

  /// 按顶层括号切段（用于策略 B）
  List<String> _splitTopLevelByBracket(String body) {
    final out = <String>[];
    var buf = StringBuffer();
    var depth = 0;
    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (ch == '（' || ch == '(') {
        depth++;
        buf.write(ch);
      } else if (ch == '）' || ch == ')') {
        if (depth > 0) depth--;
        buf.write(ch);
        if (depth == 0 && buf.isNotEmpty) {
          out.add(buf.toString());
          buf = StringBuffer();
        }
      } else {
        buf.write(ch);
      }
    }
    final rest = buf.toString().trim();
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  /// 括号不配对（OCR 丢失右括号）时，把开括号之后的整段当作括号内容展开，
  /// 否则 "食品添加剂（柠檬酸、山梨酸钾" 会整串丢失、添加剂一个都识别不出。
  _BracketMatch? _matchUnclosedBracket(String text) {
    var start = -1;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '（' || ch == '(' || ch == '【' || ch == '[') {
        if (start < 0) start = i;
      } else if (ch == '）' || ch == ')' || ch == '】' || ch == ']') {
        if (start >= 0) return null;
      }
    }
    if (start < 0 || start == text.length - 1) return null;
    return _BracketMatch(start, text.length - 1, start + 1, text.length);
  }

  /// 找到文本中第一组顶层括号的位置
  _BracketMatch? _matchBracket(String text) {
    var depth = 0;
    var start = -1;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '（' || ch == '(' || ch == '【' || ch == '[') {
        if (depth == 0) start = i;
        depth++;
      } else if (ch == '）' || ch == ')' || ch == '】' || ch == ']') {
        if (depth > 0) {
          depth--;
          if (depth == 0 && start >= 0) {
            return _BracketMatch(start, i, start + 1, i);
          }
        }
      }
    }
    // 括号不配对：截断到最后位置之前，避免崩溃
    return null;
  }
}

class _BracketMatch {
  const _BracketMatch(this.start, this.end, this.innerStart, this.innerEnd);
  final int start;
  final int end;
  final int innerStart;
  final int innerEnd;
}
