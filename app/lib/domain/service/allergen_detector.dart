import '../data/knowledge_pack.dart';
import '../entity/ingredient.dart';
import '../entity/score_result.dart';
import '../entity/user_profile.dart';

/// 过敏原检测（docs/07 §7）
class AllergenDetector {
  AllergenDetector(this.pack);

  final KnowledgePack pack;

  /// 单字别名容易误伤的成分词：含这些写法的配料不按对应过敏原处理
  static const Map<String, List<String>> _falseFriends = {
    'CRUSTACEAN': ['虾青素', '磷虾油胶囊'],
    'FISH': ['鱼胶原蛋白', '鱼子酱提取物'],
    'MILK': ['植物', '植脂', '人造', '椰奶'],
    'SOY': ['豌豆', '绿豆', '红豆', '鹰嘴豆'],
  };

  static bool _isFalseFriend(String code, String text) {
    final list = _falseFriends[code];
    if (list == null) return false;
    return list.any(text.contains);
  }

  /// 配料表 + "可能含有"提示语
  List<AllergenHit> detect({
    required List<Ingredient> items,
    required UserProfile profile,
    String? traceText,
  }) {
    final hits = <AllergenHit>[];
    final seen = <String>{};

    void add(AllergenHit hit) {
      if (seen.contains(hit.code)) return;
      seen.add(hit.code);
      hits.add(hit);
    }

    for (final item in items) {
      for (final a in pack.allergens) {
        if (_isFalseFriend(a.code, item.rawText)) continue;
        for (final alias in a.aliases) {
          if (alias.isEmpty) continue;
          if (item.rawText.contains(alias) || item.normalized.contains(alias)) {
            add(AllergenHit(
              code: a.code,
              nameZh: a.nameZh,
              matchedText: '${item.rawText}（含 $alias）',
              matchedWord: item.rawText,
              isSubscribed: profile.allergens.contains(a.code),
            ));
            break;
          }
        }
      }
      // 原料表自带的过敏原编码
      if (item.allergenCode != null && item.allergenCode!.isNotEmpty) {
        if (!_isFalseFriend(item.allergenCode!, item.rawText)) {
          final a = _find(item.allergenCode!);
          if (a != null) {
            add(AllergenHit(
              code: a.code,
              nameZh: a.nameZh,
              matchedText: item.rawText,
              matchedWord: item.rawText,
              isSubscribed: profile.allergens.contains(a.code),
            ));
          }
        }
      }
    }

    // "可能含有 / 此生产线也加工" → 交叉污染提示
    if (traceText != null && traceText.isNotEmpty) {
      for (final a in pack.allergens) {
        if (_isFalseFriend(a.code, traceText)) continue;
        for (final alias in a.aliases) {
          if (alias.isNotEmpty && traceText.contains(alias)) {
            add(AllergenHit(
              code: a.code,
              nameZh: a.nameZh,
              matchedText: '生产线可能交叉污染：$alias',
              matchedWord: alias,
              isTrace: true,
              isSubscribed: profile.allergens.contains(a.code),
            ));
            break;
          }
        }
      }
    }

    hits.sort((x, y) {
      if (x.isSubscribed != y.isSubscribed) return x.isSubscribed ? -1 : 1;
      if (x.isTrace != y.isTrace) return x.isTrace ? 1 : -1;
      return x.code.compareTo(y.code);
    });
    return hits;
  }

  Allergen? _find(String code) {
    for (final a in pack.allergens) {
      if (a.code == code) return a;
    }
    return null;
  }
}
