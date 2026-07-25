// 抖音 / TikTok 视频/图文解析
// 参考: https://github.com/Evil0ctal/Douyin_TikTok_Download_API (Apache-2.0)
// 算法移植：abogus.dart（抖音 a_bogus）、xbogus.dart（TikTok X-Bogus）
// 约束：解析逻辑全部打包进 APP，不依赖自建服务器。
import 'package:dio/dio.dart';

import 'abogus.dart';
import 'doubao_parser.dart' show ParsedImage, ParsedVideo, ParseException;
import 'xbogus.dart';

// ───────────────────────── 常量 ─────────────────────────

const String _douyinUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/130.0.0.0 Safari/537.36';

const String _tiktokUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0';

const String _douyinDetailEndpoint =
    'https://www.douyin.com/aweme/v1/web/aweme/detail/';
const String _tiktokDetailEndpoint = 'https://www.tiktok.com/api/item/detail/';

// 抖音 aweme_type -> 类型映射（与 hybrid_crawler 一致）
// 0/4/51/55/58/61: video；2/68/150: image
bool _isImageType(int? awemeType) {
  return awemeType == 2 || awemeType == 68 || awemeType == 150;
}

// ───────────────────────── 抖音解析 ─────────────────────────

/// 解析抖音视频/图文链接
///
/// [url] 支持以下格式：
///   - https://www.douyin.com/video/{aweme_id}
///   - https://www.douyin.com/note/{aweme_id}
///   - https://v.douyin.com/{short}/  短链
///   - https://www.douyin.com/discover?modal_id={aweme_id}
///
/// [cookie] 抖音 Web Cookie（必需，可为空字符串，但可能被风控）
Future<({List<ParsedImage> images, List<ParsedVideo> videos})>
    parseDouyinMedia(
  String url, {
  String cookie = '',
  String msToken = '',
  Dio? dioOverride,
}) async {
  final dio = dioOverride ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 10,
      ));
  try {
    final awemeId = await _extractDouyinAwemeId(url, dio);
    if (awemeId == null) {
      throw ParseException('未能从抖音链接中提取 aweme_id');
    }

    final params = <String, dynamic>{
      'device_platform': 'webapp',
      'aid': '6383',
      'channel': 'channel_pc_web',
      'aweme_id': awemeId,
      'pc_client_type': '1',
      'version_code': '290100',
      'version_name': '29.1.0',
      'cookie_enabled': 'true',
      'screen_width': '1920',
      'screen_height': '1080',
      'browser_language': 'zh-CN',
      'browser_platform': 'Win32',
      'browser_name': 'Chrome',
      'browser_version': '130.0.0.0',
      'browser_online': 'true',
      'engine_name': 'Blink',
      'engine_version': '130.0.0.0',
      'os_name': 'Windows',
      'os_version': '10',
      'cpu_core_num': '12',
      'device_memory': '8',
      'platform': 'PC',
      'downlink': '10',
      'effective_type': '4g',
      'round_trip_time': '50',
      'msToken': msToken,
    };

    // 生成 a_bogus 签名
    final paramStr = _paramsToQueryString(params);
    final aBogus = ABogus().getValue(paramStr);
    params['a_bogus'] = aBogus;

    final headers = <String, dynamic>{
      'user-agent': _douyinUa,
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9',
      'referer': 'https://www.douyin.com/',
      'cookie': cookie,
    };

    final resp = await dio.get<dynamic>(
      _douyinDetailEndpoint,
      queryParameters: params,
      options: Options(headers: headers, responseType: ResponseType.json),
    );

    final body = resp.data;
    if (body is! Map) {
      throw ParseException('抖音 API 返回数据格式错误');
    }
    final detail = body['aweme_detail'];
    if (detail is! Map) {
      final status = body['status_code'];
      throw ParseException('抖音未返回作品详情（status_code=$status），请检查 Cookie 是否有效');
    }

    return _extractDouyinMedia(detail);
  } on DioException catch (e) {
    throw ParseException('抖音网络请求失败: ${e.message}');
  } catch (e) {
    if (e is ParseException) rethrow;
    throw ParseException('抖音解析失败: $e');
  } finally {
    if (dioOverride == null) dio.close();
  }
}

/// 从抖音分享/视频/笔记链接中提取 aweme_id（必要时跟随重定向）
Future<String?> _extractDouyinAwemeId(String url, Dio dio) async {
  // 已经包含 aweme_id 的常见形态
  final patterns = [
    RegExp(r'video/(\d+)'),
    RegExp(r'note/(\d+)'),
    RegExp(r'[?&]modal_id=(\d+)'),
    RegExp(r'[?&]vid=(\d+)'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(url);
    if (m != null) return m.group(1);
  }

  // 短链需要重定向
  if (!url.contains('douyin.com')) return null;
  try {
    final resp = await dio.get<dynamic>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 10,
        headers: {'user-agent': _douyinUa},
      ),
    );
    final finalUrl = resp.realUri.toString();
    for (final p in patterns) {
      final m = p.firstMatch(finalUrl);
      if (m != null) return m.group(1);
    }
    // 部分重定向在响应体中包含 aweme_id
    final body = resp.data?.toString() ?? '';
    final bodyMatch = RegExp(r'"aweme_id"\s*:\s*"(\d+)"').firstMatch(body);
    if (bodyMatch != null) return bodyMatch.group(1);
  } catch (_) {}
  return null;
}

({List<ParsedImage> images, List<ParsedVideo> videos}) _extractDouyinMedia(
    Map detail) {
  final images = <ParsedImage>[];
  final videos = <ParsedVideo>[];

  final awemeType = detail['aweme_type'];
  final video = detail['video'];
  final imageList = detail['images'];

  // 视频类型
  if (!_isImageType(awemeType is int ? awemeType : null) && video is Map) {
    final playAddr = video['play_addr'];
    if (playAddr is Map) {
      final urlList = playAddr['url_list'];
      String? videoUrl;
      if (urlList is List && urlList.isNotEmpty) {
        // play_addr 含 playwm，替换为 play 得到无水印
        videoUrl = urlList[0]?.toString().replaceAll('playwm', 'play');
      }
      final uri = playAddr['uri']?.toString();
      if (videoUrl == null || videoUrl.isEmpty) {
        if (uri != null && uri.isNotEmpty) {
          videoUrl =
              'https://aweme.snssdk.com/aweme/v1/play/?video_id=$uri&ratio=1080p&line=0';
        }
      }
      if (videoUrl != null && videoUrl.isNotEmpty) {
        String? coverUrl;
        final cover = video['cover'];
        if (cover is Map) {
          final coverUrlList = cover['url_list'];
          if (coverUrlList is List && coverUrlList.isNotEmpty) {
            coverUrl = coverUrlList[0]?.toString();
          }
        }
        // 音乐：music.play_url.url_list[0]，结构同 video.play_addr
        String? musicUrl;
        String? musicTitle;
        String? musicAuthor;
        final music = detail['music'];
        if (music is Map) {
          final musicPlayUrl = music['play_url'];
          if (musicPlayUrl is Map) {
            final musicUrlList = musicPlayUrl['url_list'];
            if (musicUrlList is List && musicUrlList.isNotEmpty) {
              musicUrl = musicUrlList[0]?.toString();
            }
          }
          musicTitle = music['title']?.toString();
          musicAuthor = music['author']?.toString();
        }
        videos.add(ParsedVideo(
          url: videoUrl,
          coverUrl: coverUrl,
          vid: uri,
          width: _toInt(video['width']),
          height: _toInt(video['height']),
          duration: (_toDouble(video['duration']) ?? 0) / 1000.0,
          videoType: 'mp4',
          musicUrl: musicUrl,
          musicTitle: musicTitle,
          musicAuthor: musicAuthor,
        ));
      }
    }
  }

  // 图文类型
  if (imageList is List) {
    for (final img in imageList) {
      if (img is! Map) continue;
      final urlList = img['url_list'];
      if (urlList is List && urlList.isNotEmpty) {
        final imgUrl = urlList[0]?.toString();
        if (imgUrl != null && imgUrl.isNotEmpty) {
          images.add(ParsedImage(
            url: imgUrl,
            width: _toInt(img['width']),
            height: _toInt(img['height']),
          ));
        }
      }
    }
  }

  return (images: images, videos: videos);
}

// ───────────────────────── TikTok 解析 ─────────────────────────

/// 解析 TikTok 视频/图文链接
///
/// [url] 支持以下格式：
///   - https://www.tiktok.com/@user/video/{itemId}
///   - https://www.tiktok.com/@user/photo/{itemId}
///   - https://vm.tiktok.com/{short}/ 短链
///
/// [cookie] TikTok Web Cookie（含 msToken/ttwid/odin_tt 等，可空但可能失败）
Future<({List<ParsedImage> images, List<ParsedVideo> videos})>
    parseTiktokMedia(
  String url, {
  String cookie = '',
  String msToken = '',
  Dio? dioOverride,
}) async {
  final dio = dioOverride ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 10,
      ));
  try {
    final itemId = await _extractTiktokItemId(url, dio);
    if (itemId == null) {
      throw ParseException('未能从 TikTok 链接中提取 itemId');
    }

    final params = <String, dynamic>{
      'WebIdLastTime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'aid': '1988',
      'app_language': 'en',
      'app_name': 'tiktok_web',
      'browser_language': 'en-US',
      'browser_name': 'Mozilla',
      'browser_online': 'true',
      'browser_platform': 'Win32',
      'browser_version': '5.0%20(Windows)',
      'channel': 'tiktok_web',
      'cookie_enabled': 'true',
      'device_id': '7380187414842836523',
      'odinId': '7404669909585003563',
      'device_platform': 'web_pc',
      'focus_state': 'true',
      'from_page': 'user',
      'history_len': '4',
      'is_fullscreen': 'false',
      'is_page_visible': 'true',
      'language': 'en',
      'os': 'windows',
      'priority_region': 'US',
      'referer': '',
      'region': 'US',
      'root_referer': 'https%3A%2F%2Fwww.tiktok.com%2F',
      'screen_height': '1080',
      'screen_width': '1920',
      'webcast_language': 'en',
      'tz_name': 'America%2FTijuana',
      'itemId': itemId,
      'msToken': msToken,
    };

    final paramStr = _paramsToQueryString(params);
    final xb = XBogus(userAgent: _tiktokUa).getXBogus(paramStr).xb;
    params['X-Bogus'] = xb;

    final headers = <String, dynamic>{
      'user-agent': _tiktokUa,
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'en-US,en;q=0.9',
      'referer': 'https://www.tiktok.com/',
      'cookie': cookie,
    };

    final resp = await dio.get<dynamic>(
      _tiktokDetailEndpoint,
      queryParameters: params,
      options: Options(headers: headers, responseType: ResponseType.json),
    );

    final body = resp.data;
    if (body is! Map) {
      throw ParseException('TikTok API 返回数据格式错误');
    }
    // TikTok 详情接口字段名为 ItemModule.itemInfo.itemStruct 或直接 aweme_detail
    Map? detail = body['aweme_detail'] as Map?;
    if (detail == null) {
      final itemModule = body['ItemModule'];
      if (itemModule is Map) {
        final itemInfo = itemModule['itemInfo'];
        if (itemInfo is Map) {
          detail = itemInfo['itemStruct'] as Map?;
        }
      }
    }
    if (detail == null) {
      throw ParseException('TikTok 未返回作品详情，请检查 Cookie 或地区限制');
    }

    return _extractTiktokMedia(detail);
  } on DioException catch (e) {
    throw ParseException('TikTok 网络请求失败: ${e.message}');
  } catch (e) {
    if (e is ParseException) rethrow;
    throw ParseException('TikTok 解析失败: $e');
  } finally {
    if (dioOverride == null) dio.close();
  }
}

/// 从 TikTok 分享/视频/图文链接中提取 itemId
Future<String?> _extractTiktokItemId(String url, Dio dio) async {
  final patterns = [
    RegExp(r'video/(\d+)'),
    RegExp(r'photo/(\d+)'),
  ];
  // 长链直接匹配
  if (url.contains('tiktok.com') && url.contains('@')) {
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
  }

  // 短链重定向
  try {
    final resp = await dio.get<dynamic>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 10,
        headers: {'user-agent': _tiktokUa},
      ),
    );
    final finalUrl = resp.realUri.toString();
    for (final p in patterns) {
      final m = p.firstMatch(finalUrl);
      if (m != null) return m.group(1);
    }
  } catch (_) {}
  return null;
}

({List<ParsedImage> images, List<ParsedVideo> videos}) _extractTiktokMedia(
    Map detail) {
  final images = <ParsedImage>[];
  final videos = <ParsedVideo>[];

  final awemeType = detail['aweme_type'];
  final video = detail['video'];
  final imagePostInfo = detail['image_post_info'];

  // 视频
  if (!_isImageType(awemeType is int ? awemeType : null) && video is Map) {
    final playAddr = video['play_addr'];
    if (playAddr is Map) {
      final urlList = playAddr['url_list'];
      String? videoUrl;
      if (urlList is List && urlList.isNotEmpty) {
        videoUrl = urlList[0]?.toString();
      }
      // 高码率备选
      if (videoUrl == null || videoUrl.isEmpty) {
        final bitRate = video['bit_rate'];
        if (bitRate is List && bitRate.isNotEmpty) {
          final first = bitRate[0];
          if (first is Map) {
            final altAddr = first['play_addr'];
            if (altAddr is Map) {
              final altList = altAddr['url_list'];
              if (altList is List && altList.isNotEmpty) {
                videoUrl = altList[0]?.toString();
              }
            }
          }
        }
      }
      if (videoUrl != null && videoUrl.isNotEmpty) {
        String? coverUrl;
        final cover = video['cover'];
        if (cover is Map) {
          final coverUrlList = cover['url_list'];
          if (coverUrlList is List && coverUrlList.isNotEmpty) {
            coverUrl = coverUrlList[0]?.toString();
          }
        }
        // 音乐：music.play_url.url_list[0]，结构同 video.play_addr
        String? musicUrl;
        String? musicTitle;
        String? musicAuthor;
        final music = detail['music'];
        if (music is Map) {
          final musicPlayUrl = music['play_url'];
          if (musicPlayUrl is Map) {
            final musicUrlList = musicPlayUrl['url_list'];
            if (musicUrlList is List && musicUrlList.isNotEmpty) {
              musicUrl = musicUrlList[0]?.toString();
            }
          }
          musicTitle = music['title']?.toString();
          musicAuthor = music['author']?.toString();
        }
        videos.add(ParsedVideo(
          url: videoUrl,
          coverUrl: coverUrl,
          width: _toInt(video['width']),
          height: _toInt(video['height']),
          duration: (_toDouble(video['duration']) ?? 0) / 1000.0,
          videoType: 'mp4',
          musicUrl: musicUrl,
          musicTitle: musicTitle,
          musicAuthor: musicAuthor,
        ));
      }
    }
  }

  // 图文
  if (imagePostInfo is Map) {
    final imagesList = imagePostInfo['images'];
    if (imagesList is List) {
      for (final img in imagesList) {
        if (img is! Map) continue;
        final displayImage = img['display_image'];
        if (displayImage is Map) {
          final urlList = displayImage['url_list'];
          if (urlList is List && urlList.isNotEmpty) {
            final imgUrl = urlList[0]?.toString();
            if (imgUrl != null && imgUrl.isNotEmpty) {
              images.add(ParsedImage(
                url: imgUrl,
                width: _toInt(displayImage['width']),
                height: _toInt(displayImage['height']),
              ));
            }
          }
        }
      }
    }
  }

  return (images: images, videos: videos);
}

// ───────────────────────── 工具函数 ─────────────────────────

String _paramsToQueryString(Map<String, dynamic> params) {
  return params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
      .join('&');
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

/// 链接是否为抖音链接
bool isDouyinUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('douyin.com') || lower.contains('iesdouyin.com');
}

/// 链接是否为 TikTok 链接
bool isTiktokUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('tiktok.com') || lower.contains('vm.tiktok.com');
}
