// 豆包无水印图片解析
// 对接豆包新 API：POST /alice/message/share/get
// 同时作为统一解析入口：路由豆包/千问/抖音/TikTok 链接到对应解析器
import 'dart:convert';

import 'package:dio/dio.dart';

import 'douyin_tiktok_parser.dart';

/// 解析出的图片信息
class ParsedImage {
  final String url;
  final int? width;
  final int? height;
  final String? filename;

  const ParsedImage({
    required this.url,
    this.width,
    this.height,
    this.filename,
  });

  @override
  String toString() => 'ParsedImage(url=$url, ${width}x$height)';
}

/// 解析出的视频信息
class ParsedVideo {
  final String url; // download_url 无水印直链
  final String? coverUrl; // 封面缩略图
  final String? vid;
  final int? width;
  final int? height;
  final double? duration; // 秒
  final String? videoType; // mp4

  const ParsedVideo({
    required this.url,
    this.coverUrl,
    this.vid,
    this.width,
    this.height,
    this.duration,
    this.videoType,
  });

  @override
  String toString() => 'ParsedVideo(url=$url, ${width}x$height, ${duration}s)';
}

class ParseException implements Exception {
  final String message;
  ParseException(this.message);
  @override
  String toString() => message;
}

const _headers = {
  'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
  'user-agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0',
  'origin': 'https://www.doubao.com',
  'referer': 'https://www.doubao.com/',
  'content-type': 'application/json',
};

const _qianwenHeaders = {
  'user-agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0',
  'origin': 'https://www.qianwen.com',
  'content-type': 'application/json',
};

/// 统一解析入口：同时提取图片和视频
/// 自动检测豆包/千问/抖音/TikTok 链接并路由到对应解析器
/// 输入：豆包 thread 链接 / 千问 share/chat 链接 / 抖音视频/笔记 / TikTok 视频/图文
/// 输出：(images, videos)
Future<({List<ParsedImage> images, List<ParsedVideo> videos})> parseMedia(
    String url, {
      String douyinCookie = '',
      String tiktokCookie = '',
    }) async {
  // 抖音链接
  if (isDouyinUrl(url)) {
    return parseDouyinMedia(url, cookie: douyinCookie);
  }
  // TikTok 链接
  if (isTiktokUrl(url)) {
    return parseTiktokMedia(url, cookie: tiktokCookie);
  }
  // 千问链接
  if (url.contains('qianwen.com')) {
    return _parseQianwenMedia(url);
  }

  // 豆包链接
  final shareId = _extractShareId(url);
  if (shareId == null) {
    throw ParseException('链接格式不正确，请使用豆包对话链接（包含 /thread/）');
  }

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
  ));

  try {
    // 先尝试 alice API（图片线程），失败则回退 samantha（视频线程）
    Map<String, dynamic>? body = await _callAliceApi(dio, shareId);
    body ??= await _callSamanthaApi(dio, shareId);

    final data = body['data'];
    if (data is! Map) {
      throw ParseException('页面数据格式错误，无法解析');
    }

    final snapshot = data['message_snapshot'];
    if (snapshot is! Map) {
      throw ParseException('页面数据格式错误，无法解析');
    }

    final messageList = snapshot['message_list'];
    if (messageList is! List) {
      throw ParseException('页面数据格式错误，无法解析');
    }

    final List<ParsedImage> images = [];
    final List<ParsedVideo> videos = [];
    for (final message in messageList) {
      if (message is! Map) continue;

      final contentBlocks = message['content_block'];
      if (contentBlocks is List) {
        _extractFromContentBlocks(contentBlocks, images);
        _extractVideosFromContentBlocks(contentBlocks, videos);
      }

      final ct = message['content_type'];
      if (ct == 2022) {
        _extractFromCreationFullContent(message, images, videos);
      }
    }

    return (images: images, videos: videos);
  } on DioException catch (e) {
    throw ParseException('网络请求失败，请检查网络连接: ${e.message}');
  } catch (e) {
    if (e is ParseException) rethrow;
    throw ParseException('解析失败: $e');
  } finally {
    dio.close();
  }
}

/// 图片解析（向后兼容）
Future<List<ParsedImage>> parseImages(String url,
    {String douyinCookie = '', String tiktokCookie = ''}) async {
  return (await parseMedia(url,
          douyinCookie: douyinCookie, tiktokCookie: tiktokCookie))
      .images;
}

/// 调用 alice API
Future<Map<String, dynamic>?> _callAliceApi(Dio dio, String shareId) async {
  final resp = await dio.post<Map<String, dynamic>>(
    'https://www.doubao.com/alice/message/share/get',
    data: {'share_id': shareId},
    options: Options(
      headers: _headers,
      responseType: ResponseType.json,
    ),
  );
  final body = resp.data;
  if (body == null) return null;
  if (body['code'] != 0) return null;
  return body;
}

/// 调用 samantha API
Future<Map<String, dynamic>> _callSamanthaApi(Dio dio, String shareId) async {
  final resp = await dio.post<Map<String, dynamic>>(
    'https://www.doubao.com/samantha/thread/share/snapshot/get',
    queryParameters: {'share_id': shareId, 'need_bot': '0'},
    options: Options(
      headers: _headers,
      responseType: ResponseType.json,
    ),
  );
  final body = resp.data;
  if (body == null) {
    throw ParseException('API 返回数据为空');
  }
  final code = body['code'];
  if (code != 0) {
    throw ParseException('API 返回错误 (code=$code): ${body['msg'] ?? ''}');
  }
  return body;
}

/// 路径 A: 从 content_block 中提取图片
void _extractFromContentBlocks(List<dynamic> blocks, List<ParsedImage> result) {
  for (final block in blocks) {
    if (block is! Map) continue;

    dynamic raw = block['content_v2'] ?? block['content'];
    if (raw is String) {
      raw = _decodeJson(raw);
    }
    if (raw is! Map) continue;

    final creationBlock = raw['creation_block'];
    if (creationBlock is! Map) continue;
    final creations = creationBlock['creations'];
    if (creations is! List) continue;

    for (final creation in creations) {
      if (creation is! Map) continue;
      final image = creation['image'];
      if (image is! Map) continue;
      final oriRaw = image['image_ori_raw'];
      if (oriRaw is! Map) continue;

      final imgUrl = oriRaw['url']?.toString();
      if (imgUrl == null || imgUrl.isEmpty) continue;

      result.add(ParsedImage(
        url: imgUrl.replaceAll('&amp;', '&'),
        width: _toInt(oriRaw['width']),
        height: _toInt(oriRaw['height']),
        filename: oriRaw['file_name']?.toString(),
      ));
    }
  }
}

/// 路径 B: 从 ext.creation_full_content 中提取图片和视频（content_type=2022）
void _extractFromCreationFullContent(
    Map message, List<ParsedImage> images, List<ParsedVideo> videos) {
  final ext = message['ext'];
  if (ext is! Map) return;

  dynamic raw = ext['creation_full_content'];
  if (raw is String) {
    raw = _decodeJson(raw);
  }
  if (raw is! Map) return;

  final creationInfo = raw['creation_info'];
  if (creationInfo is! Map) return;
  final taskInfo = creationInfo['task_info'];
  if (taskInfo is! Map) return;

  for (final entry in taskInfo.entries) {
    final task = entry.value;
    if (task is! Map) continue;
    if (task['status'] != 4) continue;

    final asset = task['asset'];
    if (asset is! Map) continue;

    // 提取图片
    final imageContent = asset['image_content'];
    if (imageContent is Map) {
      final imageInfo = imageContent['image_info'];
      if (imageInfo is Map) {
        final rawImage = imageInfo['raw_image'];
        if (rawImage is Map) {
          final imgUrl = rawImage['url']?.toString();
          if (imgUrl != null && imgUrl.isNotEmpty) {
            images.add(ParsedImage(
              url: imgUrl,
              width: _toInt(rawImage['width']),
              height: _toInt(rawImage['height']),
            ));
          }
        }
      }
    }

    // 提取视频
    final videoContent = asset['video_content'];
    if (videoContent is Map) {
      final videoInfo = videoContent['video_info'];
      if (videoInfo is Map) {
        final videoUrl = videoInfo['download_url']?.toString();
        if (videoUrl != null && videoUrl.isNotEmpty) {
          final cover = videoInfo['cover'];
          String? coverUrl;
          if (cover is Map) {
            final thumb = cover['image_thumb'];
            if (thumb is Map) {
              coverUrl = thumb['url']?.toString();
            }
          }
          videos.add(ParsedVideo(
            url: videoUrl,
            coverUrl: coverUrl,
            vid: videoInfo['vid']?.toString(),
            duration: _toDouble(videoInfo['duration']),
            videoType: videoInfo['video_type']?.toString(),
          ));
        }
      }
    }
  }
}

/// 路径 C: 从 content_block 中提取视频
void _extractVideosFromContentBlocks(
    List<dynamic> blocks, List<ParsedVideo> result) {
  for (final block in blocks) {
    if (block is! Map) continue;

    dynamic raw = block['content_v2'] ?? block['content'];
    if (raw is String) {
      raw = _decodeJson(raw);
    }
    if (raw is! Map) continue;

    final creationBlock = raw['creation_block'];
    if (creationBlock is! Map) continue;
    final creations = creationBlock['creations'];
    if (creations is! List) continue;

    for (final creation in creations) {
      if (creation is! Map) continue;
      final video = creation['video'];
      if (video is! Map) continue;
      // status=3 表示成功
      if (video['status'] != 3) continue;

      final videoUrl = video['download_url']?.toString();
      if (videoUrl == null || videoUrl.isEmpty) continue;

      // 封面图
      final cover = video['cover'];
      String? coverUrl;
      if (cover is Map) {
        final thumb = cover['image_thumb'];
        if (thumb is Map) {
          coverUrl = thumb['url']?.toString();
        }
      }

      result.add(ParsedVideo(
        url: videoUrl,
        coverUrl: coverUrl,
        vid: video['vid']?.toString(),
        width: _toInt(video['width']),
        height: _toInt(video['height']),
        duration: _toDouble(video['duration']),
        videoType: video['video_type']?.toString(),
      ));
    }
  }
}

/// 千问图片解析
Future<({List<ParsedImage> images, List<ParsedVideo> videos})>
    _parseQianwenMedia(String url) async {
  final shareId = url.split('?').first.split('chat/').last;
  if (shareId.isEmpty) {
    throw ParseException('链接格式不正确，请使用千问对话链接（包含 /share/chat/）');
  }

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
  ));

  try {
    final resp = await dio.post<Map<String, dynamic>>(
      'https://chat2-api.qianwen.com/api/v1/share/info',
      data: {'share_id': shareId, 'biz_id': 'ai_qwen'},
      options: Options(
        headers: _qianwenHeaders,
        responseType: ResponseType.json,
      ),
    );

    final body = resp.data;
    if (body == null) {
      throw ParseException('API 返回数据为空');
    }

    final data = body['data'];
    if (data is! Map) {
      throw ParseException('页面数据格式错误，无法解析');
    }

    final session = data['session'];
    if (session is! Map) {
      throw ParseException('页面数据格式错误，无法解析');
    }

    final recordList = session['record_list'];
    if (recordList is! List) {
      throw ParseException('页面数据格式错误，无法解析');
    }

    final List<ParsedImage> images = [];
    for (final record in recordList) {
      if (record is! Map) continue;
      final responseMessages = record['response_messages'];
      if (responseMessages is! List) continue;

      for (final msg in responseMessages) {
        if (msg is! Map) continue;
        if (msg['mime_type'] != 'multi_load/iframe') continue;
        if (msg['status'] != 'complete') continue;

        final metaData = msg['meta_data'];
        if (metaData is! Map) continue;
        final multiLoad = metaData['multi_load'];
        if (multiLoad is! List) continue;

        for (final item in multiLoad) {
          if (item is! Map) continue;
          final content = item['content'];
          if (content is! Map) continue;
          final displayList = content['display_list'];
          if (displayList is! List) continue;

          for (final d in displayList) {
            if (d is! Map) continue;
            final imgList = d['image'];
            if (imgList is! List || imgList.isEmpty) continue;
            final img = imgList[0];
            if (img is! Map) continue;

            final imgUrl = img['url']?.toString();
            if (imgUrl == null || imgUrl.isEmpty) continue;

            images.add(ParsedImage(
              url: imgUrl,
              width: _toInt(img['width']),
              height: _toInt(img['height']),
            ));
          }
        }
      }
    }

    return (images: images, videos: const <ParsedVideo>[]);
  } on DioException catch (e) {
    throw ParseException('网络请求失败，请检查网络连接: ${e.message}');
  } catch (e) {
    if (e is ParseException) rethrow;
    throw ParseException('解析失败: $e');
  } finally {
    dio.close();
  }
}

/// 从 URL 中提取 share_id（/thread/ 后面的部分）
String? _extractShareId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final segs = uri.pathSegments;
  final idx = segs.indexOf('thread');
  if (idx == -1 || idx + 1 >= segs.length) return null;

  return segs[idx + 1];
}

dynamic _decodeJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
