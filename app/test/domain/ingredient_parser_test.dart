import 'package:fangxinyong/domain/service/ingredient_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = IngredientParser();

  List<String> names(String text) =>
      parser.parse(text).map((e) => e.rawText).toList();

  test('P-01 简单配料表', () {
    final r = parser.parse('配料：小麦粉、白砂糖、植物油、鸡蛋、食用盐、碳酸氢钠、柠檬酸');
    expect(r.length, 7);
    expect(r.first.rawText, '小麦粉');
    expect(r.last.rawText, '柠檬酸');
  });

  test('P-02 食品添加剂括号内提升为顶层', () {
    final r = parser.parse(
        '配料表：水、果葡糖浆、白砂糖、浓缩苹果汁、食品添加剂（羧甲基纤维素钠、柠檬酸、'
        '柠檬酸钠、山梨酸钾、安赛蜜、阿斯巴甜（含苯丙氨酸）、食用香精）、维生素C');
    final texts = r.map((e) => e.rawText).toList();
    expect(texts, contains('羧甲基纤维素钠'));
    expect(texts, contains('食用香精'));
    expect(texts.contains('食品添加剂'), isFalse);
    // 全部提升为顶层
    expect(r.every((e) => e.depth == 0), isTrue);
    expect(r.length, 12);
  });

  test('P-02b 单、双甘油脂肪酸酯不被顿号切断，食品添加剂不作独立配料', () {
    final r = parser.parse('配料：水、生牛乳、食品添加剂（卡拉胶、单、双甘油脂肪酸酯、食用香精）');
    final texts = r.map((e) => e.rawText).toList();
    expect(texts, contains('单双甘油脂肪酸酯'));
    expect(texts.contains('单'), isFalse);
    expect(texts.contains('食品添加剂'), isFalse);
    expect(r.length, 5);
  });

  test('P-03 复合配料展开为子项', () {
    final r = parser.parse(
        '配料：小麦粉（45%）、水、人造奶油（植物油、水、食用盐、单双甘油脂肪酸酯、'
        '食用香精、β-胡萝卜素）、全脂乳粉、酵母、丙酸钙、脱氢乙酸钠');
    final parents = r.where((e) => e.depth == 0).length;
    final children = r.where((e) => e.depth == 1).length;
    expect(parents, 7);
    expect(children, 6); // 人造奶油括号内的 6 项（"45%" 属注解，不计）
    final wheat = r.firstWhere((e) => e.rawText.contains('小麦粉'));
    expect(wheat.percent, 45);
  });

  test('P-05 无分隔符（OCR 场景）不崩溃', () {
    final r = parser.parse(
        '配料：水白砂糖全脂乳粉食品添加剂（羧甲基纤维素钠柠檬酸三聚磷酸钠）食用香精');
    expect(r, isNotEmpty);
    expect(r.map((e) => e.rawText), contains('食用香精'));
  });

  test('P-07 嵌套括号深度 2', () {
    final r = parser.parse('配料：巧克力（白砂糖、可可脂、乳化剂（大豆磷脂）、食用香精）');
    final texts = r.map((e) => e.rawText).toList();
    expect(texts, contains('大豆磷脂'));
    expect(texts, contains('食用香精'));
  });

  test('P-08 已删除品种能被识别出来', () {
    final r = parser.parse('配料：落葵红、小麦粉');
    expect(names('配料：落葵红、小麦粉'), contains('落葵红'));
    expect(r.length, 2);
  });

  test('P-14/P-15/P-16 空与异常输入不崩溃', () {
    expect(parser.parse(''), isEmpty);
    expect(parser.parse('配料：'), isEmpty);
    expect(() => parser.parse('配料：('), returnsNormally);
  });

  test('N3 尾部无关段被截断', () {
    final r = parser.parse('配料：小麦粉、水、食用盐。净含量：400g 生产商：某某公司');
    final texts = r.map((e) => e.rawText).join(',');
    expect(texts.contains('生产商'), isFalse);
    expect(texts.contains('净含量'), isFalse);
  });

  test('P-17 超长配料表性能', () {
    final long = List.generate(60, (i) => '配料$i').join('、');
    final sw = Stopwatch()..start();
    parser.parse('配料：$long');
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(200));
  });
}
