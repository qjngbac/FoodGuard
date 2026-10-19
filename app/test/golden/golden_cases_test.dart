import 'dart:convert';
import 'dart:io';

import 'package:fangxinyong/domain/entity/nutrition_facts.dart';
import 'package:fangxinyong/domain/entity/score_result.dart';
import 'package:fangxinyong/domain/entity/user_profile.dart';
import 'package:fangxinyong/domain/service/additive_matcher.dart';
import 'package:fangxinyong/domain/service/ingredient_parser.dart';
import 'package:fangxinyong/domain/service/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_pack.dart';

void main() {
  final pack = buildFakePack();

  test('Run golden cases in golden_cases.json', () {
    final file = File('test/golden/golden_cases.json');
    expect(file.existsSync(), isTrue);
    final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final cases = jsonMap['cases'] as List<dynamic>;
    expect(cases, isNotEmpty);

    for (final c in cases) {
      final id = c['id'] as String;
      final ingredients = c['ingredients'] as String;
      final categoryCode = c['categoryCode'] as String?;
      final formStr = c['foodForm'] as String? ?? 'SOLID';
      final form = formStr == 'LIQUID' ? FoodForm.liquid : FoodForm.solid;

      NutritionFacts? nutrition;
      if (c['nutrition'] != null) {
        final n = c['nutrition'] as Map<String, dynamic>;
        nutrition = NutritionFacts(
          basis: form,
          energyKj: (n['energyKj'] as num?)?.toDouble(),
          proteinG: (n['proteinG'] as num?)?.toDouble(),
          fatG: (n['fatG'] as num?)?.toDouble(),
          saturatedFatG: (n['saturatedFatG'] as num?)?.toDouble(),
          transFatG: (n['transFatG'] as num?)?.toDouble(),
          carbohydrateG: (n['carbohydrateG'] as num?)?.toDouble(),
          sugarG: (n['sugarG'] as num?)?.toDouble(),
          dietaryFiberG: (n['dietaryFiberG'] as num?)?.toDouble(),
          sodiumMg: (n['sodiumMg'] as num?)?.toDouble(),
        );
      }

      final parsed = IngredientParser().parse(ingredients);
      final items = AdditiveMatcher(pack).match(parsed);
      final result = ScoringEngine(pack).evaluate(
        ScoreInput(
          ingredients: items,
          nutrition: nutrition,
          foodForm: form,
          categoryCode: categoryCode,
          profile: const UserProfile(),
          knowledgeVersion: pack.version,
        ),
      );

      final expectMap = c['expect'] as Map<String, dynamic>;
      if (expectMap['grade'] != null) {
        expect(result.personalGrade.label, expectMap['grade'],
            reason: 'Case $id grade mismatch');
      }
      if (expectMap['score'] != null) {
        final tol = (c['tolerance']?['score'] as num?)?.toDouble() ?? 5.0;
        final expectedScore = (expectMap['score'] as num).toDouble();
        expect(result.score.toDouble(), closeTo(expectedScore, tol),
            reason: 'Case $id score mismatch');
      }
      if (expectMap['additiveCount'] != null) {
        expect(result.additiveItems.length, expectMap['additiveCount'],
            reason: 'Case $id additive count mismatch');
      }
      if (expectMap['mustContainAdditive'] != null) {
        final mustList = (expectMap['mustContainAdditive'] as List).cast<String>();
        final names = result.additiveItems.map((e) => e.name).toSet();
        for (final m in mustList) {
          expect(names.contains(m), isTrue,
              reason: 'Case $id missing expected additive: $m');
        }
      }
    }
  });
}
