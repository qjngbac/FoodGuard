import '../data/knowledge_pack.dart';
import '../data/scoring_constants.dart';
import '../entity/ingredient.dart';
import '../entity/score_result.dart';

/// NOVA 加工度分类（docs/07 §5）
class NovaClassifier {
  NovaClassifier(this.pack);

  final KnowledgePack pack;

  static const Set<String> _unprocessed = {
    '水', '牛奶', '牛乳', '生牛乳', '鲜牛奶', '鸡蛋', '蛋液', '牛肉', '猪肉', '鸡肉',
    '羊肉', '鸭肉', '鱼', '鱼肉', '虾', '虾仁', '苹果', '番茄', '橙', '橙汁', '大米',
    '小麦', '玉米', '土豆', '马铃薯', '燕麦',
  };

  static const Set<String> _cooking = {
    '食用盐', '盐', '白砂糖', '绵白糖', '冰糖', '红糖', '植物油', '菜籽油', '花生油',
    '大豆油', '玉米油', '葵花籽油', '橄榄油', '黄油', '猪油', '醋', '淀粉', '蜂蜜',
    '酵母', '香辛料',
  };

  static const Set<String> _groupOneCategories = {
    'WATER', 'MEAT', 'FRUIT', 'SEAFOOD', 'GRAIN', 'MILK', 'EGG', 'NUT', 'SOY', 'SALT',
  };

  NovaResult classify(List<Ingredient> items) {
    if (items.isEmpty) return const NovaResult(group: 3, penalty: 6.0);

    final strong = <String>[];
    final weak = <String>[];
    for (final i in items) {
      for (final m in pack.novaMarkers) {
        if (i.rawText.contains(m.keyword) || i.normalized.contains(m.keyword)) {
          if (m.weight >= 1.0) {
            if (!strong.contains(m.keyword)) strong.add(m.keyword);
          } else {
            if (!weak.contains(m.keyword)) weak.add(m.keyword);
          }
        }
      }
    }

    final allUnprocessed = items.every(_isUnprocessed);
    final usesCookingOnly = items.every((i) => _isUnprocessed(i) || _isCooking(i));
    final hasAdditive = items.any((i) => i.isAdditive);

    int group;
    if (strong.length >= 2 || (strong.isNotEmpty && items.length >= 5) ||
        (strong.isNotEmpty && weak.length >= 2)) {
      group = 4;
    } else if (strong.isNotEmpty) {
      group = 3;
    } else if (allUnprocessed && items.length <= 3) {
      group = 1;
    } else if (usesCookingOnly) {
      group = 2;
    } else if (!hasAdditive && weak.isEmpty && items.length <= 6) {
      group = 2;
    } else {
      group = 3;
    }

    final markers = <String>[...strong, ...weak];
    return NovaResult(
      group: group,
      penalty: kNovaPenalty[group]!,
      markers: markers.take(6).toList(),
    );
  }

  bool _isUnprocessed(Ingredient i) {
    if (i.depth > 0) return false;
    final t = i.rawText.trim();
    return _unprocessed.contains(t) ||
        (i.materialCategory?.code != null && _groupOneCategories.contains(i.materialCategory!.code));
  }

  bool _isCooking(Ingredient i) {
    final t = i.rawText.trim();
    return _cooking.contains(t) ||
        i.materialCategory?.code == 'SUGAR' ||
        i.materialCategory?.code == 'FAT';
  }
}
