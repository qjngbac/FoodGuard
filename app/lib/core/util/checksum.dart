/// 条形码校验位算法（docs/08 §3.3，T-311）
class BarcodeChecksum {
  /// 校验 EAN-13 条形码（13 位数字）
  static bool isValidEan13(String code) {
    if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;
    final digits = code.split('').map(int.parse).toList();
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += digits[i] * (i.isEven ? 1 : 3);
    }
    final check = (10 - (sum % 10)) % 10;
    return digits[12] == check;
  }

  /// 校验 EAN-8 条形码（8 位数字）
  static bool isValidEan8(String code) {
    if (!RegExp(r'^\d{8}$').hasMatch(code)) return false;
    final digits = code.split('').map(int.parse).toList();
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      sum += digits[i] * (i.isEven ? 3 : 1);
    }
    final check = (10 - (sum % 10)) % 10;
    return digits[7] == check;
  }

  /// 校验 UPC-A 条形码（12 位数字）
  static bool isValidUpcA(String code) {
    if (!RegExp(r'^\d{12}$').hasMatch(code)) return false;
    final digits = code.split('').map(int.parse).toList();
    var sum = 0;
    for (var i = 0; i < 11; i++) {
      sum += digits[i] * (i.isEven ? 3 : 1);
    }
    final check = (10 - (sum % 10)) % 10;
    return digits[11] == check;
  }

  /// 综合校验条码格式与校验位（支持 EAN-13 / EAN-8 / UPC-A）
  static bool isValid(String code) {
    final t = code.trim();
    if (t.length == 13) return isValidEan13(t);
    if (t.length == 8) return isValidEan8(t);
    if (t.length == 12) return isValidUpcA(t);
    // 其它长度（如 CODE-128 工业码）只要是纯字符且长度合理即可
    return t.length >= 4 && t.length <= 30;
  }

  /// 把扫描/手输得到的商品码统一成 13 位商品码；校验位不合法或不是食品码时返回 null。
  /// UPC-A(12) 前置补 0 即为 EAN-13；EAN-8 保持原样（种子库均为 13 位，不做臆造扩展）。
  static String? toProductCode(String raw) {
    final t = raw.trim();
    if (t.length == 13 && isValidEan13(t)) return t;
    if (t.length == 12 && isValidUpcA(t)) return '0$t';
    if (t.length == 8 && isValidEan8(t)) return t;
    return null;
  }
}
