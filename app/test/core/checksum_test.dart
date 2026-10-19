import 'package:fangxinyong/core/util/checksum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BarcodeChecksum Tests', () {
    test('EAN-13 valid and invalid checks', () {
      // 6901234567892 is a valid EAN-13
      expect(BarcodeChecksum.isValidEan13('6901234567892'), isTrue);
      // Wrong check digit
      expect(BarcodeChecksum.isValidEan13('6901234567893'), isFalse);
      // Non-numeric or wrong length
      expect(BarcodeChecksum.isValidEan13('690123456789'), isFalse);
      expect(BarcodeChecksum.isValidEan13('69012345678921'), isFalse);
      expect(BarcodeChecksum.isValidEan13('690123456789X'), isFalse);
    });

    test('EAN-8 valid and invalid checks', () {
      // 40123455 is a valid EAN-8
      expect(BarcodeChecksum.isValidEan8('40123455'), isTrue);
      // Wrong check digit
      expect(BarcodeChecksum.isValidEan8('40123456'), isFalse);
      // Wrong length
      expect(BarcodeChecksum.isValidEan8('4012345'), isFalse);
      expect(BarcodeChecksum.isValidEan8('401234550'), isFalse);
    });

    test('UPC-A valid and invalid checks', () {
      // 012345678905 is a valid UPC-A
      expect(BarcodeChecksum.isValidUpcA('012345678905'), isTrue);
      // Wrong check digit
      expect(BarcodeChecksum.isValidUpcA('012345678906'), isFalse);
      // Wrong length
      expect(BarcodeChecksum.isValidUpcA('01234567890'), isFalse);
      expect(BarcodeChecksum.isValidUpcA('0123456789055'), isFalse);
    });

    test('isValid general dispatch', () {
      expect(BarcodeChecksum.isValid('6901234567892'), isTrue);
      expect(BarcodeChecksum.isValid('40123455'), isTrue);
      expect(BarcodeChecksum.isValid('012345678905'), isTrue);
      expect(BarcodeChecksum.isValid('6901234567893'), isFalse);
      // Non standard length 4-30 chars
      expect(BarcodeChecksum.isValid('CODE128'), isTrue);
      expect(BarcodeChecksum.isValid('ABC'), isFalse);
    });
  });
}
