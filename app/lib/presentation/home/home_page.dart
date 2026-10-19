import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/history_repository.dart';
import '../../data/providers.dart';
import '../../data/remote/off_provider.dart';
import '../../domain/data/knowledge_pack.dart';
import '../compare/compare_page.dart';
import '../history/history_page.dart';
import '../input/input_page.dart';
import '../notfound/notfound_page.dart';
import '../ocr/ocr_page.dart';
import '../result/result_page.dart';
import '../scan/scan_page.dart';
import '../settings/settings_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, required this.pack});

  final KnowledgePack pack;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<ScanRecord> _recent = [];
  DateTime? _lastBackTime;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final list = await ref.read(historyRepoProvider).list(limit: 10);
    if (!mounted) return;
    setState(() => _recent = list);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 9) return '早上好 · 守护舌尖安全';
    if (hour < 12) return '上午好 · 吃得明白更健康';
    if (hour < 18) return '下午好 · 选对零食少负担';
    return '晚上好 · 清淡饮食好睡眠';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackTime == null ||
            now.difference(_lastBackTime!) > const Duration(seconds: 2)) {
          _lastBackTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('再按一次退出放心用'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield, color: Colors.white, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('放心用',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text(_greeting(),
                    style: const TextStyle(fontSize: 11, color: kTextSec, fontWeight: FontWeight.normal)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置与健康偏好',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage()))
                .then((_) => _loadRecent()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecent,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _scanCard(context),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _entryCard(
                    context,
                    icon: Icons.edit_note,
                    title: '手动输入',
                    subtitle: '粘贴配料表',
                    color: const Color(0xFFE8F4FD),
                    iconColor: const Color(0xFF1976D2),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InputPage()),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _entryCard(
                    context,
                    icon: Icons.camera_alt_outlined,
                    title: '拍照识别',
                    subtitle: '离线OCR',
                    color: const Color(0xFFFFF3E0),
                    iconColor: const Color(0xFFE65100),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const OcrPage()))
                        .then((_) => _loadRecent()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _entryCard(
                    context,
                    icon: Icons.compare_arrows,
                    title: '货比三家',
                    subtitle: '双品PK',
                    color: const Color(0xFFE0F2F1),
                    iconColor: const Color(0xFF00796B),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ComparePage()))
                        .then((_) => _loadRecent()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _sectionTitle('最近扫描', trailing: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const HistoryPage()))
                  .then((_) => _loadRecent()),
              child: const Text('全部'),
            )),
            if (_recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.qr_code_scanner, size: 48, color: kDivider),
                      SizedBox(height: 8),
                      Text('还没有扫描记录，点击上方扫一扫开始吧',
                          style: TextStyle(color: kTextSec, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              ..._recent.map((r) => _recordTile(context, r)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}

  Widget _scanCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadiusL),
        gradient: const LinearGradient(
          colors: [Color(0xFF00B578), Color(0xFF008954)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('端上智能评级 · 离线可用',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 10),
                const Text('对准包装条形码',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('3 秒看懂配料表与安全等级',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ScanPage()))
                .then((v) {
              if (v != null) _openAnalysis(v as String?);
              _loadRecent();
            }),
            borderRadius: BorderRadius.circular(kRadiusM),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(kRadiusM),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.qr_code_scanner, color: kPrimaryDark, size: 36),
            ),
          ),
        ],
      ),
    );
  }

  /// 扫到条码后：先查本地缓存，再（若开启联网）查 Open Food Facts。
  /// 若查得完整配料表直接端上评分进入结果页；未查得则引导至 NotFoundPage。
  Future<void> _openAnalysis(String? barcode) async {
    if (barcode == null) return;
    if (!mounted) return;

    // 弹出即时识别加载提示，避免查库/查网时的假死感
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  const Text('正在识别条形码...',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(barcode,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    ProductLookup? lookup;
    try {
      final doLookup = ref.read(barcodeLookupProvider);
      lookup = await doLookup(barcode);
    } catch (_) {
      lookup = null;
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // 关闭加载弹窗
      }
    }
    if (!mounted) return;

    if (lookup != null && lookup.hasIngredients) {
      // 拥有完整配料表：端上直接评分，3秒直达结果页！
      final result = await ref.read(analysisProvider.notifier).analyze(
        ingredientsText: lookup.ingredientsText!,
        nutrition: lookup.nutrition,
        categoryCode: lookup.categoryHint,
        barcode: barcode,
        productName: lookup.nameZh,
      );
      if (!mounted) return;
      if (result != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResultPage()),
        );
        _loadRecent();
        return;
      }
    }

    final prefill = lookup == null
        ? InputPrefill(barcode: barcode)
        : InputPrefill(
            barcode: barcode,
            productName: lookup.nameZh,
            brand: lookup.brand,
            ingredients: lookup.ingredientsText,
            nutrition: lookup.nutrition,
            inputSource: lookup.source,
          );

    final ok = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotFoundPage(barcode: barcode, prefill: prefill),
      ),
    );
    if (ok == true || ok == null) _loadRecent();
  }

  Widget _entryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusM),
        side: BorderSide(color: kDivider.withValues(alpha: 0.8)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusM),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(height: 8),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextPri)),
              const SizedBox(height: 2),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: kTextSec)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ?trailing,
      ],
    );
  }

  Widget _recordTile(BuildContext context, ScanRecord r) {
    final gradeColorVal = gradeColor(r.gradeEnum);
    final additiveCount = (r.result['additiveItems'] as List?)?.length ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusM),
        side: BorderSide(color: kDivider.withValues(alpha: 0.6)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: gradeColorVal.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: gradeColorVal, width: 2),
          ),
          child: Center(
            child: Text(
              r.grade,
              style: TextStyle(
                color: gradeColorVal,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
        title: Text(
          (r.productName?.isNotEmpty ?? false) ? r.productName! : (r.barcode ?? '未命名商品'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: gradeColorVal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${r.score}分',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: gradeColorVal),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                additiveCount > 0 ? '$additiveCount种添加剂' : '无添加剂',
                style: const TextStyle(fontSize: 11, color: kTextSec),
              ),
              const SizedBox(width: 6),
              Text('· ${_timeAgo(r.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: kTextSec)),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20, color: kTextSec),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ResultPage(recordId: r.id)),
          );
          _loadRecent();
        },
      ),
    );
  }

  String _timeAgo(int ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    final m = diff ~/ 60000;
    if (m < 1) return '刚刚';
    if (m < 60) return '$m 分钟前';
    final h = m ~/ 60;
    if (h < 24) return '$h 小时前';
    return '${h ~/ 24} 天前';
  }
}
