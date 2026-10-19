import '../data/knowledge_pack.dart';
import '../entity/additive.dart';
import '../entity/ingredient.dart';
import '../entity/score_result.dart';

/// GB2760 合规判定（docs/07 §9）
/// 只判定"该添加剂是否允许用于该食品类别"，**不判定实际添加量是否超标**。
class ComplianceJudge {
  ComplianceJudge(this.pack);

  final KnowledgePack pack;

  ComplianceResult judge(List<Ingredient> items, String? categoryCode) {
    final out = <ComplianceItem>[];
    final additives = items.where((i) => i.isAdditive);

    for (final i in additives) {
      final a = i.additive!;
      if (categoryCode == null) {
        out.add(ComplianceItem(
          additiveId: a.id,
          additiveName: a.nameZh,
          status: UsageStatus.unknown,
        ));
        continue;
      }
      final list = pack.usageByAdditive[a.id] ?? const <AdditiveUsage>[];
      if (list.isEmpty) {
        out.add(ComplianceItem(
          additiveId: a.id,
          additiveName: a.nameZh,
          status: UsageStatus.notCovered,
        ));
        continue;
      }
      final hit = _findUsage(list, categoryCode);
      if (hit == null) {
        out.add(ComplianceItem(
          additiveId: a.id,
          additiveName: a.nameZh,
          status: UsageStatus.notListed,
        ));
      } else if (hit.isProhibited) {
        out.add(ComplianceItem(
          additiveId: a.id,
          additiveName: a.nameZh,
          status: UsageStatus.prohibited,
          note: hit.note,
        ));
      } else {
        out.add(ComplianceItem(
          additiveId: a.id,
          additiveName: a.nameZh,
          status: UsageStatus.allowed,
          maxUsage: hit.maxUsage,
          unit: hit.unit,
          note: hit.note,
        ));
      }
    }

    final level = out.any((e) => e.status == UsageStatus.prohibited)
        ? 'suspected'
        : (categoryCode == null ? 'unknown' : 'ok');

    return ComplianceResult(
      level: level,
      items: out,
      categoryCode: categoryCode,
      categoryName: _categoryName(categoryCode),
    );
  }

  AdditiveUsage? _findUsage(List<AdditiveUsage> list, String categoryCode) {
    // 1) 精确匹配优先（自身明确记录优先，避免父类禁止盖掉子类明确允许）
    for (final u in list) {
      if (u.categoryCode == categoryCode) return u;
    }

    // 2) 父类别匹配（按最长前缀优先，如 07.02 优先于 07.0，07.0 优先于 ALL）
    // 相同前缀长度下禁止记录优先
    AdditiveUsage? bestParent;
    var bestMatchLen = -1;
    for (final u in list) {
      if (_isExactOrAncestor(categoryCode, u.categoryCode)) {
        final len = u.categoryCode == 'ALL' ? 0 : u.categoryCode.length;
        if (len > bestMatchLen || (len == bestMatchLen && u.isProhibited)) {
          bestMatchLen = len;
          bestParent = u;
        }
      }
    }
    return bestParent;
  }

  static bool _isExactOrAncestor(String childCode, String ancestorCode) {
    var c = childCode.trim();
    var a = ancestorCode.trim();
    if (c.endsWith('.')) c = '${c}0';
    if (a.endsWith('.')) a = '${a}0';
    if (c == a) return true;
    if (a == 'ALL') return true;
    if (a.endsWith('.0')) {
      final majorPrefix = a.substring(0, a.length - 1);
      return c.startsWith(majorPrefix);
    } else {
      return c.startsWith('$a.');
    }
  }

  String? _categoryName(String? code) {
    if (code == null) return null;
    for (final c in pack.categories) {
      if (c.code == code) return c.nameZh;
    }
    for (final c in pack.categories) {
      if (_isExactOrAncestor(code, c.code)) return c.nameZh;
    }
    return null;
  }

  /// 展示话术（合规红线：措辞必须照抄，不得改写）
  static String statusText(ComplianceItem item, String? categoryName) {
    final name = categoryName ?? '该食品类别';
    return switch (item.status) {
      UsageStatus.allowed =>
        'GB 2760 允许用于「$name」${item.maxUsage != null ? '，最大使用量 ${_fmt(item.maxUsage!)}${item.unit ?? ''}' : '，按生产需要适量使用'}。',
      UsageStatus.prohibited =>
        'GB 2760 规定该物质不得用于「$name」。如属实，属于超范围使用，建议停止食用并向 12315 反映。',
      UsageStatus.notListed =>
        'GB 2760 的该物质使用规定里没有「$name」这一类。可能是食品类别判定不准，也可能属于超范围使用，建议核对食品类别。',
      UsageStatus.notCovered =>
        '本地知识库尚未收录「${item.additiveName}」的使用规定（当前仅覆盖部分物质×食品大类），'
        '因此无法判断它在本产品中是否合规；此项不计入违规，也不代表允许使用。',
      UsageStatus.unknown => '未获取到食品类别，无法进行合规性判定。',
    };
  }

  static String _fmt(double v) =>
      v.toStringAsFixed(v < 1 ? 3 : 2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
