import 'package:fangxinyong/domain/data/knowledge_pack.dart';
import 'package:fangxinyong/domain/data/scoring_constants.dart';
import 'package:fangxinyong/domain/entity/additive.dart';
import 'package:fangxinyong/domain/entity/nutrition_facts.dart';

/// 测试用的内存知识库（覆盖文档 07 的三个演算样例所需的条目）
KnowledgePack buildFakePack() {
  Additive a({
    required int id,
    required String name,
    required int risk,
    String? function,
    String? adi,
  }) =>
      Additive(
        id: id,
        nameZh: name,
        functionClass: function,
        riskLevel: risk,
        defaultPenalty: kPenaltyByRisk[risk]!,
        adiType: adi == null ? 'UNKNOWN' : 'NUMERIC',
        adiValue: adi == null ? null : double.parse(adi),
        riskReasonZh: '$name 的测试说明',
      );

  final additives = [
    a(id: 1, name: '碳酸氢钠', risk: 1, function: '膨松剂'),
    a(id: 2, name: '柠檬酸', risk: 1, function: '酸度调节剂'),
    a(id: 3, name: '焦亚硫酸钠', risk: 4, function: '防腐剂', adi: '0.7'),
    a(id: 4, name: '食用香精', risk: 2, function: '食品用香料'),
    a(id: 5, name: '特丁基对苯二酚', risk: 4, function: '抗氧化剂', adi: '0.7'),
    a(id: 6, name: '谷氨酸钠', risk: 3, function: '增味剂'),
    a(id: 7, name: '三聚磷酸钠', risk: 3, function: '水分保持剂'),
    a(id: 8, name: '焦磷酸钠', risk: 3, function: '水分保持剂'),
    a(id: 9, name: '亚硝酸钠', risk: 4, function: '护色剂', adi: '0.07'),
    a(id: 10, name: 'D-异抗坏血酸钠', risk: 2, function: '抗氧化剂'),
    a(id: 11, name: '红曲红', risk: 2, function: '着色剂'),
    a(id: 12, name: '落葵红', risk: 5, function: '着色剂'),
    a(id: 13, name: '苯甲酸钠', risk: 3, function: '防腐剂'),
    a(id: 14, name: '阿斯巴甜', risk: 4, function: '甜味剂'),
    a(id: 15, name: '安赛蜜', risk: 3, function: '甜味剂'),
    a(id: 16, name: '山梨酸钾', risk: 2, function: '防腐剂'),
    a(id: 17, name: '偶氮甲酰胺', risk: 5, function: '面粉处理剂'),
  ];

  final pack = KnowledgePack(
    additives: additives,
    usageByAdditive: {
      3: [
        const AdditiveUsage(additiveId: 3, categoryCode: '07.0', maxUsage: 0.1, unit: 'g/kg'),
        // 测试 R2：明确超范围使用
        const AdditiveUsage(additiveId: 3, categoryCode: '08.0', isProhibited: true),
      ],
    },
    categories: const [
      FoodCategory(code: '01.0', nameZh: '乳及乳制品', keywords: ['牛奶']),
      FoodCategory(code: '06.0', nameZh: '粮食和粮食制品', keywords: ['面粉', '大米', '小麦粉']),
      FoodCategory(code: '07.0', nameZh: '焙烤食品', keywords: ['饼干']),
      FoodCategory(code: '08.0', nameZh: '肉及肉制品', keywords: ['火腿肠']),
      FoodCategory(code: '14.0', nameZh: '饮料类', keywords: ['饮料', '咖啡']),
    ],
    allergens: const [
      Allergen(code: 'GLUTEN', nameZh: '含麸质的谷物及其制品', aliases: ['小麦粉', '面粉', '小麦']),
      Allergen(code: 'PEANUT', nameZh: '花生及其制品', aliases: ['花生']),
      Allergen(code: 'SOY', nameZh: '大豆及其制品', aliases: ['大豆', '大豆蛋白']),
    ],
    nutrientRefs: const [
      NutrientRef(code: 'ENERGY', nameZh: '能量', unit: 'kJ', nrvValue: 8400),
      NutrientRef(code: 'PROTEIN', nameZh: '蛋白质', unit: 'g', nrvValue: 60),
      NutrientRef(code: 'SODIUM', nameZh: '钠', unit: 'mg', nrvValue: 2000),
      NutrientRef(code: 'SUGAR', nameZh: '糖', unit: 'g', nrvValue: 0),
      NutrientRef(code: 'FAT', nameZh: '脂肪', unit: 'g', nrvValue: 60),
      NutrientRef(code: 'SAT_FAT', nameZh: '饱和脂肪', unit: 'g', nrvValue: 20),
      NutrientRef(code: 'DF', nameZh: '膳食纤维', unit: 'g', nrvValue: 25),
    ],
    nutrientRules: const [
      // SODIUM
      NutrientRule(
          nutrientCode: 'SODIUM', scope: 'SOLID', highValue: 800, midValue: 400,
          lowValue: 120, highPenalty: 12, midPenalty: 6, lowPenalty: 2),
      NutrientRule(
          nutrientCode: 'SODIUM', scope: 'LIQUID', highValue: 300, midValue: 150,
          lowValue: 60, highPenalty: 12, midPenalty: 6, lowPenalty: 2),
      // SUGAR
      NutrientRule(
          nutrientCode: 'SUGAR', scope: 'SOLID', highValue: 22.5, midValue: 11.25,
          lowValue: 5, highPenalty: 15, midPenalty: 8, lowPenalty: 3),
      NutrientRule(
          nutrientCode: 'SUGAR', scope: 'LIQUID', highValue: 11.25, midValue: 5,
          lowValue: 2.5, highPenalty: 15, midPenalty: 8, lowPenalty: 3),
      // SAT_FAT
      NutrientRule(
          nutrientCode: 'SAT_FAT', scope: 'SOLID', highValue: 5, midValue: 3,
          lowValue: 1.5, highPenalty: 10, midPenalty: 5, lowPenalty: 1.5),
      NutrientRule(
          nutrientCode: 'SAT_FAT', scope: 'LIQUID', highValue: 2.5, midValue: 1.5,
          lowValue: 0.75, highPenalty: 10, midPenalty: 5, lowPenalty: 1.5),
      // FAT
      NutrientRule(
          nutrientCode: 'FAT', scope: 'SOLID', highValue: 17.5, midValue: 10,
          lowValue: 0, highPenalty: 6, midPenalty: 3, lowPenalty: 0),
      NutrientRule(
          nutrientCode: 'FAT', scope: 'LIQUID', highValue: 8.75, midValue: 5,
          lowValue: 0, highPenalty: 6, midPenalty: 3, lowPenalty: 0),
      // TRANS_FAT
      NutrientRule(
          nutrientCode: 'TRANS_FAT', scope: 'SOLID', highValue: 0.3, midValue: 0.01,
          lowValue: 0, highPenalty: 12, midPenalty: 8, lowPenalty: 0),
      NutrientRule(
          nutrientCode: 'TRANS_FAT', scope: 'LIQUID', highValue: 0.3, midValue: 0.01,
          lowValue: 0, highPenalty: 12, midPenalty: 8, lowPenalty: 0),
      // ENERGY
      NutrientRule(
          nutrientCode: 'ENERGY', scope: 'SOLID', highValue: 2000, midValue: 1500,
          lowValue: 0, highPenalty: 4, midPenalty: 2, lowPenalty: 0),
      NutrientRule(
          nutrientCode: 'ENERGY', scope: 'LIQUID', highValue: 400, midValue: 300,
          lowValue: 0, highPenalty: 4, midPenalty: 2, lowPenalty: 0),
      // BONUS
      NutrientRule(
          nutrientCode: 'DF', scope: 'SOLID', highValue: 6, midValue: 3,
          lowValue: 0, highPenalty: -3, midPenalty: -1.5, lowPenalty: 0, isBonus: true),
      NutrientRule(
          nutrientCode: 'PROTEIN', scope: 'SOLID', highValue: 12, midValue: 8,
          lowValue: 0, highPenalty: -3, midPenalty: -1.5, lowPenalty: 0, isBonus: true),
      NutrientRule(
          nutrientCode: 'PROTEIN', scope: 'LIQUID', highValue: 6, midValue: 4,
          lowValue: 0, highPenalty: -3, midPenalty: -1.5, lowPenalty: 0, isBonus: true),
    ],
    novaMarkers: const [
      NovaMarker(keyword: '食用香精', weight: 1.0),
      NovaMarker(keyword: '特丁基对苯二酚', weight: 1.0),
      NovaMarker(keyword: '三聚磷酸钠', weight: 1.0),
      NovaMarker(keyword: '亚硝酸钠', weight: 1.0),
      NovaMarker(keyword: '谷氨酸钠', weight: 1.0),
    ],
    populationRules: const [
      PopulationRule(
          populationCode: 'CHILD', targetType: 'ADDITIVE', targetKey: '亚硝酸钠',
          severity: 'AVOID', reasonZh: '儿童建议少食加工肉制品'),
      PopulationRule(
          populationCode: 'PREGNANCY', targetType: 'ADDITIVE', targetKey: '亚硝酸钠',
          severity: 'AVOID', reasonZh: '孕期建议避免亚硝酸盐类制品'),
    ],
    rawMaterials: const [
      RawMaterial(keyword: '小麦粉', category: 'GRAIN', allergenCode: 'GLUTEN'),
      RawMaterial(keyword: '白砂糖', category: 'SUGAR'),
      RawMaterial(keyword: '植物油', category: 'FAT'),
      RawMaterial(keyword: '食用盐', category: 'SALT'),
      RawMaterial(keyword: '水', category: 'WATER'),
      RawMaterial(keyword: '淀粉', category: 'GRAIN'),
      RawMaterial(keyword: '大豆蛋白', category: 'SOY', allergenCode: 'SOY'),
      RawMaterial(keyword: '猪肉', category: 'MEAT'),
      RawMaterial(keyword: '香辛料', category: 'OTHER'),
      RawMaterial(keyword: '生牛乳', category: 'MILK', allergenCode: 'MILK'),
      RawMaterial(keyword: '鸡蛋', category: 'EGG', allergenCode: 'EGG'),
    ],
    version: 'test-1',
  );

  pack.addAlias(3, '焦亚硫酸钠');
  pack.addAlias(5, '特丁基对苯二酚');
  pack.addAlias(5, 'TBHQ');
  pack.addAlias(6, '谷氨酸钠');
  pack.addAlias(6, '味精');
  pack.addAlias(14, '阿斯巴甜');
  pack.addAlias(15, '安赛蜜');
  return pack;
}
