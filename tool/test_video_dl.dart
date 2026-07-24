import 'dart:io';
import 'package:dio/dio.dart';
import '../lib/services/doubao_parser.dart';

void main() async {
  // 1. 重新解析获取新鲜视频 URL
  const threadUrl = 'https://www.doubao.com/thread/w3de509c584a4e3da';
  print('=== Step 1: 解析视频 ===');
  final result = await parseMedia(threadUrl);
  print('视频数量: ${result.videos.length}');
  for (var i = 0; i < result.videos.length; i++) {
    final v = result.videos[i];
    print('  [${i + 1}] ${v.width}x${v.height} ${v.duration}s');
    print('       url: ${v.url.substring(0, v.url.length > 80 ? 80 : v.url.length)}...');
  }
  if (result.videos.isEmpty) {
    print('没有视频，退出');
    return;
  }

  final video = result.videos.first;
  final url = video.url;

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    followRedirects: true,
  ));

  // 2. 测试 HEAD 请求
  print('\n=== Step 2: HEAD 请求（无 referer）===');
  try {
    final resp = await dio.head(url, options: Options(
      headers: {'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
    ));
    print('Status: ${resp.statusCode}');
    print('Content-Type: ${resp.headers.value('content-type')}');
    print('Content-Length: ${resp.headers.value('content-length')}');
    print('Redirects: ${resp.redirects.length}');
    for (final r in resp.redirects) {
      print('  -> ${r.statusCode} ${r.location}');
    }
  } catch (e) {
    print('Error: $e');
  }

  // 3. 测试 HEAD 请求（带 referer）
  print('\n=== Step 3: HEAD 请求（带 referer）===');
  try {
    final resp = await dio.head(url, options: Options(
      headers: {
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'referer': 'https://www.doubao.com/',
      },
    ));
    print('Status: ${resp.statusCode}');
    print('Content-Type: ${resp.headers.value('content-type')}');
  } catch (e) {
    print('Error: $e');
  }

  // 4. 测试 GET 下载前 1MB
  print('\n=== Step 4: GET 下载前 1MB（带 referer）===');
  int receivedTotal = 0;
  try {
    await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'referer': 'https://www.doubao.com/',
        },
      ),
      onReceiveProgress: (r, t) {
        receivedTotal = t;
        if (r > 1000000) {
          throw DioException(requestOptions: RequestOptions(path: ''));
        }
      },
    );
  } on DioException catch (e) {
    if (receivedTotal > 0) {
      print('Download works! Total size: ${receivedTotal} bytes');
    } else {
      print('Error: ${e.message}');
    }
  } catch (e) {
    print('Error: $e');
  }

  // 5. 测试 dio.download 方法（模拟 app 实际行为）
  print('\n=== Step 5: dio.download 方法 ===');
  try {
    final cacheDir = Directory.systemTemp.path;
    final filename = 'test_video.mp4';
    final filePath = '$cacheDir/$filename';
    await dio.download(
      url,
      filePath,
      options: Options(
        headers: {
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'referer': 'https://www.doubao.com/',
        },
      ),
      onReceiveProgress: (r, t) {
        if (r % 100000 < 50000) {
          print('  Progress: $r / $t');
        }
      },
    );
    final file = File(filePath);
    print('Download success! Size: ${await file.length()} bytes');
    await file.delete();
  } catch (e) {
    print('Error: $e');
  }

  // 6. 测试 filename 提取
  print('\n=== Step 6: filename 提取测试 ===');
  _testFilename(url);
  _testFilename('https://example.com/path/to/video.mp4');
  _testFilename('https://example.com/path/to/video.mp4?token=abc');

  dio.close();
}

void _testFilename(String url) {
  final uri = Uri.parse(url);
  final seg = uri.pathSegments.lastOrNull ?? 'media';
  final name = seg.length > 32 ? seg.substring(0, 32) : seg;
  print('  URL: ${url.substring(0, url.length > 60 ? 60 : url.length)}...');
  print('  -> filename: "$name" (has ext: ${name.contains('.')})');
}