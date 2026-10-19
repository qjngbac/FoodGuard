import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

/// 首次启动隐私协议弹窗（docs/13 §2.5，docs/08 §3.11）
class PrivacyDialog extends StatelessWidget {
  const PrivacyDialog({super.key});

  static const keyAgreed = 'has_agreed_privacy_v1';

  static Future<bool> hasAgreed() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(keyAgreed) ?? false;
  }

  static Future<void> markAgreed() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(keyAgreed, true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.shield_outlined, color: kPrimary, size: 24),
            SizedBox(width: 8),
            Text('隐私与自用说明', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '欢迎使用「放心用」！\n'
                '我们深知食品安全与数据隐私的重要性，特作如下郑重承诺：\n\n'
                '1. 隐私零上传：您的配料表文字、包装照片与扫描历史均仅保存在手机本机，绝不上传到任何云端服务器；\n\n'
                '2. 可选联网查数：开启“联网查商品信息”时，仅向公开数据库（Open Food Facts）发出条码号以查询名称和配料，可随时在设置中一键关闭，关闭后 100% 离线运行；\n\n'
                '3. 无埋点无广告：不采集手机号、位置、设备 ID 等任何个人信息，不投放任何商业广告；\n\n'
                '4. 参考免责：评分由端上算法依据国家标准（GB 2760 等）与权威评估自动计算，仅供日常选购参考，不替代专业实验室检测与医疗诊断。',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('不同意并退出', style: TextStyle(color: kTextSec)),
          ),
          FilledButton(
            onPressed: () async {
              await markAgreed();
              if (context.mounted) Navigator.of(context).pop(true);
            },
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
  }
}
