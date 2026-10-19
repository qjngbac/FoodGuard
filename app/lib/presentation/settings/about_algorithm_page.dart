import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';

/// 算法与数据源说明（docs/07 + docs/02 的可读版）
class AboutAlgorithmPage extends ConsumerWidget {
  const AboutAlgorithmPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(packProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('算法与数据源说明')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sec('一、总分怎么算'),
          const _Code('安全分 = 100 −（添加剂扣分 + 营养扣分 + 加工度扣分）'),
          const _P('再用 12 条硬规则把分数映射为 A / B / B- / C / D。'
              '硬规则优先于分数：例如只要检出国家明令禁止的物质，无论分数多高都直接判 D。'),
          const _P('等级含义：A 非常健康 · B 安全食用 · B- 孕童少食 · C 含有害物 · D 含禁用/高风险物质'),

          _sec('二、添加剂扣分'),
          const _P('按配料表顺序近似含量（越靠前含量越高）：第 1 位 ×1.4，2–3 位 ×1.3，'
              '4–8 位 ×1.0，9–15 位 ×0.8，更靠后 ×0.6；来自复合配料的再 ×0.9。'),
          const _Table(
            head: ['风险等级', '例子', '单项扣分'],
            rows: [
              ['1 极低', '抗坏血酸、碳酸氢钠、柠檬酸', '0'],
              ['2 低', '改性淀粉、黄原胶、食用香精', '1'],
              ['3 中', '山梨酸钾、苯甲酸钠、安赛蜜', '3'],
              ['4 较高', '亚硝酸钠、合成色素、甜味剂中争议项', '7'],
              ['5 高（禁用）', '苏丹红、偶氮甲酰胺、落葵红', '25'],
            ],
          ),
          const _P('叠加项：添加剂种类越多放大系数越高（≥8 种 ×1.25）；'
              '同类别（甜味剂/色素/防腐剂/抗氧化剂）混用 3 种以上额外扣分；'
              '阿斯巴甜与安赛蜜同用额外扣分（GB 2760-2024 有总量要求）。'),

          _sec('三、营养扣分（每 100 g，液体按 100 mL）'),
          const _Table(
            head: ['项目', '高', '中', '低', '扣分（高/中/低）'],
            rows: [
              ['钠', '≥800 mg', '≥400 mg', '≥120 mg', '12 / 6 / 2'],
              ['糖', '≥22.5 g', '≥11.25 g', '≥5 g', '15 / 8 / 3'],
              ['饱和脂肪', '≥5 g', '≥3 g', '≥1.5 g', '10 / 5 / 1.5'],
              ['脂肪总量', '≥17.5 g', '≥10 g', '—', '6 / 3 / 0'],
              ['反式脂肪', '≥0.3 g', '>0 g', '—', '12 / 8 / 0'],
              ['能量', '≥2000 kJ', '≥1500 kJ', '—', '4 / 2 / 0'],
            ],
          ),
          const _P('正向加成：膳食纤维 ≥6 g 减 3 分；蛋白质 ≥12 g 减 3 分；无糖且无甜味剂再减 2 分（合计最多减 8 分）。'),
          const _P('⚠️ 两处口径调整（与英国 FSA 标准不同，已公开说明）：\n'
              '· 钠的"高"阈值从 600 mg 上调到 800 mg（NRV 的 40%），更贴近中国居民高钠摄入现状；\n'
              '· 若食品未检出甜味剂且未使用添加糖原料，糖的扣分减半（避免牛奶、纯果汁因乳糖/果糖被误判）。'),

          _sec('四、加工度（NOVA）'),
          const _Table(
            head: ['分组', '含义', '扣分'],
            rows: [
              ['NOVA 1', '未加工/最低加工（如纯牛奶、鲜肉）', '0'],
              ['NOVA 2', '烹饪配料（油、糖、盐、醋）', '2'],
              ['NOVA 3', '加工食品（配料少、无超加工标志物）', '6'],
              ['NOVA 4', '超加工（含香精/色素/甜味剂/氢化油/麦芽糊精等）', '12'],
            ],
          ),

          _sec('五、已知缺陷（不隐瞒）'),
          const _P('1. 无法获知添加剂的实际添加量，只用配料表排序近似，属"推断"而非"实测"。\n'
              '2. 营养成分表的"糖"包含天然糖，已用"天然糖折扣"缓解但仍不完美。\n'
              '3. 复合配料中的添加剂实际含量被稀释，仅按 ×0.9 近似。\n'
              '4. 食品类别可能判定不准，会影响合规判定（可在结果页手动改类别）。\n'
              '5. 部分添加剂无 ADI / 无 IARC 评估，按保守值处理。\n'
              '6. NOVA 分类本身有学术争议，权重已压低（最多 12 分）。'),

          _sec('六、数据来源'),
          const _P('· 添加剂与限量：GB 2760《食品安全国家标准 食品添加剂使用标准》\n'
              '· 每日允许摄入量 ADI：JECFA（FAO/WHO 食品添加剂联合专家委员会）公开评估\n'
              '· 致癌性分类：IARC Monographs 公开清单（引用式表述，不作"致癌"断言）\n'
              '· 营养素参考值 NRV：GB 28050《预包装食品营养标签通则》\n'
              '· 加工度分类：NOVA（Monteiro 等提出的公开学术分类）\n'
              '· 商品条码信息（可选、可关闭）：Open Food Facts，遵循 Open Database License (ODbL)'),
          const _P('本 App 与上述机构无隶属或授权关系。'),

          _sec('七、知识库状态'),
          Card(
            color: (pack?.dataQuality.startsWith('SEED') == true) ? kWarnBg : kSurface,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('版本：${pack?.version ?? '—'}'),
                  Text('数据质量：${pack?.dataQuality ?? '—'}'),
                  Text('添加剂：${pack?.additives.length ?? 0} 条 · '
                      '别名：${pack?.allKnownNames.length ?? 0} 条 · '
                      '限量规则：${pack?.usageByAdditive.values.fold<int>(0, (a, b) => a + b.length) ?? 0} 条'),
                  if (pack?.dataQuality.startsWith('SEED') == true) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '⚠️ 当前为 SEED（种子数据）：ADI、限量、IARC 分组尚未与官方原文逐条核对。'
                      '结果仅供参考，请勿据此作出健康决策。',
                      style: TextStyle(fontSize: 12, color: kTextSec),
                    ),
                  ],
                ],
              ),
            ),
          ),

          _sec('八、数据处理边界'),
          const _P('· 条码、配料表、照片默认只存在本机，不上传。\n'
              '· 关闭"联网查商品信息"后，本 App 完全离线运行。\n'
              '· 未收录的配料只在本机计数，仅在设置页手动导出时才会离开设备。'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sec(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kPrimary)),
      );
}

class _P extends StatelessWidget {
  const _P(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
      );
}

class _Code extends StatelessWidget {
  const _Code(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kDivider,
          borderRadius: BorderRadius.circular(kRadiusS),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: kTextPri)),
      );
}

class _Table extends StatelessWidget {
  const _Table({required this.head, required this.rows});
  final List<String> head;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(3)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: head
                  .map((h) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(h,
                          style: const TextStyle(fontSize: 11, color: kTextSec))))
                  .toList(),
            ),
            ...rows.map(
              (r) => TableRow(
                children: r
                    .map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(c, style: const TextStyle(fontSize: 11))))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
