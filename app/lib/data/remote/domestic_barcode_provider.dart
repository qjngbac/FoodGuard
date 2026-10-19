import 'dart:convert';

import 'package:http/http.dart' as http;

import 'off_provider.dart';

/// 国内第三方条形码开放接口（对接 RollToolsApi / MXNZP 免费接口，极速超时兜底）
class DomesticBarcodeProvider {
  DomesticBarcodeProvider({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// 公共体验凭证（支持用户在设置页自定义）
  static const String defaultAppId = 'free_trial';
  static const String defaultAppSecret = 'free_trial';

  Future<ProductLookup?> fetch(
    String barcode, {
    String? appId,
    String? appSecret,
  }) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;

    final id = (appId != null && appId.trim().isNotEmpty) ? appId.trim() : defaultAppId;
    final secret = (appSecret != null && appSecret.trim().isNotEmpty)
        ? appSecret.trim()
        : defaultAppSecret;

    final uri = Uri.https('www.mxnzp.com', '/api/barcode/goods/details', {
      'barcode': cleanBarcode,
      'need_words': 'true',
      'app_id': id,
      'app_secret': secret,
    });

    try {
      final resp = await _client
          .get(uri)
          .timeout(const Duration(milliseconds: 1200)); // 1.2秒极速熔断，弱网/断网不傻等

      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (json['code'] != 1) return null;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      final goodsName = data['goodsName']?.toString();
      final brand = data['brand']?.toString();
      final standard = data['standard']?.toString();

      if (goodsName == null || goodsName.trim().isEmpty) return null;

      final fullName = (standard != null &&
              standard.trim().isNotEmpty &&
              !goodsName.contains(standard))
          ? '${goodsName.trim()} ${standard.trim()}'
          : goodsName.trim();

      return ProductLookup(
        barcode: cleanBarcode,
        nameZh: fullName,
        brand: brand?.trim().isNotEmpty == true ? brand!.trim() : null,
        quantity: standard?.trim().isNotEmpty == true ? standard!.trim() : null,
        source: 'DOMESTIC_API',
      );
    } catch (_) {
      return null;
    }
  }
}
