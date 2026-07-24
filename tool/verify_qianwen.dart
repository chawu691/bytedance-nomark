import '../lib/services/doubao_parser.dart';

void main() async {
  const url = 'https://www.qianwen.com/share/chat/1b7641042a7c4f2fae8111f732c31f7f';
  print('=== 千问测试: $url ===');
  try {
    final result = await parseMedia(url);
    print('图片: ${result.images.length}');
    for (var i = 0; i < result.images.length; i++) {
      final img = result.images[i];
      print('  [${i + 1}] ${img.width}x${img.height}');
      print('       ${img.url.substring(0, img.url.length > 80 ? 80 : img.url.length)}');
    }
    print('视频: ${result.videos.length}');
  } catch (e) {
    print('失败: $e');
  }
}