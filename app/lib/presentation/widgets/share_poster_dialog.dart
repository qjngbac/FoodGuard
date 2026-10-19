import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entity/score_result.dart';

/// 食品评级测评海报弹窗（支持 3x 高清长图生成、保存与分享）
class SharePosterDialog extends StatefulWidget {
  const SharePosterDialog({
    super.key,
    required this.result,
    this.productName,
    this.barcode,
  });

  final ScoreResult result;
  final String? productName;
  final String? barcode;

  @override
  State<SharePosterDialog> createState() => _SharePosterDialogState();
}

class _SharePosterDialogState extends State<SharePosterDialog> {
  final GlobalKey _posterKey = GlobalKey();
  bool _isSaving = false;

  String _buildShareText(String title, String tldr) {
    final grade = widget.result.personalGrade;
    return '【$title】安全评级测评：\n'
        '• 安全分：${widget.result.score}（${grade.label} ${grade.desc}）\n'
        '• 健康结论：$tldr\n'
        '• 食品添加剂：${widget.result.additiveItems.length} 种\n'
        '• 加工度：NOVA ${widget.result.nova.group} 类\n'
        '—— 来自「放心用」端上安全评级';
  }

  Future<void> _savePosterImage(String title, String tldr) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      // 保证渲染树绘制就绪
      await Future.delayed(const Duration(milliseconds: 60));
      final boundary = _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('未找到海报渲染节点');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('生成图片数据流失败');
      }
      final pngBytes = byteData.buffer.asUint8List();

      Directory? saveDir;
      try {
        if (Platform.isAndroid) {
          final dirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
          if (dirs != null && dirs.isNotEmpty) {
            saveDir = dirs.first;
          }
        }
        saveDir ??= await getApplicationDocumentsDirectory();
      } catch (_) {
        saveDir = await getApplicationDocumentsDirectory();
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${saveDir.path}/fangxinyong_share_$ts.png');
      await file.writeAsBytes(pngBytes);

      // 同步复制文字到剪贴板，方便双渠道分享
      Clipboard.setData(ClipboardData(text: _buildShareText(title, tldr)));

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);

      messenger.showSnackBar(
        SnackBar(
          content: Text('🎉 高清评测海报已生成并保存！\n路径：${file.path}\n评测文字摘要也已为您复制到剪贴板。'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成海报失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grade = widget.result.personalGrade;
    final color = gradeColor(grade);
    final title = (widget.productName?.isNotEmpty ?? false)
        ? widget.productName!
        : (widget.barcode?.isNotEmpty ?? false ? '条码: ${widget.barcode}' : '未命名商品');

    final tldr = _getVerdictText(grade, widget.result);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // RepaintBoundary 包裹海报主体卡片（生成 3x 超清长图）
          RepaintBoundary(
            key: _posterKey,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(kRadiusL),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusL),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 顶部品牌头图
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color, color.withValues(alpha: 0.85)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.shield, color: Colors.white, size: 22),
                              SizedBox(width: 8),
                              Text(
                                '放心用 · 食品安全评级',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              '端上离线测评',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 内容区
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: kTextPri,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.barcode != null && widget.barcode!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '商品条码: ${widget.barcode}',
                              style: const TextStyle(fontSize: 11, color: kTextSec),
                            ),
                          ],
                          const SizedBox(height: 14),

                          // 得分与等级大徽章
                          Row(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withValues(alpha: 0.12),
                                  border: Border.all(color: color, width: 3),
                                ),
                                child: Center(
                                  child: Text(
                                    '${widget.result.score}',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(kRadiusS),
                                      ),
                                      child: Text(
                                        '${grade.label}  ${grade.desc}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '共识别出 ${widget.result.additiveItems.length} 种食品添加剂 · 加工度 NOVA${widget.result.nova.group}',
                                      style: const TextStyle(fontSize: 11, color: kTextSec),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 大白话选购结论条
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(kRadiusM),
                              border: Border.all(color: color.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  grade == Grade.a
                                      ? '🌟'
                                      : (grade == Grade.b
                                          ? '✅'
                                          : (grade == Grade.bMinus || grade == Grade.c
                                              ? '⚠️'
                                              : '⛔')),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tldr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: color,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 关键摘要小药丸
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (widget.result.additiveItems.isEmpty)
                                _pill('零添加剂', kPrimary)
                              else
                                _pill('${widget.result.additiveItems.length}种添加剂',
                                    widget.result.additiveItems.length <= 3 ? kPrimary : kGradeC),
                              if (widget.result.additiveItems.any((e) => e.riskLevel >= 4))
                                _pill('含较高风险成分', kGradeD),
                              if (widget.result.allergenHits.isNotEmpty)
                                _pill('含致敏原', kGradeC),
                              _pill('NOVA ${widget.result.nova.group}类加工', kTextSec),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 底部小水印与时间戳
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('扫码识别配料 · 守护舌尖健康',
                                  style: TextStyle(fontSize: 10, color: kTextSec)),
                              Text(
                                '测评于 ${DateTime.now().year}.${DateTime.now().month.toString().padLeft(2, '0')}.${DateTime.now().day.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 9.5, color: kTextSec),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 操作按钮（保存高清海报 + 复制文字 + 关闭）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
                onPressed: _isSaving ? null : () => _savePosterImage(title, tldr),
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(_isSaving ? '生成中…' : '保存高清海报'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: kTextPri,
                  minimumSize: Size.zero,
                  side: BorderSide(color: kDivider.withValues(alpha: 0.8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                ),
                onPressed: () {
                  final text = _buildShareText(title, tldr);
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制测评摘要到剪贴板，可前往微信/小红书直接粘贴分享')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制摘要'),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.85),
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: kTextPri),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  static String _getVerdictText(Grade grade, ScoreResult result) {
    final risk4 = result.additiveItems.where((e) => e.riskLevel >= 4).length;
    switch (grade) {
      case Grade.a:
        return '本次评估未检出高风险添加剂，配料简单，营养结构相对均衡。';
      case Grade.b:
        return '配料较常规，检出少量低风险乳化/增稠剂，营养与安全性良好，日常可适量食用。';
      case Grade.bMinus:
        return '存在一定关注项（如较高糖钠或特定添加剂），建议老人、儿童或慢病人群适量节制。';
      case Grade.c:
        if (risk4 > 0) {
          return '属于深加工食品，检出 $risk4 种较高关注度添加剂，敏感人群及儿童建议控制摄入频次。';
        }
        return '加工度与糖钠含量较高，属于偶尔解馋型食品，不建议作为长期日常主食。';
      case Grade.d:
        return '检出高风险成分、疑似超范围使用或严重失衡营养，建议避免购买或寻找更健康的替代品！';
      case Grade.unknown:
        return '缺少配料表原文，未能完成评估，请在 App 内拍照或手动录入配料后重试。';
    }
  }
}
