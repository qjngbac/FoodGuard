import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/history_repository.dart';
import '../../data/providers.dart';
import '../../data/remote/off_provider.dart';
import '../result/result_page.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  List<ScanRecord> _records = [];
  String _ratingFilter = '全部';
  String _categoryFilter = '全部';
  bool _isGroupedView = false;
  bool _isSelecting = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(historyRepoProvider).list(limit: 500);
    if (!mounted) return;
    setState(() => _records = list);
  }

  static String _detectCategory(ScanRecord r) {
    final code = (r.result['categoryCode'] as String?) ??
        ((r.result['compliance'] as Map?)?['categoryCode'] as String?) ??
        '';
    final name = (r.productName ?? '').toLowerCase();

    if (code.startsWith('14.') ||
        name.contains('茶') ||
        name.contains('咖啡') ||
        name.contains('水') ||
        name.contains('汽水') ||
        name.contains('可乐') ||
        name.contains('果汁') ||
        name.contains('饮料') ||
        name.contains('拿铁') ||
        name.contains('乌龙')) {
      return '🥤 饮料';
    }
    if (code.startsWith('01.') ||
        name.contains('牛奶') ||
        name.contains('酸奶') ||
        name.contains('生牛乳') ||
        name.contains('乳粉') ||
        name.contains('奶粉') ||
        name.contains('芝士') ||
        name.contains('干酪')) {
      return '🥛 乳制品';
    }
    if (code.startsWith('07.') ||
        code.startsWith('04.') ||
        code.startsWith('05.') ||
        name.contains('面包') ||
        name.contains('蛋糕') ||
        name.contains('吐司') ||
        name.contains('薯片') ||
        name.contains('饼干') ||
        name.contains('坚果') ||
        name.contains('糖') ||
        name.contains('膨化') ||
        name.contains('巧克力') ||
        name.contains('鸭脖') ||
        name.contains('肉脯') ||
        name.contains('雪饼')) {
      return '🍿 零食';
    }
    if (code.startsWith('06.') ||
        code.startsWith('08.') ||
        name.contains('面') ||
        name.contains('粉') ||
        name.contains('饺') ||
        name.contains('馄饨') ||
        name.contains('香肠') ||
        name.contains('火腿') ||
        name.contains('螺蛳') ||
        name.contains('自热')) {
      return '🍜 方便食品';
    }
    return '🥫 其他';
  }

  List<ScanRecord> get _filteredRecords {
    return _records.where((r) {
      // 评级过滤
      if (_ratingFilter == '🌟 A级好物') {
        if (!(r.grade == 'A' || r.grade == 'B' || r.score >= 80)) return false;
      } else if (_ratingFilter == '⚠️ D级避雷') {
        if (!(r.grade == 'D' || r.score < 50)) return false;
      } else if (_ratingFilter != '全部') {
        if (r.grade != _ratingFilter) return false;
      }

      // 类别过滤
      if (_categoryFilter != '全部') {
        final cat = _detectCategory(r);
        if (cat != _categoryFilter) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filteredRecords;

    return Scaffold(
      appBar: AppBar(
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '退出多选',
                onPressed: () => setState(() {
                  _isSelecting = false;
                  _selectedIds.clear();
                }),
              )
            : null,
        title: Text(_isSelecting ? '已选择 ${_selectedIds.length} 项' : '历史记录'),
        actions: _isSelecting
            ? [
                IconButton(
                  icon: Icon(_selectedIds.length == shown.length && shown.isNotEmpty
                      ? Icons.deselect
                      : Icons.select_all),
                  tooltip: _selectedIds.length == shown.length ? '取消全选' : '全选',
                  onPressed: () {
                    setState(() {
                      if (_selectedIds.length == shown.length) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds.addAll(shown.map((e) => e.id));
                      }
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: kGradeD),
                  tooltip: '删除所选',
                  onPressed: _selectedIds.isEmpty ? null : _confirmDeleteSelected,
                ),
              ]
            : [
                // 切换分类折叠视图
                IconButton(
                  icon: Icon(_isGroupedView ? Icons.view_list_rounded : Icons.folder_copy_outlined),
                  tooltip: _isGroupedView ? '平铺时间流' : '分类折叠视图',
                  onPressed: () => setState(() => _isGroupedView = !_isGroupedView),
                ),
                if (shown.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _isSelecting = true),
                    child: const Text('多选'),
                  ),
              ],
      ),
      body: Column(
        children: [
          // 评级筛选胶囊条
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('评级: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kTextSec)),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: ['全部', '🌟 A级好物', '⚠️ D级避雷', 'A', 'B', 'B-', 'C', 'D']
                        .map((g) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(g, style: const TextStyle(fontSize: 12)),
                                selected: _ratingFilter == g,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => setState(() {
                                  _ratingFilter = g;
                                  _selectedIds.clear();
                                }),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          // 类别筛选胶囊条
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('类别: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kTextSec)),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: ['全部', '🥤 饮料', '🍿 零食', '🍜 方便食品', '🥛 乳制品', '🥫 其他']
                        .map((cat) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(cat, style: const TextStyle(fontSize: 12)),
                                selected: _categoryFilter == cat,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => setState(() {
                                  _categoryFilter = cat;
                                  _selectedIds.clear();
                                }),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: shown.isEmpty
                ? const Center(
                    child: Text('没有符合条件的记录', style: TextStyle(color: kTextSec)))
                : _isGroupedView
                    ? _buildGroupedListView(shown)
                    : _buildFlatListView(shown),
          ),
        ],
      ),
    );
  }

  /// 平铺列表视图
  Widget _buildFlatListView(List<ScanRecord> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, i) => _buildRecordCard(items[i]),
    );
  }

  /// 分类折叠视图
  Widget _buildGroupedListView(List<ScanRecord> items) {
    final Map<String, List<ScanRecord>> grouped = {};
    for (final r in items) {
      final cat = _detectCategory(r);
      grouped.putIfAbsent(cat, () => []).add(r);
    }

    final categories = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: categories.length,
      itemBuilder: (context, idx) {
        final cat = categories[idx];
        final list = grouped[cat]!;
        final avgScore = list.map((e) => e.score).reduce((a, b) => a + b) / list.length;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              '$cat (${list.length}款)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '均分 ${avgScore.toStringAsFixed(0)}',
                style: const TextStyle(color: kPrimaryDark, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            children: list.map((r) => _buildRecordCard(r)).toList(),
          ),
        );
      },
    );
  }

  /// 单个商品记录卡片
  Widget _buildRecordCard(ScanRecord r) {
    final isSelected = _selectedIds.contains(r.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: ListTile(
        leading: _isSelecting
            ? Checkbox(
                value: isSelected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(r.id);
                    } else {
                      _selectedIds.remove(r.id);
                    }
                  });
                },
              )
            : CircleAvatar(
                backgroundColor: gradeColor(r.gradeEnum),
                child: Text(r.grade,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
        title: Text(
          (r.productName?.isNotEmpty ?? false)
              ? r.productName!
              : (r.barcode ?? '未命名商品'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '安全分 ${r.score}'
          '${r.barcode != null && r.productName != null ? ' · 条码:${r.barcode}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _isSelecting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: kTextSec),
                    tooltip: '修改名称',
                    onPressed: () => _showRenameDialog(r),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: kTextSec),
                ],
              ),
        onTap: () {
          if (_isSelecting) {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(r.id);
              } else {
                _selectedIds.add(r.id);
              }
            });
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => ResultPage(recordId: r.id)),
            ).then((_) => _load());
          }
        },
        onLongPress: () {
          if (!_isSelecting) {
            setState(() {
              _isSelecting = true;
              _selectedIds.add(r.id);
            });
          }
        },
      ),
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除选中的 $count 条历史记录吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGradeD),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      await ref.read(historyRepoProvider).deleteMany(_selectedIds.toList());
      setState(() {
        _isSelecting = false;
        _selectedIds.clear();
      });
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $count 条记录')),
        );
      }
    }
  }

  Future<void> _showRenameDialog(ScanRecord r) async {
    final nameCtrl = TextEditingController(text: r.productName ?? '');
    final barcodeCtrl = TextEditingController(text: r.barcode ?? '');

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改商品信息'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '商品名称',
                  hintText: '例如：特仑苏纯牛奶',
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: barcodeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '条形码（选填）',
                  hintText: '商品包装条形码',
                  prefixIcon: Icon(Icons.qr_code),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      );

      if (ok == true && mounted) {
        final newName = nameCtrl.text.trim();
        final newBarcode = barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim();
        await ref.read(historyRepoProvider).updateProductInfo(
              r.id,
              productName: newName.isNotEmpty ? newName : null,
              barcode: newBarcode,
            );
        if (newBarcode != null) {
          final store = await ref.read(localStoreProvider.future);
          store.putCache(ProductLookup(
            barcode: newBarcode,
            nameZh: newName.isNotEmpty ? newName : null,
            ingredientsText: r.ingredientsText,
            source: 'local_history',
          ));
        }
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('商品信息已更新')),
          );
        }
      }
    } finally {
      nameCtrl.dispose();
      barcodeCtrl.dispose();
    }
  }
}
