// 抖音 Web API a_bogus 签名算法 Dart 移植
// 原始算法: https://github.com/JoeanAmier/TikTokDownloader (GPL-3.0)
// 经 https://github.com/Evil0ctal/Douyin_TikTok_Download_API (Apache-2.0) 修改
// 本文件保留原始许可证与作者信息。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// SM3 哈希，返回 32 字节整数列表
List<int> sm3Hash(List<int> data) {
  final digest = SM3Digest();
  final input = Uint8List.fromList(data);
  digest.update(input, 0, input.length);
  final out = Uint8List(digest.digestSize);
  digest.doFinal(out, 0);
  return out;
}

/// 将字符串编码为字节列表后做 SM3
List<int> sm3OfString(String s) => sm3Hash(utf8.encode(s));

/// URL 编码（与 Python urllib.parse.urlencode 等价，用于 dict）
String urlencodeMap(Map<String, dynamic> params) {
  return params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
      .join('&');
}

/// 计算请求体的 SM3 哈希值，并将结果转换为整数数组
/// 等价于 Python 的 sm3_to_array
List<int> _sm3ToArray(dynamic data) {
  List<int> bytes;
  if (data is String) {
    bytes = utf8.encode(data);
  } else if (data is List<int>) {
    bytes = data;
  } else {
    throw ArgumentError('data must be String or List<int>');
  }
  return sm3Hash(bytes);
}

class ABogus {
  static final RegExp _filter = RegExp(r'%([0-9A-F]{2})');
  static const List<int> _arguments = [0, 1, 14];
  static const String _endString = 'cus';
  static const String _browserDefault =
      '1536|742|1536|864|0|0|0|0|1536|864|1536|864|1536|742|24|24|MacIntel';
  static const List<int> _reg = [
    1937774191,
    1226093241,
    388252375,
    3666478592,
    2842636476,
    372324522,
    3817729613,
    2969243214,
  ];
  static const Map<String, String> _str = {
    's0': 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=',
    's1': 'Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',
    's2': 'Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',
    's3': 'ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe',
    's4': 'Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe',
  };

  // ua_code: 对应 Python 中硬编码的 Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.212 Safari/537.36
  static const List<int> _uaCode = [
    76,
    98,
    15,
    131,
    97,
    245,
    224,
    133,
    122,
    199,
    241,
    166,
    79,
    34,
    90,
    191,
    128,
    126,
    122,
    98,
    66,
    11,
    14,
    40,
    49,
    110,
    110,
    173,
    67,
    96,
    138,
    252
  ];

  List<int> chunk = [];
  int size = 0;
  List<int> reg = List.from(_reg);
  late String browser;
  late int browserLen;
  late List<int> browserCode;

  final _random = Random();

  ABogus() {
    browser = _browserDefault;
    browserLen = browser.length;
    browserCode = browser.codeUnits;
  }

  // ───────────────────────── 随机列表生成 ─────────────────────────

  List<int> list1(num? randomNum, {int a = 170, int b = 85, int c = 45}) {
    return randomList(randomNum, a, b, 1, 2, 5, c & a);
  }

  List<int> list2(num? randomNum, {int a = 170, int b = 85}) {
    return randomList(randomNum, a, b, 1, 0, 0, 0);
  }

  List<int> list3(num? randomNum, {int a = 170, int b = 85}) {
    return randomList(randomNum, a, b, 1, 0, 5, 0);
  }

  List<int> randomList(
    num? a, [
    int b = 170,
    int c = 85,
    int d = 0,
    int e = 0,
    int f = 0,
    int g = 0,
  ]) {
    final ri = (a ?? (_random.nextDouble() * 10000)).toInt();
    final v = <int>[
      ri,
      ri & 255,
      (ri >> 8) & 255,
    ];
    int s = (v[1] & b) | d;
    v.add(s);
    s = (v[1] & c) | e;
    v.add(s);
    s = (v[2] & b) | f;
    v.add(s);
    s = (v[2] & c) | g;
    v.add(s);
    return v.sublist(v.length - 4);
  }

  // ───────────────────────── 字符串生成 ─────────────────────────

  String fromCharCode(List<int> codes) {
    return String.fromCharCodes(codes);
  }

  String generateString1(num? r1, num? r2, num? r3) {
    return fromCharCode(list1(r1)) +
        fromCharCode(list2(r2)) +
        fromCharCode(list3(r3));
  }

  String generateString2(
    String urlParams, {
    String method = 'GET',
    int startTime = 0,
    int endTime = 0,
  }) {
    final a = generateString2List(urlParams, method, startTime, endTime);
    final e = endCheckNum(a);
    a.addAll(browserCode);
    a.add(e);
    return rc4Encrypt(fromCharCode(a), 'y');
  }

  List<int> generateString2List(
    String urlParams, [
    String method = 'GET',
    int startTime = 0,
    int endTime = 0,
  ]) {
    startTime = startTime != 0
        ? startTime
        : DateTime.now().millisecondsSinceEpoch;
    endTime = endTime != 0 ? endTime : (startTime + _randint(4, 8));
    final paramsArray = generateParamsCode(urlParams);
    final methodArray = generateMethodCode(method);
    return list4(
      (endTime >> 24) & 255,
      paramsArray[21],
      _uaCode[23],
      (endTime >> 16) & 255,
      paramsArray[22],
      _uaCode[24],
      (endTime >> 8) & 255,
      (endTime >> 0) & 255,
      (startTime >> 24) & 255,
      (startTime >> 16) & 255,
      (startTime >> 8) & 255,
      (startTime >> 0) & 255,
      methodArray[21],
      methodArray[22],
      (endTime ~/ 256 ~/ 256 ~/ 256 ~/ 256),
      (startTime ~/ 256 ~/ 256 ~/ 256 ~/ 256),
      browserLen,
    );
  }

  // ───────────────────────── SM3/压缩相关 ─────────────────────────

  /// 等价于 Python sm3_to_array（输入字符串或 List<int>）
  static List<int> sm3ToArray(dynamic data) => _sm3ToArray(data);

  /// generate_method_code: sm3_to_array(sm3_to_array(method + end_string))
  List<int> generateMethodCode([String method = 'GET']) {
    return sm3ToArray(sm3ToArray(method + _endString));
  }

  /// generate_params_code: sm3_to_array(sm3_to_array(params + end_string))
  List<int> generateParamsCode(String params) {
    return sm3ToArray(sm3ToArray(params + _endString));
  }

  static List<int> regToArray(List<int> a) {
    final o = List<int>.filled(32, 0);
    for (var i = 0; i < 8; i++) {
      var c = a[i];
      o[4 * i + 3] = c & 255;
      c >>= 8;
      o[4 * i + 2] = c & 255;
      c >>= 8;
      o[4 * i + 1] = c & 255;
      c >>= 8;
      o[4 * i] = c & 255;
    }
    return o;
  }

  void compress(List<int> a) {
    final f = generateF(a);
    final i = List<int>.from(reg);
    for (var o = 0; o < 64; o++) {
      var c = (de(i[0], 12) + i[4] + de(pe(o), o)) & 0xFFFFFFFF;
      c = de(c, 7);
      final s = (c ^ de(i[0], 12)) & 0xFFFFFFFF;

      var u = he(o, i[0], i[1], i[2]);
      u = (u + i[3] + s + f[o + 68]) & 0xFFFFFFFF;

      var b = ve(o, i[4], i[5], i[6]);
      b = (b + i[7] + c + f[o]) & 0xFFFFFFFF;

      i[3] = i[2];
      i[2] = de(i[1], 9);
      i[1] = i[0];
      i[0] = u;

      i[7] = i[6];
      i[6] = de(i[5], 19);
      i[5] = i[4];
      i[4] = (b ^ de(b, 9) ^ de(b, 17)) & 0xFFFFFFFF;
    }
    for (var l = 0; l < 8; l++) {
      reg[l] = (reg[l] ^ i[l]) & 0xFFFFFFFF;
    }
  }

  static List<int> generateF(List<int> e) {
    final r = List<int>.filled(132, 0);
    for (var t = 0; t < 16; t++) {
      r[t] = ((e[4 * t] << 24) |
              (e[4 * t + 1] << 16) |
              (e[4 * t + 2] << 8) |
              e[4 * t + 3]) &
          0xFFFFFFFF;
    }
    for (var n = 16; n < 68; n++) {
      var a = (r[n - 16] ^ r[n - 9] ^ de(r[n - 3], 15)) & 0xFFFFFFFF;
      a = (a ^ de(a, 15) ^ de(a, 23)) & 0xFFFFFFFF;
      r[n] = (a ^ de(r[n - 13], 7) ^ r[n - 6]) & 0xFFFFFFFF;
    }
    for (var n = 68; n < 132; n++) {
      r[n] = (r[n - 68] ^ r[n - 64]) & 0xFFFFFFFF;
    }
    return r;
  }

  static List<int> padArray(List<int> arr, [int length = 60]) {
    while (arr.length < length) {
      arr.add(0);
    }
    return arr;
  }

  void fill([int length = 60]) {
    final s = 8 * size;
    chunk.add(128);
    chunk = padArray(chunk, length);
    for (var i = 0; i < 4; i++) {
      chunk.add((s >> (8 * (3 - i))) & 255);
    }
  }

  static List<int> list4(
    int a,
    int b,
    int c,
    int d,
    int e,
    int f,
    int g,
    int h,
    int i,
    int j,
    int k,
    int m,
    int n,
    int o,
    int p,
    int q,
    int r,
  ) {
    return [
      44,
      a,
      0,
      0,
      0,
      0,
      24,
      b,
      n,
      0,
      c,
      d,
      0,
      0,
      0,
      1,
      0,
      239,
      e,
      o,
      f,
      g,
      0,
      0,
      0,
      0,
      h,
      0,
      0,
      14,
      i,
      j,
      0,
      k,
      m,
      3,
      p,
      1,
      q,
      1,
      r,
      0,
      0,
      0
    ];
  }

  static int endCheckNum(List<int> a) {
    var r = 0;
    for (final i in a) {
      r ^= i;
    }
    return r;
  }

  // ───────────────────────── 位运算辅助 ─────────────────────────

  static int de(int e, int r) {
    r %= 32;
    if (r == 0) return e & 0xFFFFFFFF;
    return ((e << r) & 0xFFFFFFFF) | ((e & 0xFFFFFFFF) >> (32 - r));
  }

  static int pe(int e) {
    return (0 <= e && e < 16) ? 2043430169 : 2055708042;
  }

  static int he(int e, int r, int t, int n) {
    if (0 <= e && e < 16) {
      return (r ^ t ^ n) & 0xFFFFFFFF;
    } else if (16 <= e && e < 64) {
      return ((r & t) | (r & n) | (t & n)) & 0xFFFFFFFF;
    }
    throw ArgumentError('he: e out of range: $e');
  }

  static int ve(int e, int r, int t, int n) {
    if (0 <= e && e < 16) {
      return (r ^ t ^ n) & 0xFFFFFFFF;
    } else if (16 <= e && e < 64) {
      return ((r & t) | (~r & n)) & 0xFFFFFFFF;
    }
    throw ArgumentError('ve: e out of range: $e');
  }

  static List<int> convertToCharCode(String a) {
    return a.codeUnits;
  }

  static List<List<int>> splitArray(List<int> arr, [int chunkSize = 64]) {
    final result = <List<int>>[];
    for (var i = 0; i < arr.length; i += chunkSize) {
      result.add(arr.sublist(i, i + chunkSize > arr.length ? arr.length : i + chunkSize));
    }
    return result;
  }

  static List<int> charCodeAt(String s) => s.codeUnits;

  // ───────────────────────── write / sum / reset ─────────────────────────

  void write(dynamic e) {
    if (e is String) {
      final decoded = decodeString(e);
      final codes = charCodeAt(decoded);
      size = codes.length;
      if (codes.length <= 64) {
        chunk = codes;
      } else {
        final chunks = splitArray(codes, 64);
        for (var i = 0; i < chunks.length - 1; i++) {
          compress(chunks[i]);
        }
        chunk = chunks.last;
      }
    } else if (e is List<int>) {
      size = e.length;
      if (e.length <= 64) {
        chunk = List.from(e);
      } else {
        final chunks = splitArray(e, 64);
        for (var i = 0; i < chunks.length - 1; i++) {
          compress(chunks[i]);
        }
        chunk = chunks.last;
      }
    }
  }

  void reset() {
    chunk = [];
    size = 0;
    reg = List.from(_reg);
  }

  List<int> sum(dynamic e, [int length = 60]) {
    reset();
    write(e);
    fill(length);
    compress(chunk);
    return regToArray(reg);
  }

  // ───────────────────────── 字符串解码 ─────────────────────────

  static String decodeString(String urlString) {
    return urlString.replaceAllMapped(_filter, (m) {
      final hex = m.group(1)!;
      return String.fromCharCode(int.parse(hex, radix: 16));
    });
  }

  // ───────────────────────── generate_result 系列 ─────────────────────────

  static String generateResultUnit(int n, String s) {
    var r = '';
    const shifts = [18, 12, 6, 0];
    const masks = [16515072, 258048, 4032, 63];
    for (var i = 0; i < 4; i++) {
      r += _str[s]![(n & masks[i]) >> shifts[i]];
    }
    return r;
  }

  static String generateResultEnd(String s, [String e = 's4']) {
    var r = '';
    final b = s.codeUnitAt(120) << 16;
    r += _str[e]![(b & 16515072) >> 18];
    r += _str[e]![(b & 258048) >> 12];
    r += '==';
    return r;
  }

  static String generateResult(String s, [String e = 's4']) {
    final r = <String>[];
    const shifts = [18, 12, 6, 0];
    const masks = [0xFC0000, 0x03F000, 0x0FC0, 0x3F];

    for (var i = 0; i < s.length; i += 3) {
      int n;
      if (i + 2 < s.length) {
        n = (s.codeUnitAt(i) << 16) |
            (s.codeUnitAt(i + 1) << 8) |
            s.codeUnitAt(i + 2);
      } else if (i + 1 < s.length) {
        n = (s.codeUnitAt(i) << 16) | (s.codeUnitAt(i + 1) << 8);
      } else {
        n = s.codeUnitAt(i) << 16;
      }
      for (var j = 0; j < 4; j++) {
        if (shifts[j] == 6 && i + 1 >= s.length) break;
        if (shifts[j] == 0 && i + 2 >= s.length) break;
        r.add(_str[e]![(n & masks[j]) >> shifts[j]]);
      }
    }
    final padCount = (4 - r.length % 4) % 4;
    if (padCount > 0) {
      r.add('=' * padCount);
    }
    return r.join();
  }

  // ───────────────────────── generate_args_code ─────────────────────────

  static List<int> generateArgsCode() {
    final a = <int>[];
    for (var j = 24; j >= 0; j -= 8) {
      a.add((_arguments[0] >> j) & 255);
    }
    a.add((_arguments[1] ~/ 256) & 255);
    a.add(_arguments[1] % 256);
    a.add((_arguments[1] >> 24) & 255);
    a.add((_arguments[1] >> 16) & 255);
    for (var j = 24; j >= 0; j -= 8) {
      a.add((_arguments[2] >> j) & 255);
    }
    return a.map((i) => i & 255).toList();
  }

  // ───────────────────────── RC4 ─────────────────────────

  static String rc4Encrypt(String plaintext, String key) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key.codeUnitAt(i % key.length)) % 256;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
    }
    var ii = 0;
    var jj = 0;
    final cipher = <int>[];
    for (var k = 0; k < plaintext.length; k++) {
      ii = (ii + 1) % 256;
      jj = (jj + s[ii]) % 256;
      final tmp = s[ii];
      s[ii] = s[jj];
      s[jj] = tmp;
      final t = (s[ii] + s[jj]) % 256;
      cipher.add(s[t] ^ plaintext.codeUnitAt(k));
    }
    return String.fromCharCodes(cipher);
  }

  // ───────────────────────── 主入口 ─────────────────────────

  String getValue(
    dynamic urlParams, {
    String method = 'GET',
    int startTime = 0,
    int endTime = 0,
    num? randomNum1,
    num? randomNum2,
    num? randomNum3,
  }) {
    final string1 = generateString1(randomNum1, randomNum2, randomNum3);
    final String paramsStr;
    if (urlParams is Map) {
      paramsStr = urlencodeMap(urlParams.cast<String, dynamic>());
    } else {
      paramsStr = urlParams as String;
    }
    final string2 =
        generateString2(paramsStr, method: method, startTime: startTime, endTime: endTime);
    final s = string1 + string2;
    return generateResult(s, 's4');
  }

  int _randint(int min, int max) {
    return min + _random.nextInt(max - min + 1);
  }
}

/// 生成 a_bogus 签名参数（已 URL 编码）
/// 等价于 Python: bogus.get_value(params) + quote(_, safe='')
String generateABogus(Map<String, dynamic> params, String userAgent) {
  final bogus = ABogus().getValue(params);
  return Uri.encodeComponent(bogus);
}
