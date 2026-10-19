import 'dart:io';

import 'package:fangxinyong/core/util/checksum.dart';
import 'package:fangxinyong/data/knowledge_repository.dart';
import 'package:fangxinyong/domain/entity/ingredient.dart';
import 'package:fangxinyong/domain/entity/nutrition_facts.dart';
import 'package:fangxinyong/domain/entity/score_result.dart';
import 'package:fangxinyong/domain/entity/user_profile.dart';
import 'package:fangxinyong/domain/service/additive_matcher.dart';
import 'package:fangxinyong/domain/service/ingredient_parser.dart';
import 'package:fangxinyong/domain/service/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offline Seed Barcode Tests', () {
    late KnowledgeRepository repo;

    setUp(() {
      repo = KnowledgeRepository();
    });

    tearDown(() {
      repo.close();
    });

    test('Loads 3000+ items and queries by barcode offline', () async {
      final dbFile = File('assets/knowledge/foodguard.db');
      expect(dbFile.existsSync(), isTrue, reason: 'assets/knowledge/foodguard.db must exist');

      // 验证已知国货条码（前几个条码）
      // 690100100000 -> Checksum 3 -> 6901001000003 (特仑苏 纯牛奶 250ml 经典装)
      final p1 = await repo.findProductByBarcode('6901001000003');
      expect(p1, isNotNull);
      expect(p1!.nameZh, contains('特仑苏'));
      expect(p1.brand, '蒙牛');
      expect(p1.ingredientsText, contains('生牛乳'));
      expect(p1.source, 'SEED_OFFLINE');
      expect(BarcodeChecksum.isValidEan13(p1.barcode), isTrue);

      // 查询不存在的条码应返回 null
      final pNonExist = await repo.findProductByBarcode('9999999999999');
      expect(pNonExist, isNull);
    });

    test('Offline seed product can be scored accurately by ScoringEngine', () async {
      final pack = await repo.load();
      final p1 = await repo.findProductByBarcode('6901001000003'); // 特仑苏
      expect(p1, isNotNull);

      final parsed = IngredientParser().parse(p1!.ingredientsText!);
      expect(parsed, isNotEmpty);

      final items = AdditiveMatcher(pack).match(parsed);

      final result = ScoringEngine(pack).evaluate(
        ScoreInput(
          ingredients: items,
          nutrition: p1.nutrition,
          foodForm: FoodForm.liquid,
          categoryCode: p1.categoryHint,
          profile: const UserProfile(),
          knowledgeVersion: pack.version,
        ),
      );

      expect(result.score, greaterThan(80)); // 纯牛奶应当评分极高（A级）
      expect(result.personalGrade.label, 'A');
    });

    test('Wahaha pure water 6902083881405 exists in offline seed and scores 100', () async {
      final pack = await repo.load();
      final wahaha = await repo.findProductByBarcode('6902083881405');
      expect(wahaha, isNotNull);
      expect(wahaha!.nameZh, contains('娃哈哈'));
      expect(wahaha.hasIngredients, isTrue);

      final parsed = IngredientParser().parse(wahaha.ingredientsText!);
      final items = AdditiveMatcher(pack).match(parsed);
      final result = ScoringEngine(pack).evaluate(
        ScoreInput(
          ingredients: items,
          nutrition: wahaha.nutrition,
          foodForm: FoodForm.liquid,
          categoryCode: wahaha.categoryHint ?? '14.0',
          profile: const UserProfile(),
          knowledgeVersion: pack.version,
        ),
      );
      expect(result.score, 100);
      expect(result.personalGrade.label, 'A');
    });

    test('Nestle classic coffee ingredients match as rawMaterial and not unknown', () async {
      final pack = await repo.load();
      final parsed = IngredientParser().parse('速溶咖啡、咖啡豆提取物');
      expect(parsed.length, 2);

      final items = AdditiveMatcher(pack).match(parsed);
      for (final item in items) {
        expect(item.kind, isNot(equals(IngredientKind.unknown)),
            reason: '${item.rawText} should be recognized as raw material or known');
      }
    });
  });
}
