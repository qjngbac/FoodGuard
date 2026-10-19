import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/text_normalizer.dart';
import '../../data/ocr/ocr_service.dart';
import '../../data/providers.dart';
import '../../domain/entity/nutrition_facts.dart';
import '../result/result_page.dart';
import 'image_crop_page.dart';

/// 拍照 / 相册 → 端上中文 OCR → 校对 → 送去做分析
class OcrPage extends ConsumerStatefulWidget {
  const OcrPage({super.key, this.barcode, this.productName});

  final String? barcode;
  final String? productName;

  @override
  ConsumerState<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends ConsumerState<OcrPage> {
  final _name = TextEditingController();
  final _ingredients = TextEditingController();
  final _energy = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();
  final _sat = TextEditingController();
  final _trans = TextEditingController();
  final _carb = TextEditingController();
  final _sugar = TextEditingController();
  final _fiber = TextEditingController();
  final _sodium = TextEditingController();

  bool _busy = false;
  bool _submitting = false;
  bool _liquid = false;
  String? _error;
  String? _traceText;
  String? _imagePath;
  String? _originalImagePath;

  @override
  void initState() {
    super.initState();
    if (widget.productName != null) _name.text = widget.productName!;
  }

  @override
  void dispose() {
    for (final c in [
      _name, _ingredients, _energy, _protein, _fat, _sat, _trans, _carb, _sugar, _fiber, _sodium
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(ImageSourcePlacement source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final svc = ref.read(ocrServiceProvider);
    XFile? file;
    try {
      file = source == ImageSourcePlacement.camera
          ? await svc.pickFromCamera()
          : await svc.pickFromGallery();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '无法打开相机/相册：$e';
        });
      }
      return;
    }
    if (file == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    _originalImagePath = file.path;

    // 核心优化：打开交互式裁剪页面，引导用户框选配料表/营养表区域，排除包装上的广告与厂家多余文字
    if (!mounted) return;
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ImageCropPage(imagePath: file!.path)),
    );

    if (croppedPath == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    await _recognizeImage(croppedPath);
  }

  Future<void> _reCrop() async {
    final src = _originalImagePath ?? _imagePath;
    if (src == null) return;
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ImageCropPage(imagePath: src)),
    );
    if (croppedPath != null && mounted) {
      await _recognizeImage(croppedPath);
    }
  }

  Future<void> _recognizeImage(String imagePath) async {
    setState(() {
      _busy = true;
      _error = null;
      _imagePath = imagePath;
    });

    final svc = ref.read(ocrServiceProvider);
    final text = await svc.recognize(imagePath);
    if (!mounted) return;

    if (text == null) {
      setState(() {
        _busy = false;
        _error = '本地识别不可用（设备缺少中文识别模型）。请手动输入配料表。';
      });
      return;
    }

    final ingredients = extractIngredients(text);
    final nutrition = extractNutrition(text);
    _traceText = extractTrace(text);

    setState(() {
      _busy = false;
      if (ingredients != null && ingredients.isNotEmpty) {
        _ingredients.text = ingredients;
      } else {
        // 如果截取的刚好是配料表文字主体（不含“配料：”前缀），直接填入纯净文字
        _ingredients.text = text;
      }
      if (nutrition != null) {
        _energy.text = nutrition['energyKj']?.toStringAsFixed(0) ?? '';
        _protein.text = nutrition['proteinG']?.toStringAsFixed(1) ?? '';
        _fat.text = nutrition['fatG']?.toStringAsFixed(1) ?? '';
        _sat.text = nutrition['saturatedFatG']?.toStringAsFixed(1) ?? '';
        _trans.text = nutrition['transFatG']?.toStringAsFixed(1) ?? '';
        _carb.text = nutrition['carbohydrateG']?.toStringAsFixed(1) ?? '';
        _sugar.text = nutrition['sugarG']?.toStringAsFixed(1) ?? '';
        _fiber.text = nutrition['dietaryFiberG']?.toStringAsFixed(1) ?? '';
        _sodium.text = nutrition['sodiumMg']?.toStringAsFixed(0) ?? '';
      }
      if (_ingredients.text.isEmpty) {
        _error = '未能自动定位配料表，请手动粘贴或输入。';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拍照识别配料表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_imagePath != null) ...[
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(kRadiusM),
                  child: Image.file(
                    File(_imagePath!),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _reCrop,
                    icon: const Icon(Icons.content_cut, size: 16),
                    label: const Text('重新截取区域', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.75),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(kRadiusM),
              border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: const [
                Icon(Icons.lightbulb_outline, size: 18, color: kPrimary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '拍摄提示：请保持包装表面平整无折叠，避免强反光与阴影；若识别字迹不全，可直接在下方输入框中补充修改。',
                    style: TextStyle(fontSize: 12, color: kTextPri, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (widget.barcode != null && widget.barcode!.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kRadiusS),
                border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code, size: 18, color: kPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已关联条形码：${widget.barcode}',
                      style: const TextStyle(fontSize: 13, color: kPrimary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '商品名称（选填，方便历史查找）',
              prefixIcon: Icon(Icons.shopping_bag_outlined),
              hintText: '例如：特仑苏纯牛奶',
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _run(ImageSourcePlacement.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('拍照'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(ImageSourcePlacement.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从相册选'),
                ),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(child: Text('正在识别…（在本机完成）')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kWarnBg,
                borderRadius: BorderRadius.circular(kRadiusS),
              ),
              child: Text(_error!, style: const TextStyle(color: kGradeC, fontSize: 13)),
            ),
          ],
          if (_ingredients.text.isNotEmpty || _imagePath != null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _ingredients,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: '配料表（请核对后再分析）',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('按液体计算（每 100 mL）'),
              value: _liquid,
              onChanged: (v) => setState(() => _liquid = v),
            ),
            _num(_energy, '能量 (kJ)'),
            _num(_protein, '蛋白质 (g)'),
            _num(_fat, '脂肪 (g)'),
            _num(_carb, '碳水化合物 (g)'),
            _num(_sodium, '钠 (mg)'),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_ingredients.text.trim().isEmpty || _submitting) ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.analytics_outlined),
              label: Text(_submitting ? '正在分析…' : '去分析'),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _num(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Future<void> _submit() async {
    if (_submitting) return;
    final text = TextNormalizer.cleanIngredientsText(_ingredients.text.trim());
    if (text.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final fatVal = _d(_fat);
      final rawSat = _d(_sat);
      final satVal = (fatVal != null && rawSat != null && rawSat > fatVal) ? fatVal : rawSat;
      final facts = NutritionFacts(
        basis: _liquid ? FoodForm.liquid : FoodForm.solid,
        energyKj: _d(_energy),
        proteinG: _d(_protein),
        fatG: fatVal,
        saturatedFatG: satVal,
        transFatG: _d(_trans),
        carbohydrateG: _d(_carb),
        sugarG: _d(_sugar),
        dietaryFiberG: _d(_fiber),
        sodiumMg: _d(_sodium),
      );

      final result = await ref.read(analysisProvider.notifier).analyze(
        ingredientsText: text,
        nutrition: facts.isEmpty ? null : facts,
        traceText: _traceText,
        barcode: widget.barcode,
        productName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        foodForm: _liquid ? FoodForm.liquid : FoodForm.solid,
      );

      if (!mounted || result == null) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ResultPage(isNewlyAdded: true)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  double? _d(TextEditingController c) => double.tryParse(c.text.trim());
}

enum ImageSourcePlacement { camera, gallery }
