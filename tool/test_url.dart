import '../lib/services/doubao_parser.dart';

void main() async {
  const url = 'https://www.doubao.com/thread/a1d680968d4e7';
  print('=== $url ===');
  try {
    final result = await parseMedia(url);
    print('图片: ${result.images.length}');
    for (var i = 0; i < result.images.length; i++) {
      final img = result.images[i];
      print('  [${i + 1}] ${img.width}x${img.height}');
      print('       ${img.url.substring(0, img.url.length > 80 ? 80 : img.url.length)}');
    }
    print('视频: ${result.videos.length}');
    for (var i = 0; i < result.videos.length; i++) {
      final v = result.videos[i];
      print('  [${i + 1}] ${v.duration}s ${v.videoType}');
      print('       ${v.url.substring(0, v.url.length > 80 ? 80 : v.url.length)}');
    }
  } catch (e) {
    print('失败: $e');
  }
}