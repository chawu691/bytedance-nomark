import '../lib/services/doubao_parser.dart';

void main() async {
  const url = 'https://www.doubao.com/thread/w3de509c584a4e3da';
  print('=== 视频测试: $url ===');
  try {
    final result = await parseMedia(url);
    print('图片: ${result.images.length}');
    print('视频: ${result.videos.length}');
    for (var i = 0; i < result.videos.length; i++) {
      final v = result.videos[i];
      print('  [${i + 1}] ${v.width}x${v.height} ${v.duration}s');
      print('       url: ${v.url.substring(0, v.url.length > 80 ? 80 : v.url.length)}');
      print('       cover: ${v.coverUrl}');
    }
  } catch (e) {
    print('失败: $e');
  }
}