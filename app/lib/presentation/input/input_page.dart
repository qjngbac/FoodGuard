import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/text_normalizer.dart';
import '../../data/providers.dart';
import '../../domain/entity/additive.dart';
import '../../domain/entity/nutrition_facts.dart';
import '../result/result_page.dart';

/// 预填数据：来自条码联网查询、OCR 或上一次输入
class InputPrefill {
  const InputPrefill({
    this.barcode,
    this.productName,
    this.brand,
    this.ingredients,
    this.nutrition,
    this.traceText,
    this.inputSource,
  });

  final String? barcode;
  final String? productName;
  final String? brand;
  final String? ingredients;
  final NutritionFacts? nutrition;
  final String? traceText;
  final String? inputSource;
}

class InputPage extends ConsumerStatefulWidget {
  const InputPage({super.key, this.barcode, this.prefill});

  final String? barcode;
  final InputPrefill? prefill;

  @override
  ConsumerState<InputPage> createState() => _InputPageState();
}

class _InputPageState extends ConsumerState<InputPage> {
  final _ingredients = TextEditingController();
  final _name = TextEditingController();
  final _barcode = TextEditingController();

  final _energy = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();
  final _sat = TextEditingController();
  final _trans = TextEditingController();
  final _carb = TextEditingController();
  final _sugar = TextEditingController();
  final _fiber = TextEditingController();
  final _sodium = TextEditingController();

  String _energyUnit = 'kJ';
  String _sodiumUnit = 'mg';

  bool _liquid = false;
  bool _nutritionExpanded = false;
  String? _categoryCode;

  static const _sample =
      '小麦粉、植物油、白砂糖、食用盐、碳酸氢钠、焦亚硫酸钠、食用香精、特丁基对苯二酚';

  String? _traceText;

  @override
  void initState() {
    super.initState();
    _energy.addListener(_onNutritionChanged);
    _sodium.addListener(_onNutritionChanged);
    if (widget.barcode != null) _barcode.text = widget.barcode!;
    final p = widget.prefill;
    if (p != null) {
      if (p.barcode != null) _barcode.text = p.barcode!;
      if (p.productName != null) _name.text = p.productName!;
      if (p.ingredients != null) _ingredients.text = p.ingredients!;
      _traceText = p.traceText;
      final n = p.nutrition;
      if (n != null) {
        _liquid = n.basis == FoodForm.liquid;
        _nutritionExpanded = true;
        _energy.text = n.energyKj?.toStringAsFixed(0) ?? '';
        _protein.text = n.proteinG?.toStringAsFixed(1) ?? '';
        _fat.text = n.fatG?.toStringAsFixed(1) ?? '';
        _sat.text = n.saturatedFatG?.toStringAsFixed(1) ?? '';
        _trans.text = n.transFatG?.toStringAsFixed(1) ?? '';
        _carb.text = n.carbohydrateG?.toStringAsFixed(1) ?? '';
        _sugar.text = n.sugarG?.toStringAsFixed(1) ?? '';
        _fiber.text = n.dietaryFiberG?.toStringAsFixed(1) ?? '';
        _sodium.text = n.sodiumMg?.toStringAsFixed(0) ?? '';
      }
    }
  }

  void _onNutritionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _ingredients, _name, _barcode, _energy, _protein, _fat, _sat,
      _trans, _carb, _sugar, _fiber, _sodium,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analysisProvider);
    final packAsync = ref.watch(packProvider);
    final categories = packAsync.value?.categories ?? const <FoodCategory>[];

    return Scaffold(
      appBar: AppBar(title: const Text('输入配料表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '商品名称（选填）',
              prefixIcon: Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _barcode,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '条形码（选填）',
              prefixIcon: Icon(Icons.qr_code),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ingredients,
            minLines: 5,
            maxLines: 12,
            decoration: InputDecoration(
              alignLabelWithHint: true,
              labelText: '配料表（必填）',
              hintText: '例如：小麦粉、水、白砂糖、食用盐、碳酸氢钠',
              suffixIcon: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: '填入示例',
                    icon: const Icon(Icons.auto_awesome_outlined),
                    onPressed: () => setState(() => _ingredients.text = _sample),
                  ),
                  IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _ingredients.clear()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ExpansionTile(
              title: const Text('营养成分表（选填，每 100 g / 100 mL）'),
              initiallyExpanded: _nutritionExpanded,
              onExpansionChanged: (v) => setState(() => _nutritionExpanded = v),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('按液体计算（每 100 mL）'),
                        value: _liquid,
                        onChanged: (v) => setState(() => _liquid = v),
                      ),
                      _energyField(),
                      _num(_protein, '蛋白质 (g)'),
                      _num(_fat, '脂肪 (g)'),
                      _num(_carb, '碳水化合物 (g)'),
                      _sodiumField(),
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('更多选填项（包装若未标可不填）',
                              style: TextStyle(fontSize: 13, color: kTextSec)),
                          children: [
                            _num(_sat, '饱和脂肪 (g)'),
                            _num(_trans, '反式脂肪 (g)'),
                            _num(_sugar, '糖 (g)'),
                            _num(_fiber, '膳食纤维 (g)'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (categories.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: DropdownButtonFormField<String>(
                  initialValue: _categoryCode,
                  decoration: const InputDecoration(
                    labelText: '食品类别（选填，用于 GB2760 合规判定）',
                    border: InputBorder.none,
                  ),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('自动推断')),
                    ...categories.map(
                      (c) => DropdownMenuItem<String>(
                        value: c.code,
                        child: Text(c.nameZh),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _categoryCode = v),
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: state.isBusy ? null : _submit,
            icon: state.isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.analytics_outlined),
            label: Text(state.isBusy ? '分析中…' : '开始分析'),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(state.error!, style: const TextStyle(color: kGradeD)),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _energyField() {
    final val = double.tryParse(_energy.text.trim());
    final isAnomaly = _energyUnit == 'kJ' && val != null && val > 0 && val < 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _energy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '能量 ($_energyUnit)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'kJ', label: Text('kJ', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'kcal', label: Text('kcal', style: TextStyle(fontSize: 11))),
              ],
              selected: {_energyUnit},
              onSelectionChanged: (s) {
                setState(() {
                  _energyUnit = s.first;
                });
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (isAnomaly) ...[
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
                    '能量数值偏小($val)，包装是否为 kcal？',
                    style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _energy.text = (val * 4.184).round().toString();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '一键折算为 ${(val * 4.184).round()} kJ',
                      style: TextStyle(
                        fontSize: 10.5,
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
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _sodiumField() {
    final val = double.tryParse(_sodium.text.trim());
    final isAnomaly = _sodiumUnit == 'mg' && val != null && val > 0 && val < 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _sodium,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '钠 ($_sodiumUnit)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mg', label: Text('mg', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'g', label: Text('g', style: TextStyle(fontSize: 11))),
              ],
              selected: {_sodiumUnit},
              onSelectionChanged: (s) {
                setState(() {
                  _sodiumUnit = s.first;
                });
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (isAnomaly) ...[
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
                    '钠数值偏小($val)，包装是否为克(g)？',
                    style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _sodium.text = (val * 1000).round().toString();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '一键折算为 ${(val * 1000).round()} mg',
                      style: TextStyle(
                        fontSize: 10.5,
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
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _num(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  Future<void> _submit() async {
    final rawText = _ingredients.text.trim();
    final text = TextNormalizer.cleanIngredientsText(rawText);
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先填写配料表')));
      return;
    }
    NutritionFacts? nutrition;
    if (_hasAnyNutrition()) {
      final fatVal = _d(_fat);
      final rawSat = _d(_sat);
      final satVal = (fatVal != null && rawSat != null && rawSat > fatVal) ? fatVal : rawSat;

      double? energyVal = _d(_energy);
      if (energyVal != null && _energyUnit == 'kcal') {
        energyVal = (energyVal * 4.184).roundToDouble();
      }

      double? sodiumVal = _d(_sodium);
      if (sodiumVal != null && _sodiumUnit == 'g') {
        sodiumVal = (sodiumVal * 1000).roundToDouble();
      }

      nutrition = NutritionFacts(
        basis: _liquid ? FoodForm.liquid : FoodForm.solid,
        energyKj: energyVal,
        proteinG: _d(_protein),
        fatG: fatVal,
        saturatedFatG: satVal,
        transFatG: _d(_trans),
        carbohydrateG: _d(_carb),
        sugarG: _d(_sugar),
        dietaryFiberG: _d(_fiber),
        sodiumMg: sodiumVal,
      );
    }

    final result = await ref.read(analysisProvider.notifier).analyze(
          ingredientsText: text,
          nutrition: nutrition,
          categoryCode: _categoryCode,
          barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
          productName: _name.text.trim().isEmpty ? null : _name.text.trim(),
          traceText: _traceText,
          foodForm: _liquid ? FoodForm.liquid : FoodForm.solid,
        );
    if (!mounted || result == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResultPage(isNewlyAdded: true)),
    );
  }

  bool _hasAnyNutrition() => [
        _energy, _protein, _fat, _sat, _trans, _carb, _sugar, _fiber, _sodium
      ].any((c) => c.text.trim().isNotEmpty);

  double? _d(TextEditingController c) => double.tryParse(c.text.trim());
}
