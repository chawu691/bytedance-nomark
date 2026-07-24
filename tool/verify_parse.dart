// 验证豆包图片解析移植是否正确
// 运行: dart run tool/verify_parse.dart
import 'dart:io';

import '../lib/services/doubao_parser.dart';

void main() async {
  print('=== 豆包图片解析验证 ===\n');

  // 测试链接：豆包对话 thread
  const testUrl = 'https://www.doubao.com/thread/aef4c7a4c78c2';

  print('测试链接: $testUrl');
  print('正在解析...\n');

  try {
    final images = await parseImages(testUrl);
    print('解析成功！共 ${images.length} 张图片:\n');

    var ok = 0;
    for (final img in images) {
      final issues = <String>[];
      if (img.url.isEmpty) issues.add('URL 为空');
      if (img.url.contains('&amp;')) issues.add('URL 含 &amp; 残留');
      if (img.width == null) issues.add('宽度缺失');
      if (img.height == null) issues.add('高度缺失');

      if (issues.isEmpty) {
        ok++;
        print('  [$ok]  ${img.url}');
        print('       尺寸: ${img.width}x${img.height}');
      } else {
        print('  [FAIL] ${issues.join(", ")}');
      }
    }

    // 检查首图是否可访问
    if (images.isNotEmpty) {
      print('\n--- 首图 HTTP 可达性检查 ---');
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        final req = await client.getUrl(Uri.parse(images.first.url));
        req.headers.set('user-agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
        final resp = await req.close();
        print('  首图 HTTP ${resp.statusCode}');
        client.close();
      } catch (e) {
        print('  首图 HTTP ERROR: $e');
      }
    }

    print('\n=== 结果: $ok/${images.length} 通过 ===');
    if (ok == images.length && images.isNotEmpty) {
      print('全部通过！');
      exit(0);
    } else {
      exit(1);
    }
  } on ParseException catch (e) {
    print('解析失败: $e');
    exit(1);
  } catch (e) {
    print('异常: $e');
    exit(1);
  }
}