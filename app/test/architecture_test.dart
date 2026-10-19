import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 分层约束：domain 层不得依赖任何 IO / 网络 / 数据库实现
void main() {
  test('domain 层保持纯净（无 dart:io / http / sqlite）', () {
    final root = Directory('./lib/domain');
    if (!root.existsSync()) {
      fail('找不到 lib/domain 目录');
    }
    const banned = <String>['dart:io', 'package:http', 'package:sqlite3', 'dart:ffi'];
    final violations = <String>[];

    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final src = file.readAsStringSync();
      for (final b in banned) {
        if (src.contains(b)) violations.add('${file.path} 引入了 $b');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('entity 不得依赖 Flutter（domain 必须可纯 Dart 单测）', () {
    final entityDir = Directory('./lib/domain/entity');
    final violations = <String>[];
    for (final file in entityDir.listSync().whereType<File>()) {
      final src = file.readAsStringSync();
      if (src.contains('package:flutter/')) {
        violations.add('${file.path} 引入了 package:flutter');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
