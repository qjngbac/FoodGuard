import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/text_normalizer.dart';
import '../../data/history_repository.dart';
import '../../data/providers.dart';
import '../../data/remote/off_provider.dart';
import '../../domain/entity/nutrition_facts.dart';
import '../../domain/entity/score_result.dart';
import '../../domain/service/compliance_judge.dart';
import '../compare/compare_page.dart';
import '../input/input_page.dart';
import '../settings/settings_page.dart';
import '../widgets/share_poster_dialog.dart';

class ResultPage extends ConsumerStatefulWidget {
  const ResultPage({
    super.key,
    this.recordId,
    this.isNewlyAdded = false,
  });

  /// 传入则从历史记录重建；为空则显示最近一次分析
  final String? recordId;

  /// 是否为刚刚通过拍照或手动输入录入的新增商品
  final bool isNewlyAdded;

  @override
  ConsumerState<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends ConsumerState<ResultPage> {
  bool _loading = false;

  /// 从历史记录还原的快照（不重算，保证与当时一致）
  ScoreResult? _snapshot;
  ScanRecord? _rec;
  String? _title;

  late bool _showNewlyAddedBanner = widget.isNewlyAdded;
  List<ProductLookup> _healthyAlternatives = const [];
  bool _alternativesLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.recordId != null) _loadFromHistory(widget.recordId!);
  }

  Future<void> _loadFromHistory(String id) async {
    setState(() => _loading = true);
    final records = await ref.read(historyRepoProvider).list(limit: 1000);
    if (records.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('历史记录为空或已被清除')),
        );
        Navigator.of(context).maybePop();
      }
      return;
    }
    ScanRecord? targetRec;
    for (final r in records) {
      if (r.id == id) {
        targetRec = r;
        break;
      }
    }
    if (targetRec == null) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到该历史记录或已被删除')),
        );
        Navigator.of(context).maybePop();
      }
      return;
    }
    final rec = targetRec;
    if (mounted) {
      final res = ScoreResult.fromJson(rec.result);
      setState(() {
        _rec = rec;
        _snapshot = res;
        _title = (rec.productName?.isNotEmpty ?? false) ? rec.productName : rec.barcode;
        _loading = false;
      });
      _loadHealthyAlternatives(
        res,
        rec.barcode,
        res.compliance.categoryCode,
        brand: rec.brand,
        productName: rec.productName,
      );
    }
  }

  Future<void> _loadHealthyAlternatives(
    ScoreResult result,
    String? currentBarcode,
    String? catCode, {
    String? brand,
    String? productName,
  }) async {
    final isNeedsBetter = result.personalGrade == Grade.c ||
        result.personalGrade == Grade.d ||
        result.overallGrade == Grade.c ||
        result.overallGrade == Grade.d ||
        result.breakdown.total > 20 ||
        result.additiveItems.length >= 3 ||
        result.nova.group >= 3;
    if (!isNeedsBetter) return;

    try {
      final repo = ref.read(knowledgeRepoProvider);
      final list = await repo.findHealthyAlternatives(
        catCode,
        limit: 2,
        excludeBarcode: currentBarcode,
        brand: brand,
        productName: productName,
      );
      if (mounted && list.isNotEmpty) {
        setState(() => _healthyAlternatives = list);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analysisProvider);
    final result = _snapshot ?? state.result;

    if (_loading || result == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_alternativesLoaded && widget.recordId == null) {
      _alternativesLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadHealthyAlternatives(
            result,
            _rec?.barcode ?? state.barcode,
            state.categoryCode,
            brand: _rec?.brand,
            productName: _title ?? state.productName,
          );
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_title ?? state.productName ?? '分析结果'),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: '修改与校准商品信息',
            onPressed: () => _showEditProductDialog(state),
          ),
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: '货比三家',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ComparePage(initialRecordId: _rec?.id ?? state.currentRecordId),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: '生成评测海报',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => SharePosterDialog(
                productName: _title ?? state.productName,
                barcode: _rec?.barcode ?? state.barcode,
                result: result,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '重新输入',
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => InputPage(barcode: _rec?.barcode ?? state.barcode)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_showNewlyAddedBanner) _newlyAddedBanner(),
          _productHeaderCard(context, state),
          const SizedBox(height: 10),
          _scoreCard(context, result),
          _verdictBanner(result),
          ..._warnings(result),
          if (_healthyAlternatives.isNotEmpty) _healthyAlternativesCard(result, state),
          _ingredientsXRayCard(result, _rec?.ingredientsText ?? state.ingredientsText, state),
          _highlightsCard(result),
          if (result.populationAdvices.isNotEmpty) _populationCard(result),
          _breakdownCard(result),
          _additiveCard(context, result),
          _nutritionCard(result),
          _complianceCard(context, result, state),
          const SizedBox(height: 12),
          _unknownCard(state, result),
          _allergenCard(result),
          const SizedBox(height: 12),
          const _Disclaimer(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _newlyAddedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kRadiusM),
        border: Border.all(color: const Color(0xFF81C784), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFF2E7D32),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '已永久存入本机商品库',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC8E6C9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '离线秒出',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '该商品已在本地建立特征索引。下次在超市无需拍照，直接扫条形码即可秒出健康分析！',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2E7D32),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => setState(() => _showNewlyAddedBanner = false),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: Color(0xFF388E3C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthyAlternativesCard(ScoreResult result, AnalysisState state) {
    if (_healthyAlternatives.isEmpty) return const SizedBox.shrink();

    final isGood = (result.personalGrade == Grade.a || result.personalGrade == Grade.b) &&
        result.breakdown.total <= 15 &&
        result.additiveItems.length < 3;

    final headerTitle = isGood ? '货比三家 · 同类更天然极简好物' : '货比三家 · 同类高分健康优选推荐';
    final headerDesc = isGood
        ? '为您甄选同品类极简配料/纯天然的健康标杆，支持一键 PK 对比成分与营养差异：'
        : '当前商品添加剂或加工度偏高。我们为您甄选了同品类 0 违规/极简配料的天然替代品：';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kPrimary.withValues(alpha: 0.08),
            Colors.teal.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kRadiusM),
        border: Border.all(color: kPrimary.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.thumb_up_alt_outlined, color: kPrimary, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headerTitle,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kTextPri),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: const Text('极简配料',
                    style: TextStyle(fontSize: 10, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            headerDesc,
            style: const TextStyle(fontSize: 12, color: kTextSec, height: 1.3),
          ),
          const SizedBox(height: 10),
          ..._healthyAlternatives.map((alt) {
            final currentBrand = _rec?.brand ?? '';
            final currentName = _title ?? state.productName ?? '';
            final altBrand = alt.brand ?? '';
            final isSameBrand = altBrand.isNotEmpty &&
                ((currentBrand.isNotEmpty && currentBrand.contains(altBrand)) ||
                    currentName.contains(altBrand));

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(kRadiusS),
                border: Border.all(
                  color: isSameBrand ? Colors.amber.shade300 : Colors.black12,
                  width: isSameBrand ? 1.2 : 1,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alt.nameZh ?? '同类优质好物',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: kTextPri),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isSameBrand) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.shade400, width: 0.8),
                                ),
                                child: Text(
                                  '🌟 同品牌健康款',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                alt.novaGroup == 1 ? 'NOVA 1 天然原态' : 'NOVA 2 极简原味',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          alt.ingredientsText != null && alt.ingredientsText!.isNotEmpty
                              ? '配料：${alt.ingredientsText}'
                              : (alt.brand != null ? '品牌：${alt.brand}' : '天然少添加'),
                          style: const TextStyle(fontSize: 11, color: kTextSec),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: kPrimary.withValues(alpha: 0.12),
                      foregroundColor: kPrimary,
                    ),
                    icon: const Icon(Icons.compare_arrows, size: 15),
                    label: const Text('一键 PK',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ComparePage(
                            initialRecordId: _rec?.id ?? state.currentRecordId,
                            benchmarkLookup: alt,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _productHeaderCard(BuildContext context, AnalysisState state) {
    final name = _title ?? state.productName ?? '未命名商品';
    final barcode = _rec?.barcode ?? state.barcode;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kRadiusS),
              ),
              child: const Icon(Icons.shopping_bag_outlined, color: kPrimary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        barcode != null && barcode.isNotEmpty ? '条码：$barcode' : '未绑定条形码',
                        style: const TextStyle(fontSize: 11.5, color: kTextSec),
                      ),
                      if (barcode != null && barcode.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFA5D6A7), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF2E7D32)),
                              SizedBox(width: 2),
                              Text(
                                '已存入本机',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF2E7D32),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('修改', style: TextStyle(fontSize: 12)),
              onPressed: () => _showEditProductDialog(state, initialTab: 0),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditProductDialog(AnalysisState state, {int initialTab = 0}) async {
    final currentName = _title ?? state.productName ?? '';
    final currentBarcode = _rec?.barcode ?? state.barcode ?? '';
    final currentIngredients = _rec?.ingredientsText ?? state.ingredientsText;

    NutritionFacts? curNutrition;
    if (_rec?.nutritionJson != null && _rec!.nutritionJson!.isNotEmpty) {
      try {
        final j = jsonDecode(_rec!.nutritionJson!);
        if (j is Map<String, dynamic>) {
          curNutrition = NutritionFacts.fromJson(j);
        }
      } catch (_) {}
    }
    if (curNutrition == null && _rec == null) curNutrition = state.nutrition;

    final nameCtrl = TextEditingController(text: currentName == '未命名商品' ? '' : currentName);
    final barcodeCtrl = TextEditingController(text: currentBarcode);
    final ingredientsCtrl = TextEditingController(text: currentIngredients);

    final energyCtrl = TextEditingController(text: curNutrition?.energyKj?.toString() ?? '');
    final proteinCtrl = TextEditingController(text: curNutrition?.proteinG?.toString() ?? '');
    final fatCtrl = TextEditingController(text: curNutrition?.fatG?.toString() ?? '');
    final satFatCtrl = TextEditingController(text: curNutrition?.saturatedFatG?.toString() ?? '');
    final transFatCtrl = TextEditingController(text: curNutrition?.transFatG?.toString() ?? '');
    final carbCtrl = TextEditingController(text: curNutrition?.carbohydrateG?.toString() ?? '');
    final sugarCtrl = TextEditingController(text: curNutrition?.sugarG?.toString() ?? '');
    final fiberCtrl = TextEditingController(text: curNutrition?.dietaryFiberG?.toString() ?? '');
    final sodiumCtrl = TextEditingController(text: curNutrition?.sodiumMg?.toString() ?? '');

    try {
      bool isLiquid = curNutrition?.basis == FoodForm.liquid;
      if (curNutrition == null) {
        final code = state.categoryCode ?? '';
        if (code.startsWith('14') || code.startsWith('15')) {
          isLiquid = true;
        }
      }

      String energyUnit = 'kJ';
      String sodiumUnit = 'mg';

    Widget buildNumField(TextEditingController c, String label, String unit, {VoidCallback? onChanged}) {
      return TextField(
        controller: c,
        onChanged: (_) => onChanged?.call(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        style: const TextStyle(fontSize: 13),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusM)),
            child: DefaultTabController(
              length: 3,
              initialIndex: initialTab.clamp(0, 2),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note_rounded, color: kPrimary, size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '修正商品信息与重新打分',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(ctx, false),
                          ),
                        ],
                      ),
                    ),
                    const TabBar(
                      labelColor: kPrimary,
                      unselectedLabelColor: kTextSec,
                      indicatorColor: kPrimary,
                      tabs: [
                        Tab(text: '基础信息'),
                        Tab(text: '配料表'),
                        Tab(text: '营养成分表'),
                      ],
                    ),
                    Flexible(
                      child: SizedBox(
                        height: 380,
                        child: TabBarView(
                          children: [
                            // Tab 1: 基础信息
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: nameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: '商品名称',
                                      hintText: '例如：特仑苏纯牛奶',
                                      prefixIcon: Icon(Icons.shopping_bag_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: barcodeCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '条形码（选填）',
                                      hintText: '包装上的 13 位商品条形码',
                                      prefixIcon: Icon(Icons.qr_code),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(kRadiusS),
                                      border: Border.all(color: Colors.blue.shade200),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.info_outline, size: 18, color: Colors.blue.shade800),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '绑定条码后，商品将自动存入本机离线知识库，下次在超市对准该条形码即可秒出健康分析！',
                                            style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.4),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Tab 2: 配料表原文修正
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: ingredientsCtrl,
                                    minLines: 6,
                                    maxLines: 9,
                                    decoration: const InputDecoration(
                                      labelText: '配料表完整文本',
                                      hintText: '水、白砂糖、全脂乳粉、食用香精...',
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(kRadiusS),
                                      border: Border.all(color: Colors.amber.shade300),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade900),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '保存后系统将自动重新分词并执行端上安全规则重评，分值、扣分项与添加剂预警将实时更新。',
                                            style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900, height: 1.35),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Tab 3: 营养成分表九宫格
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('食品形态：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      SegmentedButton<FoodForm>(
                                        segments: const [
                                          ButtonSegment(
                                            value: FoodForm.solid,
                                            label: Text('固体 (每100g)', style: TextStyle(fontSize: 11)),
                                          ),
                                          ButtonSegment(
                                            value: FoodForm.liquid,
                                            label: Text('液体 (每100mL)', style: TextStyle(fontSize: 11)),
                                          ),
                                        ],
                                        selected: {isLiquid ? FoodForm.liquid : FoodForm.solid},
                                        onSelectionChanged: (set) {
                                          setDialogState(() {
                                            isLiquid = set.first == FoodForm.liquid;
                                          });
                                        },
                                        style: ButtonStyle(
                                          visualDensity: VisualDensity.compact,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Builder(
                                    builder: (context) {
                                      final energyVal = double.tryParse(energyCtrl.text.trim());
                                      final showEnergyWarning = energyUnit == 'kJ' && energyVal != null && energyVal > 0 && energyVal < 100;
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: buildNumField(energyCtrl, '能量', energyUnit, onChanged: () => setDialogState(() {}))),
                                              const SizedBox(width: 6),
                                              SegmentedButton<String>(
                                                segments: const [
                                                  ButtonSegment(value: 'kJ', label: Text('kJ', style: TextStyle(fontSize: 10))),
                                                  ButtonSegment(value: 'kcal', label: Text('kcal', style: TextStyle(fontSize: 10))),
                                                ],
                                                selected: {energyUnit},
                                                onSelectionChanged: (set) => setDialogState(() => energyUnit = set.first),
                                                style: const ButtonStyle(
                                                  visualDensity: VisualDensity.compact,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (showEnergyWarning) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.amber.shade300),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.tips_and_updates_outlined, size: 14, color: Colors.amber.shade900),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      '能量 $energyVal 偏小，包装上是否为 kcal？',
                                                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () {
                                                      setDialogState(() {
                                                        energyCtrl.text = (energyVal * 4.184).round().toString();
                                                      });
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.amber.shade200,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        '一键折算为 ${(energyVal * 4.184).round()} kJ',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.amber.shade900,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(child: buildNumField(proteinCtrl, '蛋白质', 'g')),
                                      const SizedBox(width: 8),
                                      Expanded(child: buildNumField(fatCtrl, '脂肪', 'g')),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(child: buildNumField(satFatCtrl, '饱和脂肪', 'g')),
                                      const SizedBox(width: 8),
                                      Expanded(child: buildNumField(transFatCtrl, '反式脂肪', 'g')),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(child: buildNumField(carbCtrl, '碳水化合物', 'g')),
                                      const SizedBox(width: 8),
                                      Expanded(child: buildNumField(sugarCtrl, '糖', 'g')),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Builder(
                                    builder: (context) {
                                      final sodiumVal = double.tryParse(sodiumCtrl.text.trim());
                                      final showSodiumWarning = sodiumUnit == 'mg' && sodiumVal != null && sodiumVal > 0 && sodiumVal < 1.0;
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: buildNumField(sodiumCtrl, '钠', sodiumUnit, onChanged: () => setDialogState(() {}))),
                                              const SizedBox(width: 6),
                                              SegmentedButton<String>(
                                                segments: const [
                                                  ButtonSegment(value: 'mg', label: Text('mg', style: TextStyle(fontSize: 10))),
                                                  ButtonSegment(value: 'g', label: Text('g', style: TextStyle(fontSize: 10))),
                                                ],
                                                selected: {sodiumUnit},
                                                onSelectionChanged: (set) => setDialogState(() => sodiumUnit = set.first),
                                                style: const ButtonStyle(
                                                  visualDensity: VisualDensity.compact,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (showSodiumWarning) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.amber.shade300),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.tips_and_updates_outlined, size: 14, color: Colors.amber.shade900),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      '钠 $sodiumVal 偏小，包装上是否为克(g)？',
                                                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () {
                                                      setDialogState(() {
                                                        sodiumCtrl.text = (sodiumVal * 1000).round().toString();
                                                      });
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.amber.shade200,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        '一键折算为 ${(sodiumVal * 1000).round()} mg',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.amber.shade900,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  buildNumField(fiberCtrl, '膳食纤维 (选填)', 'g'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('保存并重评'),
                            onPressed: () => Navigator.pop(ctx, true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (ok == true && mounted) {
      final newName = nameCtrl.text.trim();
      final newBarcode = barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim();
      final rawIngredients = ingredientsCtrl.text.trim();
      final cleanIngredients = TextNormalizer.cleanIngredientsText(rawIngredients);

      double? parseD(TextEditingController c) => double.tryParse(c.text.trim());
      final fatVal = parseD(fatCtrl);
      final rawSat = parseD(satFatCtrl);
      final satVal = (fatVal != null && rawSat != null && rawSat > fatVal) ? fatVal : rawSat;

      double? finalEnergy = parseD(energyCtrl);
      if (finalEnergy != null && energyUnit == 'kcal') {
        finalEnergy = (finalEnergy * 4.184).roundToDouble();
      }
      double? finalSodium = parseD(sodiumCtrl);
      if (finalSodium != null && sodiumUnit == 'g') {
        finalSodium = (finalSodium * 1000).roundToDouble();
      }

      NutritionFacts? newNutrition;
      final hasAnyNut = [
        energyCtrl,
        proteinCtrl,
        fatCtrl,
        satFatCtrl,
        transFatCtrl,
        carbCtrl,
        sugarCtrl,
        fiberCtrl,
        sodiumCtrl,
      ].any((c) => c.text.trim().isNotEmpty);

      if (hasAnyNut) {
        newNutrition = NutritionFacts(
          basis: isLiquid ? FoodForm.liquid : FoodForm.solid,
          energyKj: finalEnergy,
          proteinG: parseD(proteinCtrl),
          fatG: fatVal,
          saturatedFatG: satVal,
          transFatG: parseD(transFatCtrl),
          carbohydrateG: parseD(carbCtrl),
          sugarG: parseD(sugarCtrl),
          dietaryFiberG: parseD(fiberCtrl),
          sodiumMg: finalSodium,
        );
      }

      final activeId = _rec?.id ?? state.currentRecordId;
      final effectiveIngredients = cleanIngredients.isNotEmpty
          ? cleanIngredients
          : (_rec?.ingredientsText ?? state.ingredientsText);

      // 重新执行安全分析评分（传 activeId 在 SQLite 中就地覆盖历史记录，绝不产生重复记录）
      final newResult = await ref.read(analysisProvider.notifier).analyze(
            ingredientsText: effectiveIngredients,
            nutrition: newNutrition,
            foodForm: isLiquid ? FoodForm.liquid : FoodForm.solid,
            categoryCode: state.categoryCode,
            barcode: newBarcode,
            productName: newName.isNotEmpty ? newName : null,
            recordId: activeId,
          );

      if (newResult != null && mounted) {
        setState(() {
          _snapshot = newResult;
          _title = newName.isNotEmpty ? newName : (_title ?? '未命名商品');
          if (_rec != null) {
            _rec = ScanRecord(
              id: activeId ?? _rec!.id,
              score: newResult.score,
              grade: newResult.personalGrade.label,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              result: newResult.toJson(),
              barcode: newBarcode ?? _rec!.barcode,
              productName: newName.isNotEmpty ? newName : _rec!.productName,
              brand: _rec!.brand,
              ingredientsText: effectiveIngredients,
              nutritionJson: newNutrition != null ? jsonEncode(newNutrition.toJson()) : _rec!.nutritionJson,
              knowledgeVersion: newResult.knowledgeVersion,
            );
          }
        });

        // 同步轻量条码缓存（便于后续扫描直接命中最新数据）
        if (newBarcode != null) {
          final store = await ref.read(localStoreProvider.future);
          store.putCache(ProductLookup(
            barcode: newBarcode,
            nameZh: newName.isNotEmpty ? newName : null,
            ingredientsText: effectiveIngredients,
            nutrition: newNutrition,
            source: 'local_history',
          ));
        }

        // 重新检索同类推荐
        _loadHealthyAlternatives(
          newResult,
          newBarcode ?? _rec?.barcode,
          state.categoryCode,
          brand: _rec?.brand,
          productName: newName.isNotEmpty ? newName : _title,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已重新完成健康安全评估并同步更新')),
        );
      }
    }
  } finally {
      for (final c in [
        nameCtrl,
        barcodeCtrl,
        ingredientsCtrl,
        energyCtrl,
        proteinCtrl,
        fatCtrl,
        satFatCtrl,
        transFatCtrl,
        carbCtrl,
        sugarCtrl,
        fiberCtrl,
        sodiumCtrl,
      ]) {
        c.dispose();
      }
    }
  }

  Widget _scoreCard(BuildContext context, ScoreResult r) {
    final color = gradeColor(r.personalGrade);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 110,
                    height: 110,
                    child: CircularProgressIndicator(
                      value: r.score / 100,
                      strokeWidth: 10,
                      backgroundColor: kDivider,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${r.score}',
                          style: TextStyle(
                              fontSize: 34, fontWeight: FontWeight.bold, color: color)),
                      const Text('安全分', style: TextStyle(fontSize: 11, color: kTextSec)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(kRadiusS),
                    ),
                    child: Text(
                      '${r.personalGrade.label}  ${r.personalGrade.desc}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (r.overallGrade != r.personalGrade)
                    Text('通用评级 ${r.overallGrade.label}',
                        style: const TextStyle(fontSize: 12, color: kTextSec)),
                  const SizedBox(height: 4),
                  Text('可信度 ${_confidenceText(r.confidence)}',
                      style: const TextStyle(fontSize: 12, color: kTextSec)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _confidenceText(double c) => c >= 0.8 ? '高' : (c >= 0.6 ? '中' : '低');

  Widget _verdictBanner(ScoreResult r) {
    final grade = r.personalGrade;
    final (IconData icon, Color color, String title, String desc) = switch (grade) {
      Grade.a => (
        Icons.check_circle_rounded,
        kGradeA,
        '评级 A · 配料简单',
        '本次未检出高风险添加剂，营养指标无明显异常，可按包装建议正常食用。',
      ),
      Grade.b => (
        Icons.thumb_up_alt_rounded,
        kGradeB,
        '评级 B · 可正常食用',
        '检出少量低风险添加剂，均在常见使用范围内，营养指标无明显异常。',
      ),
      Grade.bMinus => (
        Icons.info_rounded,
        kGradeBMinus,
        '中规中矩 · 适量食用',
        '含有常规食品添加剂或中度加工成分，建议日常适度控制食用频次与份量。',
      ),
      Grade.c => (
        Icons.warning_amber_rounded,
        kGradeC,
        '谨慎尝鲜 · 控制频次',
        '检出需关注添加剂或高钠/高糖/高脂指标，不建议高频或大量食用。',
      ),
      Grade.d => (
        Icons.dangerous_rounded,
        kGradeD,
        '尽量少吃 · 注意健康风险',
        '含国家禁用、限制使用或较高风险成分，可能加重代谢负担，建议尽量减少购买食用。',
      ),
      Grade.unknown => (
        Icons.help_rounded,
        const Color(0xFF9E9E9E),
        '尚未评分 · 缺少配料表',
        '这条记录没有可解析的配料表原文，请拍照或手动录入配料后再看评级。',
      ),
    };

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusM),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('健康决策',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  desc,
                  style: const TextStyle(fontSize: 12.5, height: 1.45, color: kTextPri),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ingredientsXRayCard(ScoreResult r, String? rawText, AnalysisState state) {
    if (rawText == null || rawText.trim().isEmpty) return const SizedBox.shrink();

    final spans = _buildXRaySpans(rawText.trim(), r, state);

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.saved_search_rounded, size: 20, color: kPrimary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '配料表原文透视',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kDivider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('成分高亮', style: TextStyle(fontSize: 10, color: kTextSec)),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    _showEditProductDialog(state, initialTab: 1);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: kPrimary.withValues(alpha: 0.35), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, size: 11, color: kPrimary),
                        SizedBox(width: 2),
                        Text('修正配料', style: TextStyle(fontSize: 10, color: kPrimary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _xRayLegendItem('🔴 需关注(3-5级)', kDangerBg, kGradeD),
                _xRayLegendItem('🟢 常规低风险(1-2级)', kGradeA.withValues(alpha: 0.15), kGradeA),
                _xRayLegendItem('⚠️ 过敏原', Colors.purple.withValues(alpha: 0.12), Colors.purple),
                if (_unknownWords(state, r).isNotEmpty)
                  _xRayLegendItem('🔍 点击错字一键修正', Colors.amber.shade100, Colors.amber.shade900),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(kRadiusS),
                border: Border.all(color: kDivider),
              ),
              child: SelectableText.rich(
                TextSpan(
                  children: spans,
                  style: const TextStyle(fontSize: 13, height: 1.6, color: kTextPri),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _xRayLegendItem(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w500)),
    );
  }

  List<InlineSpan> _buildXRaySpans(String text, ScoreResult r, AnalysisState state) {
    final targets = <_XRayTarget>[];
    for (final add in r.additiveItems) {
      if (add.displayName.isNotEmpty && add.displayName.length >= 2) {
        targets.add(_XRayTarget(
          word: add.displayName,
          bg: add.riskLevel >= 4
              ? kDangerBg
              : (add.riskLevel >= 3 ? kWarnBg : kGradeA.withValues(alpha: 0.15)),
          fg: add.riskLevel >= 4
              ? kGradeD
              : (add.riskLevel >= 3 ? kGradeC : kGradeA),
          isBold: add.riskLevel >= 3,
        ));
      }
      if (add.name.isNotEmpty && add.name != add.displayName && add.name.length >= 2) {
        targets.add(_XRayTarget(
          word: add.name,
          bg: add.riskLevel >= 4
              ? kDangerBg
              : (add.riskLevel >= 3 ? kWarnBg : kGradeA.withValues(alpha: 0.15)),
          fg: add.riskLevel >= 4
              ? kGradeD
              : (add.riskLevel >= 3 ? kGradeC : kGradeA),
          isBold: add.riskLevel >= 3,
        ));
      }
    }
    for (final all in r.allergenHits) {
      if (all.isTrace) continue;
      final highlightWord = all.matchedWord.isNotEmpty
          ? all.matchedWord
          : (all.matchedText.contains('（含 ')
              ? all.matchedText.split('（含 ').first.trim()
              : all.matchedText);
      if (highlightWord.isNotEmpty && highlightWord.length >= 2) {
        targets.add(_XRayTarget(
          word: highlightWord,
          bg: Colors.purple.withValues(alpha: 0.12),
          fg: Colors.purple,
          isBold: true,
        ));
      }
    }

    // 将未收录配料加入透视高亮，并赋予点击一键修正能力
    for (final unk in _unknownWords(state, r)) {
      final w = unk.trim();
      if (w.isNotEmpty && w.length >= 2) {
        targets.add(_XRayTarget(
          word: w,
          bg: Colors.amber.shade100,
          fg: Colors.amber.shade900,
          isBold: true,
          isUnknown: true,
        ));
      }
    }

    targets.sort((a, b) => b.word.length.compareTo(a.word.length));

    final occurrences = <_XRayOccurrence>[];
    for (final target in targets) {
      var startIndex = 0;
      while (startIndex < text.length) {
        final index = text.indexOf(target.word, startIndex);
        if (index == -1) break;
        final endIndex = index + target.word.length;
        final overlaps = occurrences.any((o) => !(endIndex <= o.start || index >= o.end));
        if (!overlaps) {
          occurrences.add(_XRayOccurrence(
            start: index,
            end: endIndex,
            target: target,
          ));
        }
        startIndex = index + 1;
      }
    }

    occurrences.sort((a, b) => a.start.compareTo(b.start));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final occ in occurrences) {
      if (occ.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, occ.start)));
      }
      final matchedText = text.substring(occ.start, occ.end);
      if (occ.target.isUnknown) {
        // 未收录词：支持点击一键替换纠错
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () => _showQuickFixWordDialog(matchedText, state),
            borderRadius: BorderRadius.circular(3),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: occ.target.bg,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: occ.target.fg.withValues(alpha: 0.6), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_fix_high_rounded, size: 10, color: occ.target.fg),
                  const SizedBox(width: 2),
                  Text(
                    matchedText,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: occ.target.fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
      } else {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: occ.target.bg,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              matchedText,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: occ.target.isBold ? FontWeight.bold : FontWeight.w500,
                color: occ.target.fg,
              ),
            ),
          ),
        ));
      }
      cursor = occ.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return spans;
  }

  List<Widget> _warnings(ScoreResult r) {
    final out = <Widget>[];
    final subscribed =
        r.allergenHits.where((a) => a.isSubscribed).toList();
    if (subscribed.isNotEmpty) {
      out.add(_warnBanner(
        '⚠ 含你关注的过敏原：${subscribed.map((e) => e.nameZh).join('、')}',
        kDangerBg,
        kGradeD,
      ));
    }
    final risk5 = r.additiveItems.where((e) => e.riskLevel == 5).toList();
    if (risk5.isNotEmpty) {
      out.add(_warnBanner(
        '⚠ 检出国家禁止使用（或 GB 2760-2024 已删除）的物质：${risk5.map((e) => e.name).join('、')}',
        kDangerBg,
        kGradeD,
      ));
    }
    final prohibited = r.compliance.items
        .where((e) => e.status == UsageStatus.prohibited)
        .toList();
    if (prohibited.isNotEmpty) {
      out.add(_warnBanner(
        '⚠ ${prohibited.map((e) => e.additiveName).join('、')} 在 GB 2760 中不得用于该食品类别，疑似超范围使用',
        kWarnBg,
        kGradeC,
      ));
    }
    return out;
  }

  Widget _warnBanner(String text, Color bg, Color fg) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kRadiusS),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 13)),
    );
  }

  Widget _highlightsCard(ScoreResult r) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: r.highlights
              .map((h) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.circle, size: 6, color: kPrimary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(h, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _populationCard(ScoreResult r) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('人群提示', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...r.populationAdvices.take(6).map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: a.severity == 'AVOID'
                              ? kDangerBg
                              : (a.severity == 'LIMIT' ? kWarnBg : kDivider),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          a.severity == 'AVOID'
                              ? '避免'
                              : (a.severity == 'LIMIT' ? '限量' : '注意'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${a.targetName}：${a.reasonZh}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
              child: const Text('调整人群/过敏原设置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakdownCard(ScoreResult r) {
    Widget bar(String label, double value, double max, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (value / max).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: kDivider,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: Text(
                value >= 0 ? '-${value.toStringAsFixed(1)}' : '+${(-value).toStringAsFixed(1)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('扣分构成', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            bar('添加剂风险', r.breakdown.additive, 70, kGradeC),
            if (r.breakdown.additiveShared > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  '其中 ${r.breakdown.additiveShared.toStringAsFixed(1)} 分来自数量放大、同类叠加'
                  '或配料表只标注功能类别名，无法摊到具体物质上。',
                  style: TextStyle(fontSize: 11.5, color: kTextSec, height: 1.4),
                ),
              ),
            bar('营养', r.breakdown.nutrition, 30, kGradeBMinus),
            bar('加工度 NOVA${r.nova.group}', r.breakdown.processing, 15, kPrimary),
            if (r.breakdown.ruleAdjust > 0)
              bar('一票否决修正', r.breakdown.ruleAdjust, 70, kGradeD),
            const Divider(height: 20),
            Text('合计扣分 ${r.breakdown.total.toStringAsFixed(1)} → 100 - '
                '${r.breakdown.total.toStringAsFixed(1).replaceAll(_trailingZero, '')}'
                ' = ${r.score}'),
          ],
        ),
      ),
    );
  }

  static final RegExp _trailingZero = RegExp(r'\.0$');

  Widget _additiveCard(BuildContext context, ScoreResult r) {
    final items = r.additiveItems;
    final attentionItems = items.where((e) => e.riskLevel >= 3).toList();
    final normalItems = items.where((e) => e.riskLevel < 3).toList();

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('食品添加剂（共 ${items.length} 种）',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                if (attentionItems.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kDangerBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('需关注 ${attentionItems.length}',
                        style: const TextStyle(
                            fontSize: 11, color: kGradeD, fontWeight: FontWeight.bold)),
                  ),
                if (normalItems.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kGradeA.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('常规低风险 ${normalItems.length}',
                        style: const TextStyle(
                            fontSize: 11, color: kGradeA, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: const [
                    Icon(Icons.check_circle, size: 18, color: kGradeA),
                    SizedBox(width: 8),
                    Text('未检出食品添加剂，配料纯净',
                        style: TextStyle(fontSize: 13, color: kTextSec)),
                  ],
                ),
              )
            else ...[
              if (attentionItems.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: kGradeC),
                    const SizedBox(width: 4),
                    Text('需关注添加剂（${attentionItems.length} 种）',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold, color: kGradeC)),
                  ],
                ),
                const SizedBox(height: 4),
                ...attentionItems.map((e) => _buildAdditiveTile(context, e)),
              ],
              if (normalItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: kPrimary),
                    const SizedBox(width: 4),
                    Text('常规低风险添加剂（${normalItems.length} 种）',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: kTextPri)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: normalItems.map((e) => ActionChip(
                    avatar: CircleAvatar(
                      radius: 9,
                      backgroundColor: _riskColor(e.riskLevel),
                      child: Text('${e.riskLevel}',
                          style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                    label: Text(e.displayName, style: const TextStyle(fontSize: 12)),
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    side: const BorderSide(color: kDivider),
                    onPressed: () => _showAdditiveDetail(context, e),
                  )).toList(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdditiveTile(BuildContext context, AdditiveScoreItem e) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: _riskColor(e.riskLevel),
        child: Text('${e.riskLevel}',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
      title: Text(e.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(
        '${e.functionClass ?? '—'} · 扣 ${e.penalty.toStringAsFixed(1)} 分'
        '${e.riskReasonZh != null ? '\n${e.riskReasonZh}' : ''}',
        style: const TextStyle(fontSize: 11.5, color: kTextSec, height: 1.3),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _showAdditiveDetail(context, e),
    );
  }


  void _showAdditiveDetail(BuildContext context, AdditiveScoreItem e) {
    showModalBottomSheet(
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
                CircleAvatar(
                  backgroundColor: _riskColor(e.riskLevel),
                  child: Text('${e.riskLevel}',
                      style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      Text('${e.functionClass ?? '—'} · 风险${e.riskLevelText}',
                          style: const TextStyle(fontSize: 12, color: kTextSec)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (e.insCode != null) _kv('INS 号', e.insCode!),
            if (e.euCode != null) _kv('E 号', e.euCode!),
            _kv('位置', '第 ${e.order} 位${e.depth > 0 ? '（来自复合配料）' : ''}'),
            _kv('ADI', e.adiText ?? '未收录'),
            if (e.iarcText != null) _kv('致癌性分类', e.iarcText!),
            if (e.riskReasonZh != null) _kv('风险说明', e.riskReasonZh!),
            if (e.populationFlags.isNotEmpty)
              _kv('需关注人群', e.populationFlags.join('、')),
            if (e.compliance != null)
              _kv('使用规定',
                  ComplianceJudge.statusText(e.compliance!, r0CategoryName(context))),
            const SizedBox(height: 16),
            const Text(
              '本页内容整理自公开标准与权威评估，可能存在滞后或整理偏差。'
              'ADI 是"终身每日摄入而无可察觉健康风险的量"，单次超过并不等于有害。',
              style: TextStyle(fontSize: 11, color: kTextSec),
            ),
          ],
        ),
      ),
    );
  }

  String? r0CategoryName(BuildContext context) {
    if (_snapshot != null || _rec != null) return _snapshot?.compliance.categoryName;
    final state = ref.read(analysisProvider);
    return _snapshot?.compliance.categoryName ?? state.result?.compliance.categoryName;
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 84,
              child: Text(k, style: const TextStyle(fontSize: 12, color: kTextSec))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _nutritionCard(ScoreResult r) {
    final eval = r.nutritionEval;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.restaurant_menu, size: 18, color: kPrimary),
                const SizedBox(width: 6),
                const Text('营养成分与生活化等效',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                InkWell(
                  onTap: () {
                    final state = ref.read(analysisProvider);
                    _showEditProductDialog(state, initialTab: 2);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: kPrimary.withValues(alpha: 0.35), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_outlined, size: 11, color: kPrimary),
                        const SizedBox(width: 2),
                        Text(
                          eval == null || eval.items.isEmpty ? '补充营养表' : '修正营养表',
                          style: const TextStyle(fontSize: 10, color: kPrimary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (eval == null || eval.items.isEmpty)
              const Text('未提供营养成分表，营养维度未计入',
                  style: TextStyle(fontSize: 13, color: kTextSec))
            else ...[
              _buildNutritionEquivalence(eval),
              const SizedBox(height: 12),
              _buildTrafficLightBadges(eval),
              const SizedBox(height: 12),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                },
                children: [
                  const TableRow(children: [
                    Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text('项目', style: TextStyle(fontSize: 12, color: kTextSec))),
                    Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text('含量', style: TextStyle(fontSize: 12, color: kTextSec))),
                    Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text('NRV%', style: TextStyle(fontSize: 12, color: kTextSec))),
                  ]),
                  ...eval.items.map((i) => TableRow(children: [
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(i.nameZh, style: const TextStyle(fontSize: 12))),
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                                '${i.value?.toStringAsFixed(1) ?? '—'} ${i.unit}',
                                style: const TextStyle(fontSize: 12))),
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                                i.nrvPercent == null
                                    ? '—'
                                    : '${i.nrvPercent!.round()}%',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: (i.nrvPercent ?? 0) >= 30
                                        ? kGradeC
                                        : kTextPri))),
                      ])),
                ],
              ),
              if (eval.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: eval.tags
                      .map((t) => Chip(
                            label: Text(t, style: const TextStyle(fontSize: 11)),
                            backgroundColor: kDivider,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionEquivalence(NutritionEvaluation eval) {
    NutritionItemEval? find(String code) {
      for (final item in eval.items) {
        if (item.code == code) return item;
      }
      return null;
    }

    final energy = find('ENERGY')?.value;
    final sodium = find('SODIUM')?.value;
    final sugar = find('SUGAR')?.value ??
        (find('CHO')?.value != null ? find('CHO')!.value! * 0.6 : null);

    // 慢跑消耗：慢跑10分钟约消耗 300 kJ (30 kJ/min)
    final jogMinutes = energy != null ? (energy / 30.0).round() : null;
    // 每日钠限：成人推荐钠摄入上限约 2000mg
    final sodiumPercent =
        sodium != null ? (sodium / 2000.0 * 100).round() : null;
    // 方糖等效：1块标准方糖约 4.5g
    final sugarCubes = sugar != null ? (sugar / 4.5) : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(kRadiusS),
        border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _equivItem('🏃 慢跑消耗', jogMinutes != null ? '$jogMinutes 分钟' : '—', '每100g/ml热量'),
          Container(width: 1, height: 36, color: kDivider),
          _equivItem('🧂 占全天限钠', sodiumPercent != null ? '$sodiumPercent%' : '—', '按2000mg上限计'),
          Container(width: 1, height: 36, color: kDivider),
          _equivItem('🍬 等效方糖', sugarCubes != null ? '≈${sugarCubes.toStringAsFixed(1)}块' : '—', '以4.5g/块换算'),
        ],
      ),
    );
  }

  Widget _equivItem(String title, String value, String hint) {
    return Expanded(
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: kTextSec)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: kPrimary)),
          const SizedBox(height: 2),
          Text(hint,
              style: const TextStyle(fontSize: 9, color: kTextSec),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildTrafficLightBadges(NutritionEvaluation eval) {
    NutritionItemEval? find(String code) {
      for (final item in eval.items) {
        if (item.code == code) return item;
      }
      return null;
    }

    final badges = <Widget>[];

    final sodium = find('SODIUM')?.value;
    if (sodium != null) {
      if (sodium >= 600) {
        badges.add(_trafficBadge('🔴 高钠食品', kDangerBg, kGradeD));
      } else if (sodium <= 120) {
        badges.add(_trafficBadge('🟢 低钠清淡', kGradeA.withValues(alpha: 0.15), kGradeA));
      }
    }

    final fat = find('FAT')?.value;
    if (fat != null) {
      if (fat >= 20) {
        badges.add(_trafficBadge('🔴 高脂', kDangerBg, kGradeD));
      } else if (fat <= 3) {
        badges.add(_trafficBadge('🟢 低脂轻负担', kGradeA.withValues(alpha: 0.15), kGradeA));
      }
    }

    final sugar = find('SUGAR')?.value;
    if (sugar != null) {
      if (sugar >= 10) {
        badges.add(_trafficBadge('🔴 高糖预警', kDangerBg, kGradeD));
      } else if (sugar <= 0.5) {
        badges.add(_trafficBadge('🟢 0糖无负担', kGradeA.withValues(alpha: 0.15), kGradeA));
      }
    }

    final energy = find('ENERGY')?.value;
    if (energy != null) {
      if (energy >= 1700) {
        badges.add(_trafficBadge('🟠 高能量', kWarnBg, kGradeC));
      } else if (energy <= 600) {
        badges.add(_trafficBadge('🟢 低卡轻食', kGradeA.withValues(alpha: 0.15), kGradeA));
      }
    }

    final protein = find('PROTEIN')?.value;
    if (protein != null && protein >= 10) {
      badges.add(_trafficBadge('🟢 高蛋白质', kGradeA.withValues(alpha: 0.15), kGradeA));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: badges,
    );
  }

  Widget _trafficBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }


  Widget _complianceCard(
      BuildContext context, ScoreResult r, AnalysisState state) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('合规判定（GB 2760）',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => _pickCategory(context),
                  child: const Text('改类别'),
                ),
              ],
            ),
            Text(
              r.compliance.categoryName == null
                  ? '食品类别：无法判定'
                  : '食品类别：${r.compliance.categoryName}',
              style: const TextStyle(fontSize: 12, color: kTextSec),
            ),
            const SizedBox(height: 8),
            if (r.compliance.items.isEmpty)
              const Text('未检出食品添加剂，无需判定',
                  style: TextStyle(fontSize: 12, color: kTextSec))
            else if (r.compliance.categoryCode == null)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kDivider.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(kRadiusS),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, size: 16, color: kTextSec),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '未获取到食品类别，暂无法按国标逐项判定使用范围。您可以点击右上角「改类别」指定食品分类。',
                        style: TextStyle(fontSize: 12, color: kTextSec, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...r.compliance.items.take(10).map((i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          i.status == UsageStatus.allowed
                              ? Icons.check_circle_outline
                              : (i.status == UsageStatus.prohibited
                                  ? Icons.cancel_outlined
                                  : Icons.help_outline),
                          size: 16,
                          color: i.status == UsageStatus.allowed
                              ? kPrimary
                              : (i.status == UsageStatus.prohibited
                                  ? kGradeD
                                  : kTextSec),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            ComplianceJudge.statusText(
                                i, r.compliance.categoryName),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 8),
            const Text(
              '本模块只判定"该添加剂是否允许用于该食品类别"，'
              '不对实际添加量是否超标作出判定。',
              style: TextStyle(fontSize: 11, color: kTextSec),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCategory(BuildContext context) async {
    final pack = await ref.read(packProvider.future);
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(
        children: [
          ListTile(
            title: const Text('自动推断'),
            onTap: () => Navigator.pop(context, '__auto__'),
          ),
          ...pack.categories.map(
            (c) => ListTile(
              title: Text(c.nameZh),
              onTap: () => Navigator.pop(context, c.code),
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    final catCode = picked == '__auto__' ? null : picked;
    final activeId = _rec?.id ?? ref.read(analysisProvider).currentRecordId;

    if (_snapshot != null && _rec?.ingredientsText != null && _rec!.ingredientsText!.isNotEmpty) {
      NutritionFacts? nutrition;
      if (_rec?.nutritionJson != null && _rec!.nutritionJson!.isNotEmpty) {
        try {
          final j = jsonDecode(_rec!.nutritionJson!);
          if (j is Map<String, dynamic>) {
            nutrition = NutritionFacts.fromJson(j);
          }
        } catch (_) {}
      }
      final newResult = await ref.read(analysisProvider.notifier).analyze(
        ingredientsText: _rec!.ingredientsText!,
        nutrition: nutrition,
        categoryCode: catCode,
        barcode: _rec!.barcode,
        productName: _rec!.productName,
        recordId: activeId,
      );
      if (mounted && newResult != null) {
        setState(() {
          _snapshot = newResult;
          if (_rec != null) {
            _rec = ScanRecord(
              id: _rec!.id,
              score: newResult.score,
              grade: newResult.personalGrade.label,
              createdAt: _rec!.createdAt,
              result: newResult.toJson(),
              barcode: _rec!.barcode,
              productName: _rec!.productName,
              brand: _rec!.brand,
              ingredientsText: _rec!.ingredientsText,
              nutritionJson: _rec!.nutritionJson,
              knowledgeVersion: newResult.knowledgeVersion,
            );
          }
        });
      }
    } else if (_snapshot != null) {
      if (!mounted) return;
      const hint = SnackBar(content: Text('该历史记录没有配料表原文，请重新录入配料后再修改类别'));
      ScaffoldMessenger.of(this.context).showSnackBar(hint);
    } else {
      await ref.read(analysisProvider.notifier).reanalyzeWithCategory(catCode, recordId: activeId);
    }
  }

  /// 未收录配料词一键修正对话框
  Future<void> _showQuickFixWordDialog(String word, AnalysisState state) async {
    final cleanWord = word.trim();
    if (cleanWord.isEmpty) return;

    final pack = await ref.read(packProvider.future);
    if (!mounted) return;
    final candidates = TextNormalizer.findCorrectionCandidates(
      cleanWord,
      dictionary: pack.allKnownNames,
      limit: 6,
    );

    final editCtrl = TextEditingController(
      text: candidates.isNotEmpty ? candidates.first : cleanWord,
    );

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusM)),
            title: Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded, color: kPrimary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '修正配料「$cleanWord」',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '若因反光或微小字号导致识别出错，可一键替换为推荐候选词，或直接手动输入：',
                  style: TextStyle(fontSize: 12, color: kTextSec, height: 1.4),
                ),
                if (candidates.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '💡 推荐修正候选词：',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextPri),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: candidates.map((cand) {
                      final isCurrent = editCtrl.text.trim() == cand;
                      return ChoiceChip(
                        label: Text(cand, style: TextStyle(fontSize: 12, color: isCurrent ? Colors.white : kTextPri)),
                        selected: isCurrent,
                        selectedColor: kPrimary,
                        visualDensity: VisualDensity.compact,
                        onSelected: (sel) {
                          if (sel) {
                            setDialogState(() {
                              editCtrl.text = cand;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: editCtrl,
                  decoration: const InputDecoration(
                    labelText: '替换为规范配料名称',
                    hintText: '输入规范配料名称',
                    prefixIcon: Icon(Icons.edit_outlined, size: 18),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('一键替换并重评'),
                onPressed: () {
                  final repl = editCtrl.text.trim();
                  if (repl.isEmpty) return;
                  Navigator.pop(ctx, repl);
                },
              ),
            ],
          );
        },
      ),
    );
    editCtrl.dispose();

    if (selected != null && selected.isNotEmpty && selected != cleanWord && mounted) {
      final currentIngredients = _rec?.ingredientsText ?? state.ingredientsText;
      if (currentIngredients.isEmpty) return;

      final updatedIngredients = currentIngredients.replaceAll(cleanWord, selected);
      final activeId = _rec?.id ?? state.currentRecordId;

      NutritionFacts? curNutrition = state.nutrition;
      if (curNutrition == null && _rec?.nutritionJson != null && _rec!.nutritionJson!.isNotEmpty) {
        try {
          final j = jsonDecode(_rec!.nutritionJson!);
          if (j is Map<String, dynamic>) {
            curNutrition = NutritionFacts.fromJson(j);
          }
        } catch (_) {}
      }

      final newResult = await ref.read(analysisProvider.notifier).analyze(
            ingredientsText: updatedIngredients,
            nutrition: curNutrition,
            foodForm: curNutrition?.basis ?? state.foodForm,
            categoryCode: state.categoryCode,
            barcode: _rec?.barcode ?? state.barcode,
            productName: _title ?? state.productName,
            recordId: activeId,
          );

      if (newResult != null && mounted) {
        setState(() {
          _snapshot = newResult;
          if (_rec != null) {
            _rec = ScanRecord(
              id: activeId ?? _rec!.id,
              score: newResult.score,
              grade: newResult.personalGrade.label,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              result: newResult.toJson(),
              barcode: _rec!.barcode,
              productName: _rec!.productName,
              brand: _rec!.brand,
              ingredientsText: updatedIngredients,
              nutritionJson: _rec!.nutritionJson,
              knowledgeVersion: newResult.knowledgeVersion,
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已将「$cleanWord」修正为「$selected」并重新计算安全分！'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 未收录词的唯一来源：历史模式下只看快照，避免把上一个商品的未收录词串进当前页面
  List<String> _unknownWords(AnalysisState state, ScoreResult r) {
    if (_rec != null || _snapshot != null) return r.unknownIngredients;
    return r.unknownIngredients.isNotEmpty ? r.unknownIngredients : state.unknownIngredients;
  }

  /// 未收录配料提示（不扣分，仅提示与补库，支持点击一键修正）
  Widget _unknownCard(AnalysisState state, ScoreResult r) {
    final unknowns = _unknownWords(state, r);
    if (unknowns.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('未收录配料（${unknowns.length}）',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('点击即可一键纠错',
                    style: TextStyle(fontSize: 11, color: kPrimary.withValues(alpha: 0.9))),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: unknowns
                  .take(12)
                  .map((t) => ActionChip(
                        avatar: const Icon(Icons.auto_fix_high_rounded, size: 12, color: kPrimary),
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        backgroundColor: kDivider.withValues(alpha: 0.6),
                        visualDensity: VisualDensity.compact,
                        tooltip: '点击一键修正配料词',
                        onPressed: () => _showQuickFixWordDialog(t, state),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              '这些配料不在当前知识库中，未参与扣分，但会降低结果可信度。点击词条可直接修正错字。'
              '（知识库 v${r.knowledgeVersion}）',
              style: const TextStyle(fontSize: 11, color: kTextSec),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allergenCard(ScoreResult r) {
    if (r.allergenHits.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('过敏原信息', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...r.allergenHits.map((h) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${h.isTrace ? '可能含有' : '含'} ${h.nameZh}（${h.matchedText}）'
                    '${h.isSubscribed ? '  ⚠你已关注' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: h.isSubscribed ? kGradeD : kTextPri,
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Color _riskColor(int level) => switch (level) {
        1 => kGradeA,
        2 => kGradeB,
        3 => kGradeBMinus,
        4 => kGradeC,
        _ => kGradeD,
      };
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '本结果由本 App 依据公开标准（GB 2760 等）与权威评估（JECFA / IARC / EFSA）'
      '在手机本地计算得出，仅供选购参考，不构成医疗建议，也不能替代实验室检测。\n'
      '本 App 不对实际添加量是否超标作出判定——这需要专业机构检测。'
      '合规不等于健康，不合规也不等于一定有害。',
      style: TextStyle(fontSize: 11, color: kTextSec),
    );
  }
}

class _XRayTarget {
  const _XRayTarget({
    required this.word,
    required this.bg,
    required this.fg,
    required this.isBold,
    this.isUnknown = false,
  });

  final String word;
  final Color bg;
  final Color fg;
  final bool isBold;
  final bool isUnknown;
}

class _XRayOccurrence {
  const _XRayOccurrence({
    required this.start,
    required this.end,
    required this.target,
  });

  final int start;
  final int end;
  final _XRayTarget target;
}


