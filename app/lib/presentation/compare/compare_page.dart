import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/history_repository.dart';
import '../../data/providers.dart';
import '../../domain/entity/score_result.dart';

/// 货比三家：双食品健康 PK 对比模式（维度三）
import '../../data/remote/off_provider.dart';
import '../../domain/entity/nutrition_facts.dart';
import '../../domain/service/additive_matcher.dart';
import '../../domain/service/ingredient_parser.dart';
import '../../domain/service/scoring_engine.dart';
class ComparePage extends ConsumerStatefulWidget {
  const ComparePage({
    super.key,
    this.initialRecordId,
    this.initialRightRecordId,
    this.benchmarkLookup,
    this.candidateRecords,
  });

  final String? initialRecordId;
  final String? initialRightRecordId;
  final ProductLookup? benchmarkLookup;
  final List<ScanRecord>? candidateRecords;

  @override
  ConsumerState<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends ConsumerState<ComparePage> {
  List<ScanRecord> _records = [];
  bool _loading = true;

  ScanRecord? _leftRecord;
  ScanRecord? _rightRecord;

  ScoreResult? _leftResult;
  ScoreResult? _rightResult;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final list = widget.candidateRecords != null && widget.candidateRecords!.isNotEmpty
        ? widget.candidateRecords!
        : await ref.read(historyRepoProvider).list(limit: 50);
    if (!mounted) return;

    ScanRecord? leftRec;
    ScoreResult? leftRes;
    ScanRecord? rightRec;
    ScoreResult? rightRes;

    if (list.isNotEmpty) {
      if (widget.initialRecordId != null) {
        leftRec = list.firstWhere(
          (r) => r.id == widget.initialRecordId,
          orElse: () => list.first,
        );
      } else {
        leftRec = list.first;
      }
      leftRes = ScoreResult.fromJson(leftRec.result);

      if (widget.benchmarkLookup != null) {
        final bench = widget.benchmarkLookup!;
        try {
          final pack = await ref.read(packProvider.future);
          final parsed = IngredientParser(dictionary: pack.allKnownNames.toSet())
              .parse(bench.ingredientsText ?? '');
          final items = AdditiveMatcher(pack).match(parsed);
          final form = (bench.categoryHint?.startsWith('14') ?? false)
              ? FoodForm.liquid
              : FoodForm.solid;
          final evaluated = ScoringEngine(pack).evaluate(
            ScoreInput(
              ingredients: items,
              nutrition: bench.nutrition,
              foodForm: form,
              categoryCode: bench.categoryHint,
              profile: ref.read(profileProvider),
              knowledgeVersion: pack.version,
            ),
          );
          rightRec = ScanRecord(
            id: 'bench_${bench.barcode}',
            score: evaluated.score,
            grade: evaluated.personalGrade.label,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            result: evaluated.toJson(),
            barcode: bench.barcode,
            productName: bench.nameZh,
            brand: bench.brand,
            ingredientsText: bench.ingredientsText,
          );
          rightRes = evaluated;
        } catch (_) {}
      } else if (widget.initialRightRecordId != null) {
        rightRec = list.firstWhere(
          (r) => r.id == widget.initialRightRecordId,
          orElse: () => list.firstWhere((r) => r.id != leftRec?.id, orElse: () => list.first),
        );
        rightRes = ScoreResult.fromJson(rightRec.result);
      } else if (list.length > 1) {
        rightRec = list.firstWhere(
          (r) => r.id != leftRec?.id,
          orElse: () => list[1],
        );
        rightRes = ScoreResult.fromJson(rightRec.result);
      }
    }

    final allDisplayRecords = List<ScanRecord>.from(list);
    if (rightRec != null && !allDisplayRecords.any((r) => r.id == rightRec!.id)) {
      allDisplayRecords.add(rightRec);
    }

    setState(() {
      _records = allDisplayRecords;
      _leftRecord = leftRec;
      _leftResult = leftRes;
      _rightRecord = rightRec;
      _rightResult = rightRes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_records.length < 2 && _rightRecord == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('货比三家')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.compare_arrows, size: 64, color: kPrimary),
                const SizedBox(height: 16),
                const Text('还没有足够的扫描记录',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  '需要至少扫描或输入 2 款商品，才能开启双商品健康 PK 对比！',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: kTextSec),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('去扫描商品'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('货比三家 · 健康 PK'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部选择与分栏卡片
          _buildSelectorHeader(),

          const SizedBox(height: 16),

          // 胜负决策大横幅
          if (_leftResult != null && _rightResult != null)
            _buildVerdictCard(_leftResult!, _rightResult!),

          const SizedBox(height: 16),

          // 对比维度指标卡
          if (_leftResult != null && _rightResult != null) ...[
            _buildComparisonCard(
              title: '安全得分与等级',
              leftVal: '${_leftResult!.score} 分 (${_leftResult!.personalGrade.label})',
              rightVal: '${_rightResult!.score} 分 (${_rightResult!.personalGrade.label})',
              leftWin: _leftResult!.score > _rightResult!.score,
              rightWin: _rightResult!.score > _leftResult!.score,
            ),
            _buildComparisonCard(
              title: '食品添加剂总数',
              leftVal: '${_leftResult!.additiveItems.length} 种',
              rightVal: '${_rightResult!.additiveItems.length} 种',
              leftWin: _leftResult!.additiveItems.length < _rightResult!.additiveItems.length,
              rightWin: _rightResult!.additiveItems.length < _leftResult!.additiveItems.length,
              subtitle: '越少越纯净',
            ),
            _buildComparisonCard(
              title: '高关注添加剂 (Risk 4/5)',
              leftVal: '${_leftResult!.additiveItems.where((e) => e.riskLevel >= 4).length} 种',
              rightVal: '${_rightResult!.additiveItems.where((e) => e.riskLevel >= 4).length} 种',
              leftWin: _leftResult!.additiveItems.where((e) => e.riskLevel >= 4).length <
                  _rightResult!.additiveItems.where((e) => e.riskLevel >= 4).length,
              rightWin: _rightResult!.additiveItems.where((e) => e.riskLevel >= 4).length <
                  _leftResult!.additiveItems.where((e) => e.riskLevel >= 4).length,
              subtitle: '高风险越少越安全',
            ),
            _buildComparisonCard(
              title: '加工度等级 (NOVA)',
              leftVal: 'NOVA ${_leftResult!.nova.group}',
              rightVal: 'NOVA ${_rightResult!.nova.group}',
              leftWin: _leftResult!.nova.group < _rightResult!.nova.group,
              rightWin: _rightResult!.nova.group < _leftResult!.nova.group,
              subtitle: '级数越低越少深度加工',
            ),
            _buildNutritionSection(),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSelectorHeader() {
    return Row(
      children: [
        // 左商品
        Expanded(child: _productPickCard(isLeft: true)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: kPrimary,
            child: Text('VS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
        // 右商品
        Expanded(child: _productPickCard(isLeft: false)),
      ],
    );
  }

  Widget _productPickCard({required bool isLeft}) {
    final record = isLeft ? _leftRecord : _rightRecord;
    final res = isLeft ? _leftResult : _rightResult;
    final color = res != null ? gradeColor(res.personalGrade) : kPrimary;

    return Card(
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusM),
        onTap: () => _pickProduct(isLeft: isLeft),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isLeft ? '商品 A' : '商品 B',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kTextSec),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 16, color: kTextSec),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                (record?.productName?.isNotEmpty ?? false) ? record!.productName! : (record?.barcode ?? '点击选择'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              if (res != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(kRadiusS),
                  ),
                  child: Text(
                    '${res.score}分 · ${res.personalGrade.label}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickProduct({required bool isLeft}) async {
    final picked = await showModalBottomSheet<ScanRecord>(
      context: context,
      builder: (_) => ListView.builder(
        itemCount: _records.length,
        itemBuilder: (ctx, idx) {
          final r = _records[idx];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: gradeColor(r.gradeEnum),
              child: Text(r.grade, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            title: Text((r.productName?.isNotEmpty ?? false) ? r.productName! : (r.barcode ?? '未命名商品')),
            subtitle: Text('得分 ${r.score} · ${_timeAgo(r.createdAt)}'),
            onTap: () => Navigator.pop(ctx, r),
          );
        },
      ),
    );

    if (picked != null) {
      setState(() {
        if (isLeft) {
          _leftRecord = picked;
          _leftResult = ScoreResult.fromJson(picked.result);
        } else {
          _rightRecord = picked;
          _rightResult = ScoreResult.fromJson(picked.result);
        }
      });
    }
  }

  Widget _buildVerdictCard(ScoreResult left, ScoreResult right) {
    String verdict;
    Color color;
    IconData icon;

    if (left.score > right.score + 5) {
      verdict = '商品 A 综合安全评分高出 ${left.score - right.score} 分，配料纯净度更具优势，更推荐选购商品 A！';
      color = kGradeA;
      icon = Icons.thumb_up_alt_outlined;
    } else if (right.score > left.score + 5) {
      verdict = '商品 B 综合安全评分高出 ${right.score - left.score} 分，配料纯净度更具优势，更推荐选购商品 B！';
      color = kGradeA;
      icon = Icons.thumb_up_alt_outlined;
    } else {
      verdict = '两款商品评分接近（相差 ≤ 5 分），可根据下方添加剂种类与糖钠偏好综合抉择。';
      color = kGradeBMinus;
      icon = Icons.balance_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusM),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              verdict,
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard({
    required String title,
    required String leftVal,
    required String rightVal,
    required bool leftWin,
    required bool rightWin,
    String? subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(color: kTextSec, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: leftWin ? kPrimary.withValues(alpha: 0.1) : kBg,
                      borderRadius: BorderRadius.circular(kRadiusS),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (leftWin)
                            const Icon(Icons.check_circle, color: kPrimary, size: 14),
                          if (leftWin) const SizedBox(width: 4),
                          Text(leftVal,
                              style: TextStyle(
                                  fontWeight: leftWin ? FontWeight.bold : FontWeight.normal,
                                  color: leftWin ? kPrimary : kTextPri,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: rightWin ? kPrimary.withValues(alpha: 0.1) : kBg,
                      borderRadius: BorderRadius.circular(kRadiusS),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (rightWin)
                            const Icon(Icons.check_circle, color: kPrimary, size: 14),
                          if (rightWin) const SizedBox(width: 4),
                          Text(rightVal,
                              style: TextStyle(
                                  fontWeight: rightWin ? FontWeight.bold : FontWeight.normal,
                                  color: rightWin ? kPrimary : kTextPri,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionSection() {
    final lEval = _leftResult?.nutritionEval;
    final rEval = _rightResult?.nutritionEval;
    if (lEval == null && rEval == null) return const SizedBox.shrink();

    double? getVal(ScoreResult? res, String code) {
      if (res?.nutritionEval == null) return null;
      for (final item in res!.nutritionEval!.items) {
        if (item.code == code) return item.value;
      }
      return null;
    }

    final lSodium = getVal(_leftResult, 'SODIUM');
    final rSodium = getVal(_rightResult, 'SODIUM');
    final lSugar = getVal(_leftResult, 'SUGAR');
    final rSugar = getVal(_rightResult, 'SUGAR');

    return Column(
      children: [
        if (lSodium != null || rSodium != null)
          _buildComparisonCard(
            title: '钠含量 (每100g/mL)',
            leftVal: lSodium != null ? '${lSodium.toStringAsFixed(0)} mg' : '未标',
            rightVal: rSodium != null ? '${rSodium.toStringAsFixed(0)} mg' : '未标',
            leftWin: (lSodium ?? 99999) < (rSodium ?? 99999),
            rightWin: (rSodium ?? 99999) < (lSodium ?? 99999),
            subtitle: '低钠更健康',
          ),
        if (lSugar != null || rSugar != null)
          _buildComparisonCard(
            title: '糖含量 (每100g/mL)',
            leftVal: lSugar != null ? '${lSugar.toStringAsFixed(1)} g' : '未标',
            rightVal: rSugar != null ? '${rSugar.toStringAsFixed(1)} g' : '未标',
            leftWin: (lSugar ?? 99999) < (rSugar ?? 99999),
            rightWin: (rSugar ?? 99999) < (lSugar ?? 99999),
            subtitle: '控糖更优',
          ),
      ],
    );
  }

  String _timeAgo(int ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    final m = diff ~/ 60000;
    if (m < 1) return '刚刚';
    if (m < 60) return '$m 分钟前';
    final h = m ~/ 60;
    if (h < 24) return '$h 小时前';
    return '${h ~/ 24} 天前';
  }
}
