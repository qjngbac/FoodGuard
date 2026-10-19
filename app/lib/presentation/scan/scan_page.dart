import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/checksum.dart';
import '../../data/history_repository.dart';
import '../../data/providers.dart';
import '../compare/compare_page.dart';

/// 比对候选条目
class CandidateItem {
  CandidateItem({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.score,
    required this.grade,
    required this.record,
  });

  final String barcode;
  final String name;
  final String? brand;
  final int score;
  final String grade;
  final ScanRecord record;
}

/// 条码扫描页
/// 说明：使用 mobile_scanner（端上识别，不联网）；
/// 针对易拉罐/细铝箔包装优化：支持 autoZoom、1x/2x变焦、手电筒补光、触感反馈与全码制；
/// 新增「超市比对小助手」连续扫描模式：取景不中断、多品托盘沉淀、一键横评对比。
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    autoZoom: true,
    detectionSpeed: DetectionSpeed.unrestricted,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
    ],
  );

  late final AnimationController _animController;
  late final Animation<double> _laserAnim;

  bool _handled = false;
  bool _torchOn = false;
  double _zoomScale = 0.0; // 0.0 = 1x, 0.35 = ~2x

  // 连续扫描模式（超市比对小助手）
  bool _continuousMode = false;
  final List<CandidateItem> _candidates = [];
  String? _lastScannedBarcode;
  int _lastScannedTime = 0;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _laserAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
    } catch (_) {
      if (!mounted) return;
      setState(() => _torchOn = false);
      _showToast('本机不支持手电筒补光');
    }
  }

  void _onDetect(BarcodeCapture capture) {
    // 上层还有弹窗/页面时不处理：否则隐藏页会被后台相机持续 setState
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;
    // 只接受校验位合法的食品商品码：误读码/箱码/二维码不得进入查库、缓存、历史与网络请求
    final code = BarcodeChecksum.toProductCode(raw);
    if (code == null) {
      if (_continuousMode) _showToast('校验位不合法或非商品码，已忽略');
      return;
    }

    if (!_continuousMode) {
      if (_handled) return;
      _handled = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(code);
      return;
    }

    // 连续比对模式：节流防抖
    final now = DateTime.now().millisecondsSinceEpoch;
    if (code == _lastScannedBarcode && now - _lastScannedTime < 1800) {
      return;
    }
    _lastScannedBarcode = code;
    _lastScannedTime = now;

    if (_candidates.any((c) => c.barcode == code)) {
      HapticFeedback.selectionClick();
      _showToast('该商品已在对比托盘中');
      return;
    }

    HapticFeedback.mediumImpact();
    _addCandidateFromBarcode(code);
  }

  Future<void> _addCandidateFromBarcode(String barcode) async {
    if (!mounted) return;
    setState(() => _isResolving = true);

    try {
      // 1. 先查本地已有的扫描历史
      final existing = await ref.read(historyRepoProvider).findByBarcode(barcode);
      if (existing != null) {
        final cand = CandidateItem(
          barcode: barcode,
          name: (existing.productName?.isNotEmpty ?? false) ? existing.productName! : '条码 $barcode',
          brand: existing.brand,
          score: existing.score,
          grade: existing.grade,
          record: existing,
        );
        if (mounted) {
          setState(() {
            _candidates.add(cand);
            _isResolving = false;
          });
          _showToast('已录入：${cand.name} (${cand.score}分)');
        }
        return;
      }

      // 2. 查种子库/缓存/网络
      final doLookup = ref.read(barcodeLookupProvider);
      final lookup = await doLookup(barcode);
      if (lookup != null && lookup.hasIngredients) {
        final res = await ref.read(analysisProvider.notifier).analyze(
          ingredientsText: lookup.ingredientsText!,
          nutrition: lookup.nutrition,
          categoryCode: lookup.categoryHint,
          barcode: barcode,
          productName: lookup.nameZh,
        );
        final saved = await ref.read(historyRepoProvider).findByBarcode(barcode);
        if (res != null && saved != null) {
          final cand = CandidateItem(
            barcode: barcode,
            name: (saved.productName?.isNotEmpty ?? false) ? saved.productName! : '商品 $barcode',
            brand: saved.brand ?? lookup.brand,
            score: saved.score,
            grade: saved.grade,
            record: saved,
          );
          if (mounted) {
            setState(() {
              _candidates.add(cand);
              _isResolving = false;
            });
            _showToast('已录入：${cand.name} (${cand.score}分)');
          }
          return;
        }
      }

      // 3. 兜底记录
      final fallbackRec = ScanRecord(
        id: 'temp_$barcode',
        score: 0,
        grade: '?',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        result: {},
        barcode: barcode,
        productName: lookup?.nameZh ?? '条码 $barcode',
        brand: lookup?.brand,
      );
      final cand = CandidateItem(
        barcode: barcode,
        name: lookup?.nameZh ?? '未收录配料 ($barcode)',
        brand: lookup?.brand,
        score: 0,
        grade: '?',
        record: fallbackRec,
      );
      if (mounted) {
        setState(() {
          _candidates.add(cand);
          _isResolving = false;
        });
        _showToast('已加入：$barcode');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isResolving = false);
      }
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boxWidth = MediaQuery.of(context).size.width * 0.82;
    const boxHeight = 180.0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          '扫描条形码',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // 连续扫描模式开关
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: InkWell(
              onTap: () {
                setState(() => _continuousMode = !_continuousMode);
                HapticFeedback.selectionClick();
              },
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _continuousMode ? Colors.amber.shade700 : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _continuousMode ? Colors.amberAccent : const Color(0xFFCBD5E1),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _continuousMode ? Icons.auto_awesome : Icons.compare_arrows,
                      size: 15,
                      color: _continuousMode ? Colors.white : kTextPri,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _continuousMode ? '比对中' : '连续比对',
                      style: TextStyle(
                        color: _continuousMode ? Colors.white : kTextPri,
                        fontSize: 12,
                        fontWeight: _continuousMode ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 1x / 2x 快速变焦按钮（专治小条码与微距模糊）
          IconButton(
            tooltip: '切换 1x / 2x 变焦',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _zoomScale > 0 ? kPrimary : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _zoomScale > 0 ? Colors.transparent : const Color(0xFFCBD5E1)),
              ),
              child: Text(
                _zoomScale > 0 ? '2x' : '1x',
                style: TextStyle(
                  color: _zoomScale > 0 ? Colors.white : kTextPri,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onPressed: () async {
              final next = _zoomScale == 0.0 ? 0.35 : 0.0;
              setState(() => _zoomScale = next);
              try {
                await _controller.setZoomScale(next);
              } catch (_) {}
            },
          ),
          // 手电筒常亮补光
          IconButton(
            tooltip: '手电筒补光',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
            icon: Icon(
              _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
              color: _torchOn ? Colors.amber.shade700 : kTextPri,
            ),
            onPressed: _toggleTorch,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.no_photography_outlined, size: 56, color: kTextSec),
                    const SizedBox(height: 12),
                    Text('摄像头不可用：${error.errorCode}'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _showManual,
                      child: const Text('手动输入条码'),
                    ),
                  ],
                ),
              ),
            ),
            onDetect: _onDetect,
          ),
          // 取景框与动态激光扫描线
          Positioned(
            top: MediaQuery.of(context).size.height * 0.16,
            left: (MediaQuery.of(context).size.width - boxWidth) / 2,
            child: SizedBox(
              width: boxWidth,
              height: boxHeight,
              child: Stack(
                children: [
                  // 取景边框
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: _continuousMode ? Colors.amber : kPrimary, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  // 动态上下往复激光扫描线
                  AnimatedBuilder(
                    animation: _laserAnim,
                    builder: (context, child) {
                      final scanColor = _continuousMode ? Colors.amber : kPrimary;
                      return Positioned(
                        top: _laserAnim.value * (boxHeight - 4),
                        left: 6,
                        right: 6,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                scanColor,
                                Colors.white,
                                scanColor,
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: scanColor.withValues(alpha: 0.8),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // 顶部提示条
          Positioned(
            top: 16,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _continuousMode
                      ? '🛒 超市比对模式：对准多款条码连续扫入'
                      : '将包装条码对准框内 · 离线毫秒级解析',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
          // 易拉罐与塑料瓶强光/弧面反光抑制指引（非连续模式下）
          if (!_continuousMode) ...[
            Positioned(
              bottom: 165,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wb_incandescent_outlined, size: 14, color: Colors.amberAccent),
                      SizedBox(width: 6),
                      Text(
                        '易拉罐/塑料反光？手机微倾15°或开启补光灯',
                        style: TextStyle(color: Colors.white, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 取景框下方大拇指快捷浮岛
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: _buildThumbControlIsland(),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  icon: const Icon(Icons.keyboard),
                  label: const Text('手动输入条码'),
                  onPressed: _showManual,
                ),
              ),
            ),
          ],
          // 连续扫描比对模式：底部候选小托盘（Dock）
          if (_continuousMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildContinuousDock(),
            ),
        ],
      ),
    );
  }

  /// 取景框下方大拇指快捷浮岛
  Widget _buildThumbControlIsland() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white24, width: 1),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _toggleTorch,
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _torchOn ? Colors.amber.shade700 : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: _torchOn
                      ? [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                      size: 17,
                      color: _torchOn ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _torchOn ? '补光已开' : '补光灯',
                      style: TextStyle(
                        color: _torchOn ? Colors.white : Colors.white70,
                        fontSize: 12.5,
                        fontWeight: _torchOn ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 18, color: Colors.white24),
            const SizedBox(width: 8),
            InkWell(
              onTap: () async {
                HapticFeedback.selectionClick();
                final next = _zoomScale == 0.0 ? 0.35 : 0.0;
                setState(() => _zoomScale = next);
                try {
                  await _controller.setZoomScale(next);
                } catch (_) {}
              },
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _zoomScale > 0 ? kPrimary : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.zoom_in, size: 17, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      _zoomScale > 0 ? '2x' : '1x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 连续比对模式：底部候选托盘（Mini-Dock）
  Widget _buildContinuousDock() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 托盘标题栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.shopping_basket_outlined, color: Colors.amberAccent, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '已扫入 ${_candidates.length} 款备选',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  if (_isResolving) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                    ),
                  ],
                ],
              ),
              if (_candidates.isNotEmpty)
                InkWell(
                  onTap: () => setState(() => _candidates.clear()),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('清空', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 候选商品横向滚动条
          if (_candidates.isEmpty)
            Container(
              height: 54,
              alignment: Alignment.center,
              child: const Text(
                '对准货架上的 2~5 款商品包装条码\n即可在此聚合横评对比',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            )
          else
            SizedBox(
              height: 56,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _candidates.length,
                itemBuilder: (context, i) {
                  final item = _candidates[i];
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: gradeColor(item.record.gradeEnum),
                          child: Text(
                            item.grade,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 90),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${item.score}分',
                                style: const TextStyle(color: Colors.white70, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => setState(() => _candidates.removeAt(i)),
                          child: const Icon(Icons.close, size: 15, color: Colors.white60),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          // 动作按钮栏
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                icon: const Icon(Icons.keyboard, size: 16),
                label: const Text('补录条码', style: TextStyle(fontSize: 12)),
                onPressed: _showManual,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _candidates.length >= 2 ? kPrimary : Colors.white24,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: _candidates.length >= 2 ? () => _openMultiCompareModal(context) : null,
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  label: Text(
                    _candidates.length >= 2 ? '一键横评对比 (${_candidates.length}款)' : '需扫入至少 2 款',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 唤起多品横评模态弹窗或进入对比页
  void _openMultiCompareModal(BuildContext context) {
    if (_candidates.length == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ComparePage(
            candidateRecords: _candidates.map((e) => e.record).toList(),
            initialRecordId: _candidates[0].record.id,
            initialRightRecordId: _candidates[1].record.id,
          ),
        ),
      );
      return;
    }

    // 超过 2 款时展示横评榜单弹窗
    final sorted = List<CandidateItem>.from(_candidates)
      ..sort((a, b) => b.score.compareTo(a.score));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.leaderboard_outlined, color: kPrimary),
                      const SizedBox(width: 8),
                      Text(
                        '超市比对横评榜 (${sorted.length}款)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Text(
                '已为您按食品安全分从高到低排列（🥇 第一名为最健康之选）：',
                style: TextStyle(fontSize: 12, color: kTextSec),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final item = sorted[idx];
                    final rankMedal = idx == 0
                        ? '🥇'
                        : idx == 1
                            ? '🥈'
                            : idx == 2
                                ? '🥉'
                                : '${idx + 1}';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(rankMedal, style: const TextStyle(fontSize: 20)),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${item.brand != null ? '${item.brand} · ' : ''}条码: ${item.barcode}',
                        style: const TextStyle(fontSize: 11, color: kTextSec),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: gradeColor(item.record.gradeEnum),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${item.score}分 · ${item.grade}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ComparePage(
                                    candidateRecords: _candidates.map((e) => e.record).toList(),
                                    initialRecordId: sorted.first.record.id,
                                    initialRightRecordId: item.record.id,
                                  ),
                                ),
                              );
                            },
                            child: const Text('PK 第一名', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ComparePage(
                          candidateRecords: _candidates.map((e) => e.record).toList(),
                          initialRecordId: sorted[0].record.id,
                          initialRightRecordId: sorted[1].record.id,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('深入对比前两名 (冠军 vs 亚军)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showManual() async {
    final controller = TextEditingController();
    String? errorText;
    try {
      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (sheetCtx) => StatefulBuilder(
          builder: (ctx, setModalState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('手动输入条形码', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '例如 6901234567892',
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setModalState(() => errorText = null);
                    }
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    final code = BarcodeChecksum.toProductCode(text);
                    if (code == null) {
                      setModalState(() => errorText = '校验位不合法或不是标准商品码，请核对');
                      return;
                    }
                    Navigator.pop(sheetCtx, code);
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (result != null && result.isNotEmpty) {
        if (_continuousMode) {
          _addCandidateFromBarcode(result);
        } else {
          Navigator.of(context).pop(result);
        }
      }
    } finally {
      controller.dispose();
    }
  }
}
