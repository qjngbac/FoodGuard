import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entity/nutrition_facts.dart';

/// 条码 → 商品信息 的查询结果
class ProductLookup {
  const ProductLookup({
    required this.barcode,
    this.nameZh,
    this.brand,
    this.quantity,
    this.imageUrl,
    this.ingredientsText,
    this.nutrition,
    this.allergens = const [],
    this.novaGroup,
    this.categoryHint,
    this.source = 'OFF',
  });

  final String barcode;
  final String? nameZh;
  final String? brand;
  final String? quantity;
  final String? imageUrl;
  final String? ingredientsText;
  final NutritionFacts? nutrition;
  final List<String> allergens;
  final int? novaGroup;
  final String? categoryHint;
  final String source;

  bool get hasIngredients =>
      ingredientsText != null && ingredientsText!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'nameZh': nameZh,
        'brand': brand,
        'quantity': quantity,
        'imageUrl': imageUrl,
        'ingredientsText': ingredientsText,
        'nutrition': nutrition?.toJson(),
        'allergens': allergens,
        'novaGroup': novaGroup,
        'categoryHint': categoryHint,
        'source': source,
      };

  static ProductLookup? fromJson(Map<String, dynamic> j) => ProductLookup(
        barcode: j['barcode']?.toString() ?? '',
        nameZh: j['nameZh']?.toString(),
        brand: j['brand']?.toString(),
        quantity: j['quantity']?.toString(),
        imageUrl: j['imageUrl']?.toString(),
        ingredientsText: j['ingredientsText']?.toString(),
        nutrition: NutritionFacts.fromJson(
            j['nutrition'] is Map ? Map<String, dynamic>.from(j['nutrition']) : null),
        allergens: (j['allergens'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        novaGroup: (j['novaGroup'] as num?)?.toInt(),
        categoryHint: j['categoryHint']?.toString(),
        source: j['source']?.toString() ?? 'OFF',
      );
}

/// Open Food Facts 查询（ODbL 许可，必须具名 User-Agent）
/// 关闭"联网查询"后本类不会被调用，App 完全离线运行。
class OpenFoodFactsProvider {
  OpenFoodFactsProvider({http.Client? client, this.userAgent = kUserAgent})
      : _client = client ?? http.Client();

  static const String kUserAgent = 'FangXinYong/1.0 (self-use food label scanner)';

  final http.Client _client;
  final String userAgent;

  /// 返回 null 表示"未找到"或"查询失败"（调用方都应降级到手动输入）
  Future<ProductLookup?> fetch(String barcode) async {
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$barcode.json', {
      'fields': 'code,product_name,product_name_zh,generic_name_zh,brands,quantity,'
          'image_url,image_front_small_url,ingredients_text,ingredients_text_zh,'
          'allergens_tags,traces_tags,nutriments,nova_group,categories_tags',
      'lc': 'zh',
    });
    try {
      final resp = await _client
          .get(uri, headers: {'User-Agent': userAgent})
          .timeout(const Duration(milliseconds: 1200)); // 1.2秒极速熔断，断网不卡顿
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (json['status'] != 1) return null;
      final p = json['product'] as Map<String, dynamic>?;
      if (p == null) return null;

      final nut = p['nutriments'] as Map<String, dynamic>?;
      return ProductLookup(
        barcode: barcode,
        nameZh: (p['product_name_zh'] ?? p['generic_name_zh'] ?? p['product_name'])
            ?.toString(),
        brand: p['brands']?.toString(),
        quantity: p['quantity']?.toString(),
        imageUrl: (p['image_url'] ?? p['image_front_small_url'])?.toString(),
        ingredientsText:
            (p['ingredients_text_zh'] ?? p['ingredients_text'])?.toString(),
        nutrition: _nutrition(nut),
        allergens: _allergens(p),
        novaGroup: (p['nova_group'] as num?)?.toInt(),
        categoryHint: (p['categories_tags'] is List &&
                (p['categories_tags'] as List).isNotEmpty)
            ? (p['categories_tags'] as List).first.toString()
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  NutritionFacts? _nutrition(Map<String, dynamic>? n) {
    if (n == null) return null;
    double? d(String key) {
      final v = n[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final sodiumG = d('sodium_100g');
    final facts = NutritionFacts(
      energyKj: d('energy-kj_100g') ??
          ((d('energy-kcal_100g') ?? 0) * 4.184 > 0
              ? (d('energy-kcal_100g')! * 4.184)
              : null),
      proteinG: d('proteins_100g'),
      fatG: d('fat_100g'),
      saturatedFatG: d('saturated-fat_100g'),
      transFatG: d('trans-fat_100g'),
      carbohydrateG: d('carbohydrates_100g'),
      sugarG: d('sugars_100g'),
      dietaryFiberG: d('fiber_100g'),
      sodiumMg: sodiumG == null ? null : sodiumG * 1000,
    );
    return facts.isEmpty ? null : facts;
  }

  List<String> _allergens(Map<String, dynamic> p) {
    final out = <String>[];
    for (final key in ['allergens_tags', 'traces_tags']) {
      final list = p[key];
      if (list is List) {
        for (final e in list) {
          final s = e.toString(); // 形如 "en:peanuts"
          final code = s.split(':').last.toUpperCase();
          final mapped = _mapAllergen(code);
          if (mapped != null && !out.contains(mapped)) out.add(mapped);
        }
      }
    }
    return out;
  }

  static String? _mapAllergen(String code) {
    const map = {
      'GLUTEN': 'GLUTEN',
      'PEANUTS': 'PEANUT',
      'SOYBEANS': 'SOY',
      'MILK': 'MILK',
      'NUTS': 'NUT',
      'EGGS': 'EGG',
      'FISH': 'FISH',
      'CRUSTACEANS': 'CRUSTACEAN',
      'SESAME': 'SESAME',
      'SULPHUR-DIOXIDE-AND-SULPHITES': 'SULFITE',
      'SULFITES': 'SULFITE',
      'CELERY': null,
    };
    return map[code];
  }

  void dispose() => _client.close();
}
