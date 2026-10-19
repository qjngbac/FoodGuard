import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../input/input_page.dart';
import '../ocr/ocr_page.dart';

/// 无数据页（docs/01 P10，docs/08 §3.11）
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, this.barcode, this.prefill});

  final String? barcode;
  final InputPrefill? prefill;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('未找到商品数据')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (prefill?.productName != null && prefill!.productName!.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(kRadiusM),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.check_circle_outline, size: 16, color: kPrimary),
                        SizedBox(width: 6),
                        Text('已自动识别商品名称',
                            style: TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      prefill!.productName!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kTextPri),
                    ),
                    if (prefill?.brand != null && prefill!.brand!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('品牌：${prefill!.brand!}',
                          style: const TextStyle(fontSize: 12, color: kTextSec)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const Icon(Icons.search_off_outlined, size: 72, color: kTextSec),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded, size: 16, color: Colors.teal.shade700),
                    const SizedBox(width: 4),
                    Text(
                      '纯离线/弱网极速模式 · 无需网络傻等',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              barcode != null && barcode!.isNotEmpty ? '条形码：$barcode' : '公开数据库暂未收录',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              prefill?.productName != null
                  ? '已为您自动识别并填好品名！请直接对准包装上的配料表拍照，App 将在本地解析成分并计算安全等级。'
                  : '国内部分预包装食品尚未收录至开源数据库中。\n您可以直接拍照包装上的配料表，或手动输入，\nApp 将在手机本地为您解析成分并计算安全等级。',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: kTextSec, height: 1.5),
            ),
            const SizedBox(height: 36),
            FilledButton.icon(
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('拍照识别配料表'),
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => OcrPage(
                    barcode: barcode,
                    productName: prefill?.productName,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('手动输入配料表'),
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => InputPage(barcode: barcode, prefill: prefill),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    );
  }
}
