import '../data/knowledge_pack.dart';
import '../entity/additive.dart';

/// 商品名 / 品类关键词 → GB2760 食品类别码（docs/07 §9.1）
class CategoryMapper {
  CategoryMapper(this.pack);

  final KnowledgePack pack;

  /// 按优先级推断：用户指定 > 商品名关键词 > 配料反推
  FoodCategory? map({
    String? userPicked,
    String? productName,
    List<String> ingredients = const [],
  }) {
    if (userPicked != null) {
      for (final c in pack.categories) {
        if (c.code == userPicked) return c;
      }
    }

    if (productName != null && productName.isNotEmpty) {
      final byKeyword = _matchKeyword(productName);
      if (byKeyword != null) return byKeyword;
    }

    // 配料反推：第一项为主料
    if (ingredients.isNotEmpty) {
      final first = ingredients.first;
      final hit = _byIngredient(first);
      if (hit != null) return hit;
    }
    return null;
  }

  FoodCategory? _matchKeyword(String name) {
    // 1. 优先匹配 pack.categories 中配置的关键词
    final candidates = <FoodCategory>[];
    for (final c in pack.categories) {
      for (final k in c.keywords) {
        if (k.isNotEmpty && name.contains(k)) {
          candidates.add(c);
          break;
        }
      }
    }
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => _score(b, name).compareTo(_score(a, name)));
      return candidates.first;
    }

    // 2. 常见国货品类内置映射（针对咖啡、茶、果汁、苏打水、酸奶、糖果等超高频品名）
    var bestMatchCode = '';
    var bestLen = 0;
    for (final entry in _commonKeywords.entries) {
      if (name.contains(entry.key) && entry.key.length > bestLen) {
        bestLen = entry.key.length;
        bestMatchCode = entry.value;
      }
    }
    if (bestMatchCode.isNotEmpty) {
      for (final c in pack.categories) {
        if (c.code == bestMatchCode) return c;
      }
    }

    return null;
  }

  int _score(FoodCategory c, String name) {
    var best = 0;
    for (final k in c.keywords) {
      if (k.isNotEmpty && name.contains(k)) best = k.length > best ? k.length : best;
    }
    return best;
  }

  FoodCategory? _byIngredient(String first) {
    // 1. 精确主料匹配
    final code = _ingredientCodeMap[first];
    if (code != null) {
      for (final c in pack.categories) {
        if (c.code == code) return c;
      }
    }

    // 2. 模糊主料归类
    for (final entry in _ingredientFuzzyMap.entries) {
      if (first.contains(entry.key)) {
        for (final c in pack.categories) {
          if (c.code == entry.value) return c;
        }
      }
    }

    return null;
  }

  static const _commonKeywords = <String, String>{
    // 14.0 饮料类（涵盖咖啡、茶饮、水、果汁、植物蛋白、碳酸）
    '咖啡': '14.0', '拿铁': '14.0', '摩卡': '14.0', '美式': '14.0', '卡布奇诺': '14.0',
    '速溶': '14.0', '饮用水': '14.0', '纯净水': '14.0', '矿泉水': '14.0', '天然水': '14.0',
    '苏打水': '14.0', '汽水': '14.0', '可乐': '14.0', '雪碧': '14.0', '芬达': '14.0',
    '果汁': '14.0', '橙汁': '14.0', '苹果汁': '14.0', '椰汁': '14.0', '椰子水': '14.0',
    '茶': '14.0', '乌龙': '14.0', '绿茶': '14.0', '红茶': '14.0', '奶茶': '14.0',
    '花茶': '14.0', '普洱': '14.0', '铁观音': '14.0', '豆奶': '14.0', '豆浆': '14.0',
    '电解质': '14.0', '功能饮料': '14.0', '能量饮料': '14.0', '水': '14.0',
    // 01.0 乳及乳制品
    '牛奶': '01.0', '鲜奶': '01.0', '纯牛奶': '01.0', '酸奶': '01.0', '发酵乳': '01.0',
    '奶粉': '01.0', '乳粉': '01.0', '黄油': '01.0', '奶酪': '01.0', '干酪': '01.0',
    '炼乳': '01.0', '稀奶油': '01.0',
    // 07.0 焙烤食品
    '面包': '07.0', '蛋糕': '07.0', '饼干': '07.0', '曲奇': '07.0', '威化': '07.0',
    '蛋黄派': '07.0', '吐司': '07.0', '糕点': '07.0', '月饼': '07.0', '酥': '07.0',
    // 06.0 粮食和粮食制品
    '方便面': '06.0', '挂面': '06.0', '拉面': '06.0', '米粉': '06.0', '螺蛳粉': '06.0',
    '粉丝': '06.0', '麦片': '06.0', '燕麦片': '06.0', '大米': '06.0', '面条': '06.0',
    // 05.0 可可制品巧克力和糖果
    '巧克力': '05.0', '糖果': '05.0', '软糖': '05.0', '硬糖': '05.0', '棒棒糖': '05.0',
    '薄荷糖': '05.0', '润喉糖': '05.0', '果冻': '05.0', '可可': '05.0',
    // 08.0 肉及肉制品
    '火腿': '08.0', '火腿肠': '08.0', '香肠': '08.0', '培根': '08.0', '牛肉干': '08.0',
    '肉脯': '08.0', '鸡翅': '08.0', '鸭脖': '08.0', '肉丸': '08.0', '午餐肉': '08.0',
    // 16.0 膨化食品及其他
    '薯片': '16.0', '虾条': '16.0', '米饼': '16.0', '爆米花': '16.0', '锅巴': '16.0',
    '辣条': '16.0', '面筋': '16.0', '魔芋爽': '16.0',
    // 03.0 冷冻饮品
    '冰淇淋': '03.0', '雪糕': '03.0', '冰棍': '03.0', '冰棒': '03.0',
    // 12.0 调味品
    '酱油': '12.0', '生抽': '12.0', '老抽': '12.0', '醋': '12.0', '陈醋': '12.0',
    '香醋': '12.0', '料酒': '12.0', '蚝油': '12.0', '番茄酱': '12.0', '沙拉酱': '12.0',
    '鸡精': '12.0', '味精': '12.0', '辣椒酱': '12.0', '豆瓣酱': '12.0',
    // 02.0 脂肪油
    '食用油': '02.0', '花生油': '02.0', '大豆油': '02.0', '菜籽油': '02.0', '玉米油': '02.0',
    // 15.0 酒类
    '啤酒': '15.0', '白酒': '15.0', '红酒': '15.0', '黄酒': '15.0',
  };

  static const _ingredientCodeMap = <String, String>{
    '小麦粉': '06.0',
    '面粉': '06.0',
    '生牛乳': '01.0',
    '鲜牛奶': '01.0',
    '纯牛奶': '01.0',
    '牛奶': '01.0',
    '牛乳': '01.0',
    '全脂乳粉': '01.0',
    '脱脂乳粉': '01.0',
    '速溶咖啡': '14.0',
    '咖啡粉': '14.0',
    '咖啡豆': '14.0',
    '咖啡提取物': '14.0',
    '咖啡豆提取物': '14.0',
    '水': '14.0',
    '饮用水': '14.0',
    '纯净水': '14.0',
    '天然矿泉水': '14.0',
    '绿茶': '14.0',
    '红茶': '14.0',
    '乌龙茶': '14.0',
    '茶叶': '14.0',
    '猪肉': '08.0',
    '牛肉': '08.0',
    '鸡肉': '08.0',
    '鸭肉': '08.0',
    '大豆': '04.0',
    '黄豆': '04.0',
    '大米': '06.0',
    '大麦': '06.0',
    '燕麦': '06.0',
    '白砂糖': '11.0',
    '食用葡萄糖': '11.0',
    '果葡糖浆': '11.0',
    '可可液块': '05.0',
    '可可脂': '05.0',
  };

  static const _ingredientFuzzyMap = <String, String>{
    '咖啡': '14.0',
    '茶': '14.0',
    '水': '14.0',
    '乳': '01.0',
    '奶': '01.0',
    '肉': '08.0',
    '面粉': '06.0',
    '麦粉': '06.0',
    '可可': '05.0',
    '巧克力': '05.0',
  };
}
