import 'package:fangxinyong/domain/entity/ingredient.dart';
import 'package:fangxinyong/domain/service/additive_matcher.dart';
import 'package:fangxinyong/domain/service/ingredient_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_pack.dart';

void main() {
  final pack = buildFakePack();
  final matcher = AdditiveMatcher(pack);
  final parser = IngredientParser();

  List<Ingredient> matchText(String text) {
    final parsed = parser.parse(text);
    return matcher.match(parsed);
  }

  group('AdditiveMatcher Tests', () {
    test('M1 Exact Match', () {
      final res = matchText('配料：柠檬酸、碳酸氢钠');
      expect(res.length, 2);
      expect(res[0].kind, IngredientKind.additive);
      expect(res[0].additive?.nameZh, '柠檬酸');
      expect(res[0].matchMethod, 'M1');
      expect(res[1].additive?.nameZh, '碳酸氢钠');
      expect(res[1].matchMethod, 'M1');
    });

    test('M2 Alias Match', () {
      final res = matchText('配料：TBHQ、味精');
      expect(res.length, 2);
      expect(res[0].additive?.nameZh, '特丁基对苯二酚');
      expect(res[0].matchMethod, 'M2');
      expect(res[1].additive?.nameZh, '谷氨酸钠');
      expect(res[1].matchMethod, 'M2');
    });

    test('M3 Salt Normalization - Base acid to salt in pack', () {
      // Pack has 山梨酸钾, input is 山梨酸
      final res = matchText('配料：山梨酸');
      expect(res.length, 1);
      expect(res[0].kind, IngredientKind.additive);
      expect(res[0].additive?.nameZh, '山梨酸钾');
      expect(res[0].matchMethod, 'M3');
    });

    test('M3 Salt Normalization - Sibling salt to salt in pack', () {
      // Pack has 山梨酸钾, input is 山梨酸钠 (ends with 酸钠)
      final res = matchText('配料：山梨酸钠');
      expect(res.length, 1);
      expect(res[0].kind, IngredientKind.additive);
      expect(res[0].additive?.nameZh, '山梨酸钾');
      expect(res[0].matchMethod, 'M3');
    });

    test('Raw material and Unknown match', () {
      final res = matchText('配料：小麦粉、神秘配料X');
      expect(res.length, 2);
      expect(res[0].kind, IngredientKind.rawMaterial);
      expect(res[0].allergenCode, 'GLUTEN');
      expect(res[1].kind, IngredientKind.unknown);
    });

    test('Fuzzy OCR Misspelling and Levenshtein Tolerance Match', () {
      // 1. 白砂溏 -> 白砂糖 (形近/同音字纠偏)
      final r1 = matchText('配料：白砂溏');
      expect(r1.length, 1);
      expect(r1[0].kind, IngredientKind.rawMaterial);
      expect(r1[0].normalized, '白砂糖');
      expect(r1[0].matchMethod, anyOf(['MR', 'MR_FUZZY']));

      // 2. 碳酸氢纳 -> 碳酸氢钠 (添加剂容错)
      final r2 = matchText('配料：碳酸氢纳');
      expect(r2.length, 1);
      expect(r2[0].kind, IngredientKind.additive);
      expect(r2[0].additive?.nameZh, '碳酸氢钠');

      // 3. 山梨酸纳 -> 归一为山梨酸钾
      final r3 = matchText('配料：山梨酸纳');
      expect(r3.length, 1);
      expect(r3[0].kind, IngredientKind.additive);
      expect(r3[0].additive?.nameZh, '山梨酸钾');

      // 4. 白砂汤 (纯 Levenshtein 编辑距离 <= 1，不在纠偏词典中)
      final r4 = matchText('配料：白砂汤');
      expect(r4.length, 1);
      expect(r4[0].kind, IngredientKind.rawMaterial);
      expect(r4[0].matchMethod, 'MR_FUZZY');
    });
  });
}
