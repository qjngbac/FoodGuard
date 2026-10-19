import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../domain/entity/user_profile.dart';
import 'about_algorithm_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const List<AllergenOption> allergenOptions = [
    AllergenOption(code: 'GLUTEN', nameZh: '含麸质谷物'),
    AllergenOption(code: 'CRUSTACEAN', nameZh: '甲壳类'),
    AllergenOption(code: 'EGG', nameZh: '蛋类'),
    AllergenOption(code: 'FISH', nameZh: '鱼类'),
    AllergenOption(code: 'PEANUT', nameZh: '花生'),
    AllergenOption(code: 'SOY', nameZh: '大豆'),
    AllergenOption(code: 'MILK', nameZh: '乳类'),
    AllergenOption(code: 'NUT', nameZh: '坚果'),
    AllergenOption(code: 'SESAME', nameZh: '芝麻'),
    AllergenOption(code: 'SULFITE', nameZh: '亚硫酸盐'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final packAsync = ref.watch(packProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _title('为你定制'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('关注人群'),
                  subtitle: Text(profile.population.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickPopulation(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.medical_information_outlined),
                  title: const Text('慢病'),
                  subtitle: Text(profile.chronics.isEmpty
                      ? '无'
                      : profile.chronics.map((e) => e.label).join('、')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickChronic(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined),
                  title: const Text('过敏原订阅'),
                  subtitle: Text(profile.allergens.isEmpty
                      ? '未订阅'
                      : '${profile.allergens.length} 项'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickAllergen(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _title('联网（可关闭）'),
          Card(
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final enabled = ref.watch(networkLookupProvider);
                    return SwitchListTile(
                      secondary: Icon(enabled ? Icons.wifi : Icons.wifi_off),
                      title: const Text('联网查商品信息'),
                      subtitle: const Text(
                          '仅用条码号查询公共数据源；关闭后完全离线，功能不受影响'),
                      value: enabled,
                      onChanged: (v) =>
                          ref.read(networkLookupProvider.notifier).setEnabled(v),
                    );
                  },
                ),
                const Divider(height: 1),
                Consumer(
                  builder: (context, ref, _) {
                    final enabled = ref.watch(domesticLookupProvider);
                    return SwitchListTile(
                      secondary: const Icon(Icons.cloud_sync_outlined),
                      title: const Text('国内第三方条码联网补充'),
                      subtitle: const Text('未命中离线库时，查第三方接口补全最新商品名'),
                      value: enabled,
                      onChanged: (v) =>
                          ref.read(domesticLookupProvider.notifier).setEnabled(v),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('第三方条码 API 密钥'),
                  subtitle: const Text('默认使用内置通道，支持自定义 RollToolsApi 凭证'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDomesticKeyDialog(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清空条码缓存'),
                  onTap: () async {
                    final store = await ref.read(localStoreProvider.future);
                    await Future.microtask(store.clearCache);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('缓存已清空')));
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _title('数据与隐私'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('配料表与照片不上传'),
                  subtitle: Text('评分全部在本机完成；只有上面的联网开关会发出条码号'),
                ),
                const Divider(height: 1),
                Consumer(
                  builder: (context, ref, _) {
                    final storeAsync = ref.watch(localStoreProvider);
                    final count = storeAsync.value?.unknownCount ?? 0;
                    return ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text('未收录配料'),
                      subtitle: Text('$count 条（用于补库，仅本机保存）'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showUnknown(context, ref),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('清除历史记录'),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('确认清除？'),
                        content: const Text('将删除本机所有扫描历史，知识库不受影响。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('确认')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(historyRepoProvider).clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('已清除')));
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _title('关于'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('应用版本'),
                  subtitle: Text('v1.0.8 (Build 9)'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('知识库版本'),
                  subtitle: Text(
                      '${packAsync.value?.version ?? '—'} · '
                      '${packAsync.value?.dataQuality ?? ''}'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('算法与数据源说明'),
                  subtitle: const Text('评分口径、阈值、已知缺陷与数据署名'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutAlgorithmPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('免责声明'),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const AlertDialog(
                      title: Text('免责声明'),
                      content: SingleChildScrollView(child: _DisclaimerText()),
                      actions: [CloseButton()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 未收录配料：查看 / 导出（导出为文本，用户自己决定要不要发出来）
  Future<void> _showUnknown(BuildContext context, WidgetRef ref) async {
    final store = await ref.read(localStoreProvider.future);
    final items = store.listUnknown();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('未收录配料',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: const Text('导出'),
                  onPressed: () async {
                    final text =
                        items.map((e) => '${e.$1}\t${e.$2}').join('\n');
                    final dir = await getApplicationDocumentsDirectory();
                    final file = File(
                        '${dir.path}/fangxinyong_unknown_${DateTime.now().millisecondsSinceEpoch}.txt');
                    await file.writeAsString('配料原文\t命中次数\n$text');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已导出到 ${file.path}')),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('这些配料不在知识库中，未参与扣分。导出后可用于补充别名表。',
                style: TextStyle(fontSize: 12, color: kTextSec)),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('暂无')),
              )
            else
              ...items.map((e) => ListTile(
                    dense: true,
                    title: Text(e.$1),
                    trailing: Text('${e.$2} 次'),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSec)),
      );

  void _pickPopulation(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusL)),
      ),
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final profile = ref.watch(profileProvider);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('关注人群',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ...Population.values.map((p) => RadioListTile<Population>(
                      title: Text(p.label),
                      value: p,
                      // ignore: deprecated_member_use
                      groupValue: profile.population,
                      // ignore: deprecated_member_use
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(profileProvider.notifier).setPopulation(val);
                          Navigator.pop(context);
                        }
                      },
                    )),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  void _pickChronic(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusL)),
      ),
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final profile = ref.watch(profileProvider);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('关注慢病（多选）',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
                ...Chronic.values.map((c) => CheckboxListTile(
                      title: Text(c.label),
                      value: profile.chronics.contains(c),
                      onChanged: (_) {
                        ref.read(profileProvider.notifier).toggleChronic(c);
                      },
                    )),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  void _pickAllergen(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusL)),
      ),
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final profile = ref.watch(profileProvider);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('过敏原订阅（多选）',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
                ...allergenOptions.map((a) => CheckboxListTile(
                      title: Text(a.nameZh),
                      value: profile.allergens.contains(a.code),
                      onChanged: (_) {
                        ref.read(profileProvider.notifier).toggleAllergen(a.code);
                      },
                    )),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDomesticKeyDialog(BuildContext context, WidgetRef ref) async {
    final keys = ref.read(domesticKeyProvider);
    final idController = TextEditingController(text: keys.$1);
    final secretController = TextEditingController(text: keys.$2);

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('第三方条码 API 密钥'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本功能对接 RollToolsApi (MXNZP) 免费商品条码接口。\n'
                  '留空时将自动使用内置公共通道；如果您拥有自己的 app_id / app_secret，可在此配置专属额度。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: idController,
                  decoration: const InputDecoration(
                    labelText: 'app_id',
                    hintText: '留空使用默认',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: secretController,
                  decoration: const InputDecoration(
                    labelText: 'app_secret',
                    hintText: '留空使用默认',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      );

      if (saved == true) {
        await ref
            .read(domesticKeyProvider.notifier)
            .setKeys(idController.text.trim(), secretController.text.trim());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('密钥配置已保存')),
          );
        }
      }
    } finally {
      idController.dispose();
      secretController.dispose();
    }
  }
}

class _DisclaimerText extends StatelessWidget {
  const _DisclaimerText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '本结果由本 App 依据公开标准（GB 2760 等）与权威评估（JECFA / IARC / EFSA）'
      '在手机本地计算得出，仅供选购参考，不构成医疗建议，也不能替代实验室检测。\n\n'
      '本 App 不对实际添加量是否超标作出判定——这需要专业机构检测。\n\n'
      '合规不等于健康，不合规也不等于一定有害。\n\n'
      '知识库为种子数据（SEED）时，数值尚未与官方原文逐条核对，请勿据此作出健康决策。',
      style: TextStyle(fontSize: 13),
    );
  }
}
