import 'package:fangxinyong/domain/entity/additive.dart';
import 'package:fangxinyong/domain/entity/ingredient.dart';
import 'package:fangxinyong/domain/entity/score_result.dart';
import 'package:fangxinyong/domain/service/compliance_judge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_pack.dart';

void main() {
  final pack = buildFakePack();
  // Add some specific usages to pack to test hierarchy and siblings
  pack.usageByAdditive[1] = [
    // 碳酸氢钠 (id=1): allowed in 07.02 (糕点) with maxUsage 2.0
    const AdditiveUsage(additiveId: 1, categoryCode: '07.02', maxUsage: 2.0, unit: 'g/kg'),
  ];
  // 焦亚硫酸钠 (id=3): in fake_pack, has 07.0 allowed (max 0.1), and 08.0 prohibited

  final judge = ComplianceJudge(pack);

  Ingredient makeAdditive(int id, String name) {
    return Ingredient(
      order: 1,
      rawText: name,
      normalized: name,
      kind: IngredientKind.additive,
      additive: pack.byId(id),
    );
  }

  group('ComplianceJudge Tests', () {
    test('Exact match and parent category inheritance', () {
      final item3 = makeAdditive(3, '焦亚硫酸钠');
      
      // 07.0 exact match
      final resExact = judge.judge([item3], '07.0');
      expect(resExact.level, 'ok');
      expect(resExact.items.first.status, UsageStatus.allowed);
      expect(resExact.items.first.maxUsage, 0.1);

      // 07.02 (糕点) is child of 07.0, inherits allowed
      final resChild = judge.judge([item3], '07.02');
      expect(resChild.level, 'ok');
      expect(resChild.items.first.status, UsageStatus.allowed);
      expect(resChild.items.first.maxUsage, 0.1);
    });

    test('Prohibited category', () {
      final item3 = makeAdditive(3, '焦亚硫酸钠');
      // 08.0 is prohibited for id=3
      final resProhibited = judge.judge([item3], '08.0');
      expect(resProhibited.level, 'suspected');
      expect(resProhibited.items.first.status, UsageStatus.prohibited);

      // Child of 08.0 (08.01) should also be prohibited
      final resProhibitedChild = judge.judge([item3], '08.01');
      expect(resProhibitedChild.level, 'suspected');
      expect(resProhibitedChild.items.first.status, UsageStatus.prohibited);
    });

    test('Sibling isolation (not listed)', () {
      final item1 = makeAdditive(1, '碳酸氢钠');
      // id=1 has rule for 07.02 only.
      // In 07.02.01 (child of 07.02), should be allowed
      final resChild = judge.judge([item1], '07.02.01');
      expect(resChild.items.first.status, UsageStatus.allowed);

      // In 07.03 (sibling of 07.02), should NOT match 07.02 -> notListed
      final resSibling = judge.judge([item1], '07.03');
      expect(resSibling.items.first.status, UsageStatus.notListed);
    });

    test('Unknown category when categoryCode is null', () {
      final item3 = makeAdditive(3, '焦亚硫酸钠');
      final res = judge.judge([item3], null);
      expect(res.level, 'unknown');
      expect(res.items.first.status, UsageStatus.unknown);
    });

    test('statusText compliance wordings', () {
      final allowedItem = ComplianceItem(
        additiveId: 3,
        additiveName: '焦亚硫酸钠',
        status: UsageStatus.allowed,
        maxUsage: 0.1,
        unit: 'g/kg',
      );
      final text = ComplianceJudge.statusText(allowedItem, '焙烤食品');
      expect(text, contains('GB 2760 允许用于「焙烤食品」，最大使用量 0.1g/kg。'));

      final prohibitedItem = ComplianceItem(
        additiveId: 3,
        additiveName: '焦亚硫酸钠',
        status: UsageStatus.prohibited,
      );
      final pText = ComplianceJudge.statusText(prohibitedItem, '肉及肉制品');
      expect(pText, contains('GB 2760 规定该物质不得用于「肉及肉制品」'));
    });
  });
}
