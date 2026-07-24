// TikTok Web API X-Bogus 签名算法 Dart 移植
// 原始算法: https://github.com/Evil0ctal/Douyin_TikTok_Download_API (Apache-2.0)
// 移植自 crawlers/douyin/web/xbogus.py，保留原始许可证与作者信息。
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// MD5 哈希，返回 16 字节十六进制字符串
String md5Hex(List<int> data) {
  final d = MD5Digest();
  d.update(Uint8List.fromList(data), 0, data.length);
  final out = Uint8List(d.digestSize);
  d.doFinal(out, 0);
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class XBogus {
  /// 与 Python 版完全一致的字符表
  static const String character =
      'Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=';

  final List<int> uaKey = [0x00, 0x01, 0x0c];

  final String userAgent;

  XBogus({String? userAgent})
      : userAgent = (userAgent == null || userAgent.isEmpty)
            ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0'
            : userAgent;

  /// 将十六进制字符串转换为整数数组。
  /// 长度 > 32 时直接按字符编码返回。
  List<int> md5StrToArray(String md5Str) {
    if (md5Str.length > 32) {
      return md5Str.codeUnits;
    }
    final array = <int>[];
    var idx = 0;
    while (idx < md5Str.length) {
      final hi = _hexCharToInt(md5Str.codeUnitAt(idx));
      final lo = _hexCharToInt(md5Str.codeUnitAt(idx + 1));
      array.add((hi << 4) | lo);
      idx += 2;
    }
    return array;
  }

  int _hexCharToInt(int codeUnit) {
    if (codeUnit >= 48 && codeUnit <= 57) return codeUnit - 48; // 0-9
    if (codeUnit >= 97 && codeUnit <= 102) return codeUnit - 87; // a-f
    if (codeUnit >= 65 && codeUnit <= 70) return codeUnit - 55; // A-F
    throw ArgumentError('Invalid hex char: $codeUnit');
  }

  /// 对 URL 路径进行多轮 MD5 加密
  List<int> md5Encrypt(String urlPath) {
    return md5StrToArray(
      md5Hex(
        md5StrToArray(
          md5Hex(urlPath.codeUnits),
        ),
      ),
    );
  }

  /// 第一次编码转换（参数命名与 Python 版对应）
  String encodingConversion(
    int a, int b, int c, int e, int d, int t, int f, int r, int n, int o,
    int i, int x2, int x, int u, int s, int l, int v, int h, int p,
  ) {
    final y = <int>[a, i, b, x2, c, x, e, u, d, s, t, l, f, v, r, h, n, p, o];
    // 等价 Python: bytes(y).decode("ISO-8859-1")
    return latin1.decode(y);
  }

  /// 第二次编码转换
  String encodingConversion2(int a, int b, String c) {
    return String.fromCharCode(a) + String.fromCharCode(b) + c;
  }

  /// RC4 加密，返回字节数组
  List<int> rc4EncryptBytes(List<int> key, List<int> data) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) % 256;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
    }
    var ii = 0;
    var jj = 0;
    final out = <int>[];
    for (final byte in data) {
      ii = (ii + 1) % 256;
      jj = (jj + s[ii]) % 256;
      final tmp = s[ii];
      s[ii] = s[jj];
      s[jj] = tmp;
      out.add(byte ^ s[(s[ii] + s[jj]) % 256]);
    }
    return out;
  }

  /// 位运算计算
  String calculation(int a1, int a2, int a3) {
    final x1 = (a1 & 255) << 16;
    final x2 = (a2 & 255) << 8;
    final x3 = x1 | x2 | a3;
    return character[(x3 & 16515072) >> 18] +
        character[(x3 & 258048) >> 12] +
        character[(x3 & 4032) >> 6] +
        character[x3 & 63];
  }

  /// 获取 X-Bogus 值
  ///
  /// 返回 (paramsWithXbogus, xbogusOnly, userAgent)
  ({String params, String xb, String ua}) getXBogus(String urlPath) {
    // array1: RC4(UA) -> base64 -> md5 -> md5StrToArray
    final uaEnc = rc4EncryptBytes(uaKey, latin1.encode(userAgent));
    final uaB64 = base64.encode(uaEnc);
    final array1 = md5StrToArray(md5Hex(uaB64.codeUnits));

    // array2: md5(md5StrToArray("d41d8cd98f00b204e9800998ecf8427e"))
    final array2 = md5StrToArray(
      md5Hex(md5StrToArray('d41d8cd98f00b204e9800998ecf8427e')),
    );

    final urlPathArray = md5Encrypt(urlPath);

    final timer = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const ct = 536919696;

    final newArray = <int>[
      64,
      1, // 0.00390625 取 int
      12,
      urlPathArray[14],
      urlPathArray[15],
      array2[14],
      array2[15],
      array1[14],
      array1[15],
      (timer >> 24) & 255,
      (timer >> 16) & 255,
      (timer >> 8) & 255,
      timer & 255,
      (ct >> 24) & 255,
      (ct >> 16) & 255,
      (ct >> 8) & 255,
      ct & 255,
    ];

    // Python 中 new_array[1] = 0.00390625 是 float，但在 xor 时 int(b) 取 0
    // 这里在 list 里已经写 1（int），但 Python 行为是 int(0.00390625)=0
    // 修正：与 Python int(b) 行为保持一致
    newArray[1] = 0;

    var xorResult = newArray[0];
    for (var i = 1; i < newArray.length; i++) {
      xorResult ^= newArray[i];
    }
    newArray.add(xorResult);

    // 拆 array3/array4
    final array3 = <int>[];
    final array4 = <int>[];
    for (var idx = 0; idx < newArray.length; idx += 2) {
      array3.add(newArray[idx]);
      if (idx + 1 < newArray.length) {
        array4.add(newArray[idx + 1]);
      }
    }
    final mergeArray = [...array3, ...array4];

    // encoding_conversion(*merge_array) -> latin1 bytes -> rc4("ÿ") -> latin1 string
    final mergedStr = encodingConversion(
      mergeArray[0], mergeArray[1], mergeArray[2], mergeArray[3], mergeArray[4],
      mergeArray[5], mergeArray[6], mergeArray[7], mergeArray[8], mergeArray[9],
      mergeArray[10], mergeArray[11], mergeArray[12], mergeArray[13],
      mergeArray[14], mergeArray[15], mergeArray[16], mergeArray[17], mergeArray[18],
    );
    final mergedBytes = latin1.encode(mergedStr);
    // "ÿ".encode("ISO-8859-1") = [0xFF]
    final rc4Out = rc4EncryptBytes([0xFF], mergedBytes);
    final garbledCode = encodingConversion2(2, 255, latin1.decode(rc4Out));

    // 每 3 个字符做一次 calculation
    var xb = '';
    var idx = 0;
    while (idx < garbledCode.length) {
      xb += calculation(
        garbledCode.codeUnitAt(idx),
        garbledCode.codeUnitAt(idx + 1),
        garbledCode.codeUnitAt(idx + 2),
      );
      idx += 3;
    }

    final paramsWithXb = '$urlPath&X-Bogus=$xb';
    return (params: paramsWithXb, xb: xb, ua: userAgent);
  }
}

/// 顶层便捷函数：返回仅 X-Bogus 值（已 URL 编码）
String generateXBogus(String urlPath, String userAgent) {
  final result = XBogus(userAgent: userAgent).getXBogus(urlPath);
  return result.xb;
}
