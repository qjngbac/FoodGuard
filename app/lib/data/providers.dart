import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/data/knowledge_pack.dart';
import '../domain/entity/ingredient.dart';
import '../domain/entity/nutrition_facts.dart';
import '../domain/entity/score_result.dart';
import '../domain/entity/user_profile.dart';
import '../domain/service/additive_matcher.dart';
import '../domain/service/category_mapper.dart';
import '../domain/service/ingredient_parser.dart';
import '../domain/service/scoring_engine.dart';
import 'history_repository.dart';
import 'knowledge_repository.dart';
import 'local_store.dart';
import 'ocr/ocr_service.dart';
import 'remote/domestic_barcode_provider.dart';
import 'remote/off_provider.dart';

final knowledgeRepoProvider = Provider<KnowledgeRepository>((ref) => KnowledgeRepository());
final historyRepoProvider = Provider<HistoryRepository>((ref) => HistoryRepository());

/// 端上轻量存储（条码缓存 + 未收录配料）
final localStoreProvider = FutureProvider<LocalStore>((ref) => LocalStore.open());

/// 联网查询商品信息（Open Food Facts）。可一键关闭，关闭后完全离线。
final offProvider = Provider<OpenFoodFactsProvider>((ref) {
  final provider = OpenFoodFactsProvider();
  ref.onDispose(provider.dispose);
  return provider;
});

/// 国内第三方条形码开放接口（RollToolsApi）
final domesticBarcodeProvider =
    Provider<DomesticBarcodeProvider>((ref) => DomesticBarcodeProvider());

class NetworkLookupController extends StateNotifier<bool> {
  NetworkLookupController() : super(false) {
    _load();
  }

  static const _key = 'setting_network_lookup';

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      state = sp.getBool(_key) ?? false;
    } catch (_) {}
  }

  Future<void> setEnabled(bool v) async {
    state = v;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_key, v);
    } catch (_) {}
  }
}

final networkLookupProvider =
    StateNotifierProvider<NetworkLookupController, bool>((ref) => NetworkLookupController());

class DomesticLookupController extends StateNotifier<bool> {
  DomesticLookupController() : super(false) {
    _load();
  }

  static const _key = 'setting_domestic_lookup';

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      state = sp.getBool(_key) ?? false;
    } catch (_) {}
  }

  Future<void> setEnabled(bool v) async {
    state = v;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_key, v);
    } catch (_) {}
  }
}

final domesticLookupProvider =
    StateNotifierProvider<DomesticLookupController, bool>((ref) => DomesticLookupController());

class DomesticKeyController extends StateNotifier<(String, String)> {
  DomesticKeyController() : super(('', '')) {
    _load();
  }

  static const _keyId = 'setting_domestic_app_id';
  static const _keySecret = 'setting_domestic_app_secret';

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      state = (sp.getString(_keyId) ?? '', sp.getString(_keySecret) ?? '');
    } catch (_) {}
  }

  Future<void> setKeys(String id, String secret) async {
    state = (id, secret);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyId, id);
      await sp.setString(_keySecret, secret);
    } catch (_) {}
  }
}

final domesticKeyProvider =
    StateNotifierProvider<DomesticKeyController, (String, String)>((ref) => DomesticKeyController());

/// 条码查商品：本地历史记录优先（含完整配料与营养） → 离线高频爆款库 → 本地轻量缓存 → 离线万级品名字典 → 国内第三方免费API → Open Food Facts → 兜底
final barcodeLookupProvider = Provider<Future<ProductLookup?> Function(String)>((ref) {
  return (String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return null;

    final store = await ref.read(localStoreProvider.future);

    // 1. 本地历史记录优先（用户曾扫描拍照或手动确认过的条码商品，配料与营养最全、最准）
    final history = await ref.read(historyRepoProvider).findByBarcode(code);
    if (history != null && (history.ingredientsText?.isNotEmpty ?? false)) {
      NutritionFacts? nutrition;
      if (history.nutritionJson != null && history.nutritionJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(history.nutritionJson!);
          if (decoded is Map<String, dynamic>) {
            nutrition = NutritionFacts.fromJson(decoded);
          }
        } catch (_) {}
      }
      final lookup = ProductLookup(
        barcode: code,
        nameZh: history.productName,
        brand: history.brand,
        ingredientsText: history.ingredientsText,
        nutrition: nutrition,
        source: 'local_history',
      );
      store.putCache(lookup);
      return lookup;
    }

    // 2. 离线高频国货热门种子库（含完整配料与营养，断网秒级直出）
    final seed = await ref.read(knowledgeRepoProvider).findProductByBarcode(code);
    if (seed != null && seed.hasIngredients) {
      store.putCache(seed);
      return seed;
    }

    // 3. 本地轻量缓存（若缓存中存有完整配料表则直接命中）
    final cached = store.getCached(code);
    if (cached != null && cached.hasIngredients) {
      return cached;
    }

    // 4. 离线万级国货条码-品名字典（11000+款常见国货商品，0毫秒自动报出品名）
    final dictItem = await ref.read(knowledgeRepoProvider).findProductNameFromDict(code);
    if (dictItem != null) {
      store.putCache(dictItem);
      return dictItem;
    }

    // 5. 联网国内第三方免费条码 API（查最新冷门国货商品名）
    if (ref.read(networkLookupProvider) && ref.read(domesticLookupProvider)) {
      final keys = ref.read(domesticKeyProvider);
      final domestic = await ref.read(domesticBarcodeProvider).fetch(
        code,
        appId: keys.$1,
        appSecret: keys.$2,
      );
      if (domestic != null) {
        store.putCache(domestic);
        return domestic;
      }
    }

    // 6. 联网开放数据源（Open Food Facts，国际品牌兜底）
    if (ref.read(networkLookupProvider)) {
      final offLookup = await ref.read(offProvider).fetch(code);
      if (offLookup != null) {
        store.putCache(offLookup);
        return offLookup;
      }
    }

    // 7. 若上述均未查得完整配料，返回之前可能缓存的品名信息（供拍照识别配料表预填品名）
    if (cached != null) return cached;

    return null;
  };
});

/// 端上 OCR（拍照识别配料表），可降级为手动输入
final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService();
  ref.onDispose(service.dispose);
  return service;
});

final packProvider = FutureProvider<KnowledgePack>((ref) async {
  final repo = ref.read(knowledgeRepoProvider);
  ref.onDispose(repo.close);
  return repo.load();
});

/// 用户画像（人群 / 慢病 / 过敏原订阅）——本地持久化
class ProfileController extends StateNotifier<UserProfile> {
  ProfileController() : super(const UserProfile()) {
    _load();
  }

  static const _keyPop = 'profile_population';
  static const _keyChronics = 'profile_chronics';
  static const _keyAllergens = 'profile_allergens';

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final popCode = sp.getString(_keyPop);
      final chronicsList = sp.getStringList(_keyChronics) ?? [];
      final allergensList = sp.getStringList(_keyAllergens) ?? [];

      state = UserProfile(
        population: Population.fromCode(popCode),
        chronics: chronicsList.map(Chronic.fromCode).whereType<Chronic>().toList(),
        allergens: allergensList,
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyPop, state.population.code);
      await sp.setStringList(_keyChronics, state.chronics.map((e) => e.code).toList());
      await sp.setStringList(_keyAllergens, state.allergens);
    } catch (_) {}
  }

  void setPopulation(Population p) {
    state = state.copyWith(population: p);
    _save();
  }

  void toggleChronic(Chronic c) {
    final list = [...state.chronics];
    list.contains(c) ? list.remove(c) : list.add(c);
    state = state.copyWith(chronics: list);
    _save();
  }

  void toggleAllergen(String code) {
    final list = [...state.allergens];
    list.contains(code) ? list.remove(code) : list.add(code);
    state = state.copyWith(allergens: list);
    _save();
  }
}

final profileProvider = StateNotifierProvider<ProfileController, UserProfile>(
  (ref) => ProfileController(),
);

/// 分析结果状态
class AnalysisState {
  const AnalysisState({
    this.result,
    this.ingredientsText = '',
    this.nutrition,
    this.foodForm,
    this.categoryCode,
    this.barcode,
    this.productName,
    this.isBusy = false,
    this.error,
    this.unknownIngredients = const [],
    this.traceText,
    this.currentRecordId,
  });

  final ScoreResult? result;
  final String ingredientsText;
  final NutritionFacts? nutrition;

  /// 用户选定/推断出的食品形态（固体/液体）；与营养表是否填写无关，改类别重算时必须保留
  final FoodForm? foodForm;
  final String? categoryCode;
  final String? barcode;
  final String? productName;
  final bool isBusy;
  final String? error;

  /// 未收录（无法识别）的配料原文
  final List<String> unknownIngredients;

  /// "可能含有…"交叉污染提示语
  final String? traceText;

  /// 当前分析对应的历史记录ID（用于修改类别时原地更新，避免重复插入）
  final String? currentRecordId;

  AnalysisState copyWith({
    ScoreResult? result,
    String? ingredientsText,
    NutritionFacts? nutrition,
    FoodForm? foodForm,
    String? categoryCode,
    String? barcode,
    String? productName,
    bool? isBusy,
    String? error,
    List<String>? unknownIngredients,
    String? traceText,
    String? currentRecordId,
    bool clearResult = false,
    bool clearNutrition = false,
    bool clearFoodForm = false,
    bool clearCategoryCode = false,
    bool clearBarcode = false,
    bool clearProductName = false,
    bool clearTraceText = false,
    bool clearCurrentRecordId = false,
    bool clearUnknownIngredients = false,
  }) =>
      AnalysisState(
        result: clearResult ? null : (result ?? this.result),
        ingredientsText: ingredientsText ?? this.ingredientsText,
        nutrition: clearNutrition ? null : (nutrition ?? this.nutrition),
        foodForm: clearFoodForm ? null : (foodForm ?? this.foodForm),
        categoryCode: clearCategoryCode ? null : (categoryCode ?? this.categoryCode),
        barcode: clearBarcode ? null : (barcode ?? this.barcode),
        productName: clearProductName ? null : (productName ?? this.productName),
        isBusy: isBusy ?? this.isBusy,
        error: error,
        unknownIngredients: clearUnknownIngredients
            ? const []
            : (unknownIngredients ?? this.unknownIngredients),
        traceText: clearTraceText ? null : (traceText ?? this.traceText),
        currentRecordId:
            clearCurrentRecordId ? null : (currentRecordId ?? this.currentRecordId),
      );
}

class AnalysisController extends StateNotifier<AnalysisState> {
  AnalysisController(this.ref) : super(const AnalysisState());

  final Ref ref;

  /// 解析并评分（全本地，无任何网络调用）
  Future<ScoreResult?> analyze({
    required String ingredientsText,
    NutritionFacts? nutrition,
    String? categoryCode,
    String? barcode,
    String? productName,
    String? traceText,
    String? recordId,
    FoodForm? foodForm,
  }) async {
    final pack = await ref.read(packProvider.future);
    final profile = ref.read(profileProvider);

    // 校验类别码：防止将中文字典描述等非 GB 编码文本当作类别码使用（DATA-5）
    var validCategory =
        (categoryCode != null && RegExp(r'^\d{2}(\.\d+)?').hasMatch(categoryCode.trim()))
            ? categoryCode.trim()
            : null;
    // 补齐尾点（DATA-4: 如 '14.' 规范化为 '14.0'）
    if (validCategory != null && validCategory.endsWith('.')) {
      validCategory = '${validCategory}0';
    }

    state = state.copyWith(
      ingredientsText: ingredientsText,
      nutrition: nutrition,
      foodForm: foodForm ?? nutrition?.basis,
      categoryCode: validCategory,
      barcode: barcode,
      productName: productName,
      isBusy: true,
      error: null,
      traceText: traceText,
      currentRecordId: recordId,
      clearResult: true,
      clearNutrition: nutrition == null,
      clearFoodForm: (foodForm ?? nutrition?.basis) == null,
      clearCategoryCode: validCategory == null,
      clearBarcode: barcode == null,
      clearProductName: productName == null,
      clearTraceText: traceText == null,
      clearCurrentRecordId: recordId == null,
      clearUnknownIngredients: true,
    );

    try {
      final parsed = IngredientParser(dictionary: pack.allKnownNames.toSet()).parse(ingredientsText);
      final items = AdditiveMatcher(pack).match(parsed);
      final unknowns =
          items.where((i) => i.kind == IngredientKind.unknown).map((i) => i.rawText).toList();

      var resolvedCategory = validCategory ??
          CategoryMapper(pack)
              .map(productName: productName, ingredients: items.map((e) => e.rawText).toList())
              ?.code;
      if (resolvedCategory != null && resolvedCategory.endsWith('.')) {
        resolvedCategory = '${resolvedCategory}0';
      }

      final form = foodForm ?? nutrition?.basis ?? _guessForm(productName, resolvedCategory);

      final result = ScoringEngine(pack).evaluate(
        ScoreInput(
          ingredients: items,
          nutrition: nutrition,
          foodForm: form,
          categoryCode: resolvedCategory,
          profile: profile,
          knowledgeVersion: pack.version,
          traceText: traceText,
        ),
      );

      // 未收录配料：本地计数，供后续补库（不上传）
      final store = await ref.read(localStoreProvider.future);
      for (final i in items) {
        if (i.kind == IngredientKind.unknown) store.addUnknown(i.rawText);
      }

      // 入库或更新（若指定了既有记录ID，或条码/配料已在库中，则原地就地更新，不产生重复记录）
      final nutritionJsonStr = nutrition != null ? jsonEncode(nutrition.toJson()) : null;
      String effectiveId;
      if (recordId != null) {
        await ref.read(historyRepoProvider).updateRecordResult(
              id: recordId,
              result: result,
              barcode: barcode,
              productName: productName,
              ingredientsText: ingredientsText,
              nutritionJson: nutritionJsonStr,
            );
        effectiveId = recordId;
      } else {
        effectiveId = await ref.read(historyRepoProvider).insert(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              ingredientsText: ingredientsText,
              result: result,
              barcode: barcode,
              productName: productName,
              nutritionJson: nutritionJsonStr,
            );
      }

      // 关联条形码到轻量缓存
      if (barcode != null && barcode.isNotEmpty) {
        store.putCache(ProductLookup(
          barcode: barcode,
          nameZh: productName,
          ingredientsText: ingredientsText,
          nutrition: nutrition,
          source: 'local_history',
        ));
      }

      state = state.copyWith(
        result: result,
        isBusy: false,
        categoryCode: resolvedCategory,
        foodForm: form,
        unknownIngredients: unknowns,
        currentRecordId: effectiveId,
      );
      return result;
    } catch (e) {
      state = state.copyWith(isBusy: false, error: '分析失败：$e');
      return null;
    }
  }

  /// 修改食品类别后重算（传 recordId 原地更新既有记录，避免出现双份记录）
  Future<void> reanalyzeWithCategory(String? code, {String? recordId}) async {
    final current = state;
    if (current.ingredientsText.isEmpty) return;
    await analyze(
      ingredientsText: current.ingredientsText,
      nutrition: current.nutrition,
      categoryCode: code,
      barcode: current.barcode,
      productName: current.productName,
      traceText: current.traceText,
      recordId: recordId ?? current.currentRecordId,
      foodForm: current.foodForm ?? current.nutrition?.basis,
    );
  }

  static FoodForm _guessForm(String? productName, String? categoryCode) {
    if (categoryCode != null && (categoryCode.startsWith('14') || categoryCode.startsWith('15'))) {
      return FoodForm.liquid;
    }
    final n = productName ?? '';
    for (final k in ['饮料', '水', '茶', '果汁', '可乐', '汽水', '奶茶', '酒', '咖啡']) {
      if (n.contains(k)) return FoodForm.liquid;
    }
    return FoodForm.solid;
  }
}

final analysisProvider = StateNotifierProvider<AnalysisController, AnalysisState>(
  (ref) => AnalysisController(ref),
);
