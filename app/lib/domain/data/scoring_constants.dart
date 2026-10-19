/// 评分算法全部常量（集中定义，便于调参与单测）
/// 依据：docs/07-安全评级算法规格.md
library;

const String kAlgorithmVersion = '1.0.0';

/// 各风险等级的默认扣分（riskLevel -> penalty）
const Map<int, double> kPenaltyByRisk = {1: 0.0, 2: 1.0, 3: 3.0, 4: 7.0, 5: 25.0};

/// 位置因子阈值（顶层 order -> factor）
const Map<int, double> kPositionFactorByOrder = {1: 1.40, 3: 1.30, 8: 1.00, 15: 0.80};

/// 超过 15 位的位置因子
const double kPositionFactorTail = 0.60;

/// 复合配料展开项的位置折扣
const double kCompositeDiscount = 0.9;

/// 添加剂种数 -> 数量放大系数
const Map<int, double> kCountFactorByCount = {2: 1.00, 4: 1.05, 7: 1.15};

/// 超过 7 种的放大系数
const double kCountFactorTail = 1.25;

/// 同类叠加惩罚：功能组 -> (k=2, k=3, k>=4)
const Map<String, List<double>> kStackingByFunction = {
  'SWEETENER': [1.5, 4.0, 6.0],
  'COLORANT': [1.5, 4.0, 6.0],
  'PRESERVATIVE': [1.5, 4.0, 6.0],
  'ANTIOXIDANT': [1.0, 3.0, 5.0],
};

/// 其余功能组的叠加惩罚
const List<double> kStackingOther = [0.0, 1.0, 2.0];

/// 阿斯巴甜 + 安赛蜜 等混合甜味剂的额外扣分
const double kMixedSweetenerPenalty = 2.0;

/// 中文功能类别 -> 类别码
const Map<String, String> kFunctionClassCode = {
  '防腐剂': 'PRESERVATIVE',
  '抗氧化剂': 'ANTIOXIDANT',
  '着色剂': 'COLORANT',
  '甜味剂': 'SWEETENER',
  '增稠剂': 'THICKENER',
  '乳化剂': 'EMULSIFIER',
  '酸度调节剂': 'ACIDITY_REGULATOR',
  '膨松剂': 'LEAVENING',
  '增味剂': 'FLAVOR_ENHANCER',
  '水分保持剂': 'HUMECTANT',
  '抗结剂': 'ANTICAKING',
  '稳定剂和凝固剂': 'STABILIZER',
  '被膜剂': 'COATING',
  '面粉处理剂': 'FLOUR_TREATMENT',
  '护色剂': 'COLOR_RETENTION',
  '食品用香料': 'FLAVORING',
  '营养强化剂': 'NUTRITION',
  '其他': 'OTHER',
  '非法添加物': 'ILLEGAL',
  '消泡剂': 'ANTIFOAMING',
  '漂白剂': 'BLEACHING',
  '胶基糖果中基础剂物质': 'GUM_BASE',
  '酶制剂': 'ENZYME',
};

/// AP 上限
const double kApMax = 70.0;

/// 配料表只标注功能类别名（未给出具体品种）时，每一种的保守扣分
const double kClassOnlyPenalty = 2.0;

/// GB 2760 功能类别名：出现在配料表里说明"确有添加剂但品种不明"，不能当作普通未知词放过
const List<String> kFunctionClassOnlyNames = [
  '防腐剂', '抗氧化剂', '着色剂', '甜味剂', '增稠剂', '乳化剂', '酸度调节剂', '膨松剂',
  '增味剂', '水分保持剂', '抗结剂', '稳定剂', '凝固剂', '被膜剂', '面粉处理剂', '护色剂',
  '漂白剂', '消泡剂', '胶基', '酶制剂', '营养强化剂', '食品用香料', '食用香料', '香精', '香料',
];

/// NP 区间
const double kNpMin = -8.0;
const double kNpMax = 30.0;

/// PP 上限
const double kPpMax = 15.0;

/// NOVA 扣分
const Map<int, double> kNovaPenalty = {1: 0.0, 2: 2.0, 3: 6.0, 4: 12.0};

/// 配料项数 ≥ 20 的附加扣分
const int kLongIngredientListThreshold = 20;
const double kLongIngredientListPenalty = 3.0;

/// 反式脂肪"标 0 但含氢化油"的扣分
const double kTransFatZeroButHydrogenatedPenalty = 8.0;

/// 含氢化油的关键原料词
const List<String> kHydrogenatedOilKeywords = [
  '氢化植物油',
  '部分氢化植物油',
  '氢化油',
  '人造奶油',
  '起酥油',
  '代可可脂',
  '植脂末',
  '奶精',
];

/// 添加糖原料词（用于"天然糖折扣"判定）
const List<String> kAddedSugarKeywords = [
  '白砂糖',
  '绵白糖',
  '冰糖',
  '红糖',
  '果葡糖浆',
  '麦芽糖浆',
  '葡萄糖浆',
  '蜂蜜',
  '麦芽糖',
  '葡萄糖',
  '海藻糖',
  '糖蜜',
];

/// 天然糖折扣系数（无甜味剂且无添加糖原料时，糖的扣分乘以此系数）
const double kNaturalSugarDiscount = 0.5;

/// 触发 B- 的"咖啡因/合成色素"关键词
const List<String> kBMinusTriggerKeywords = [
  '咖啡因',
  '咖啡碱',
  '柠檬黄',
  '日落黄',
  '胭脂红',
  '诱惑红',
  '亮蓝',
  '赤藓红',
  '靛蓝',
  '二氧化钛',
];

/// 硬规则阈值
const double kApThresholdForC = 25.0;
const int kRisk4InTopN = 5;
const int kRisk4CountForC = 2;
const int kScoreForD = 40;
const int kScoreForC = 60;
const int kScoreForBMinus = 75;
const int kScoreForA = 90;
const double kApForA = 3.0;
const int kNovaForA = 2;

/// 复合配料中的"容器型"引导词（括号内内容提升为顶层）
const List<String> kContainerPrefixes = [
  '食品添加剂',
  '复配',
  '食用香精',
  '食用香料',
  '香精',
  '香料',
];
