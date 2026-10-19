import 'dart:convert';
import 'dart:io';

import 'package:fangxinyong/data/knowledge_repository.dart';
import 'package:fangxinyong/data/remote/domestic_barcode_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offline Product Name Dict Tests', () {
    late KnowledgeRepository repo;

    setUp(() {
      repo = KnowledgeRepository();
    });

    tearDown(() {
      repo.close();
    });

    test('Queries 10,000+ offline product name dictionary', () async {
      final dbFile = File('assets/knowledge/foodguard.db');
      expect(dbFile.existsSync(), isTrue);

      // 查询离线品名字典条码：6920000000005 (金典有机纯牛奶 250ml 盒装)
      final p1 = await repo.findProductNameFromDict('6920000000005');
      expect(p1, isNotNull);
      expect(p1!.nameZh, contains('金典有机纯牛奶'));
      expect(p1.brand, '伊利');
      expect(p1.ingredientsText, isNull);
      expect(p1.source, 'DICT_OFFLINE');

      // 不存在的条码返回 null
      final pNonExist = await repo.findProductNameFromDict('0000000000000');
      expect(pNonExist, isNull);
    });
  });

  group('DomesticBarcodeProvider Tests', () {
    test('Successfully parses MXNZP response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'www.mxnzp.com');
        expect(request.url.path, '/api/barcode/goods/details');
        expect(request.url.queryParameters['barcode'], '6901234567890');

        final body = jsonEncode({
          'code': 1,
          'msg': '数据返回成功',
          'data': {
            'goodsName': '康师傅冰红茶',
            'brand': '康师傅',
            'standard': '500ml',
            'barcode': '6901234567890',
          }
        });
        return http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });

      final provider = DomesticBarcodeProvider(client: mockClient);
      final result = await provider.fetch('6901234567890');

      expect(result, isNotNull);
      expect(result!.barcode, '6901234567890');
      expect(result.nameZh, '康师傅冰红茶 500ml');
      expect(result.brand, '康师傅');
      expect(result.quantity, '500ml');
      expect(result.source, 'DOMESTIC_API');
    });

    test('Returns null when response code is not 1', () async {
      final mockClient = MockClient((request) async {
        final body = jsonEncode({
          'code': 0,
          'msg': '暂无该条码信息',
          'data': null,
        });
        return http.Response(body, 200);
      });

      final provider = DomesticBarcodeProvider(client: mockClient);
      final result = await provider.fetch('6999999999999');
      expect(result, isNull);
    });

    test('Handles network error or timeout gracefully', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Connection failed');
      });

      final provider = DomesticBarcodeProvider(client: mockClient);
      final result = await provider.fetch('6901234567890');
      expect(result, isNull);
    });
  });
}
