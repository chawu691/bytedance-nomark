// Riverpod 状态层：解析 + 下载 + 设置 + 历史
// 手写 Notifier，不依赖 build_runner 生成代码
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../services/app_preferences.dart';
import '../services/doubao_parser.dart';
import '../services/platform_services.dart';

// ───────────────────────── Dio ─────────────────────────

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
  ));
  ref.onDispose(dio.close);
  return dio;
});

// ───────────────────────── 解析 ─────────────────────────

class ParseState {
  final bool isLoading;
  final List<ParsedImage>? images;
  final List<ParsedVideo>? videos;
  final String? error;
  final Set<String> selectedUrls; // 图片 URL
  final Set<String> selectedVideoUrls; // 视频 URL

  const ParseState({
    this.isLoading = false,
    this.images,
    this.videos,
    this.error,
    this.selectedUrls = const {},
    this.selectedVideoUrls = const {},
  });

  bool get isEmpty =>
      !isLoading && images == null && videos == null && error == null;
  int get imageSelected => selectedUrls.length;
  int get videoSelected => selectedVideoUrls.length;
  int get selectedCount => imageSelected + videoSelected;
  bool get isAllImageSelected =>
      images != null &&
      images!.isNotEmpty &&
      selectedUrls.length == images!.length;
  bool get isAllVideoSelected =>
      videos != null &&
      videos!.isNotEmpty &&
      selectedVideoUrls.length == videos!.length;
}

class ParseNotifier extends StateNotifier<ParseState> {
  ParseNotifier(this._settings) : super(const ParseState());

  final SettingsNotifier _settings;

  Future<void> parse(String url) async {
    url = url.trim();
    if (url.isEmpty) {
      state = const ParseState(error: '请输入链接');
      return;
    }
    state = const ParseState(isLoading: true);
    try {
      final settings = _settings.current;
      final result = await parseMedia(
        url,
        douyinCookie: settings.douyinCookie,
        tiktokCookie: settings.tiktokCookie,
        douyinMsToken: settings.douyinMsToken,
        tiktokMsToken: settings.tiktokMsToken,
      );
      final images = result.images;
      final videos = result.videos;
      if (images.isEmpty && videos.isEmpty) {
        state = const ParseState(error: '未解析到任何内容，请确认链接');
      } else {
        state = ParseState(
          images: images.isEmpty ? null : images,
          videos: videos.isEmpty ? null : videos,
          selectedUrls: images.map((e) => e.url).toSet(),
          selectedVideoUrls: videos.map((e) => e.url).toSet(),
        );
      }
    } on ParseException catch (e) {
      state = ParseState(error: e.message);
    } catch (e) {
      state = ParseState(error: '解析失败: $e');
    }
  }

  void toggleSelect(String url) {
    final images = state.images;
    if (images == null) return;
    final sel = state.selectedUrls.toSet();
    if (sel.contains(url)) {
      sel.remove(url);
    } else {
      sel.add(url);
    }
    state = _copyWith(selectedUrls: sel);
  }

  void selectAll() {
    final images = state.images;
    if (images == null) return;
    state = _copyWith(selectedUrls: images.map((e) => e.url).toSet());
  }

  void deselectAll() {
    state = _copyWith(selectedUrls: const {});
  }

  void toggleVideoSelect(String url) {
    final videos = state.videos;
    if (videos == null) return;
    final sel = state.selectedVideoUrls.toSet();
    if (sel.contains(url)) {
      sel.remove(url);
    } else {
      sel.add(url);
    }
    state = _copyWith(selectedVideoUrls: sel);
  }

  void selectAllVideos() {
    final videos = state.videos;
    if (videos == null) return;
    state = _copyWith(selectedVideoUrls: videos.map((e) => e.url).toSet());
  }

  void deselectAllVideos() {
    state = _copyWith(selectedVideoUrls: const {});
  }

  ParseState _copyWith(
      {Set<String>? selectedUrls, Set<String>? selectedVideoUrls}) {
    return ParseState(
      images: state.images,
      videos: state.videos,
      selectedUrls: selectedUrls ?? state.selectedUrls,
      selectedVideoUrls: selectedVideoUrls ?? state.selectedVideoUrls,
    );
  }

  void reset() => state = const ParseState();
}

final parseProvider = StateNotifierProvider<ParseNotifier, ParseState>((ref) {
  return ParseNotifier(ref.watch(settingsProvider.notifier));
});

// ───────────────────────── 下载 ─────────────────────────

enum DownloadStatus { idle, downloading, saving, done, error }

class DownloadTask {
  final String url;
  final double progress; // 0~1
  final DownloadStatus status;
  final String? error;

  const DownloadTask({
    required this.url,
    this.progress = 0,
    this.status = DownloadStatus.idle,
    this.error,
  });
}

class DownloadManager extends StateNotifier<Map<String, DownloadTask>> {
  DownloadManager(this._dio) : super(const {});

  final Dio _dio;
  final Map<String, Timer> _doneTimers = {};

  @override
  void dispose() {
    for (final timer in _doneTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> downloadSelected({
    required List<ParsedImage> images,
    required List<ParsedVideo> videos,
  }) async {
    if (isOhos) {
      await _downloadSelectedOhos(images, videos);
      return;
    }
    await Future.wait([
      ...images.map(download),
      ...videos.map(downloadVideo),
    ]);
  }

  /// 图片：下载到内存 → Gal.putImageBytes（无需临时文件）
  Future<void> download(ParsedImage image) async {
    if (isOhos) {
      await _downloadSelectedOhos([image], const []);
      return;
    }
    final url = image.url;
    if (state[url]?.status == DownloadStatus.downloading) return;
    _set(url, status: DownloadStatus.downloading);
    try {
      if (!await _ensureGalleryAccess()) {
        _set(url, status: DownloadStatus.error, error: '未授予相册权限');
        return;
      }

      final resp = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'user-agent': _pcUaHeader},
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          _set(url, progress: received / total);
        },
      );

      _set(url, status: DownloadStatus.saving, progress: 1);
      await Gal.putImageBytes(
        Uint8List.fromList(resp.data!),
        name: _filename(url),
      );
      _markDone(url);
    } catch (e) {
      _set(url, status: DownloadStatus.error, error: '$e');
    }
  }

  void _set(String url,
      {DownloadStatus status = DownloadStatus.downloading,
      double progress = 0,
      String? error}) {
    if (status != DownloadStatus.done) {
      _doneTimers.remove(url)?.cancel();
    }
    state = {
      ...state,
      url: DownloadTask(
          url: url, progress: progress, status: status, error: error),
    };
  }

  void _markDone(String url) {
    _set(url, status: DownloadStatus.done, progress: 1);
    _doneTimers.remove(url)?.cancel();
    _doneTimers[url] = Timer(const Duration(seconds: 3), () {
      _doneTimers.remove(url);
      if (state[url]?.status == DownloadStatus.done) {
        _set(url, status: DownloadStatus.idle);
      }
    });
    // 下载完成震动反馈（fire-and-forget）
    triggerHaptic(HapticLevel.medium);
  }

  /// 视频：下载到临时文件 → Gal.putVideo
  Future<void> downloadVideo(ParsedVideo video) async {
    if (isOhos) {
      await _downloadSelectedOhos(const [], [video]);
      return;
    }
    final url = video.url;
    if (state[url]?.status == DownloadStatus.downloading) return;
    _set(url, status: DownloadStatus.downloading);
    try {
      if (!await _ensureGalleryAccess()) {
        _set(url, status: DownloadStatus.error, error: '未授予相册权限');
        return;
      }

      final cacheDir = await getAppCacheDirectory();
      final ext = video.videoType ?? 'mp4';
      final filename = '${_filename(url)}.$ext';
      final filePath = _join(cacheDir.path, filename);

      await _dio.download(
        url,
        filePath,
        options: Options(
          headers: {
            'user-agent': _pcUaHeader,
            'referer': 'https://www.doubao.com/',
          },
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          _set(url, progress: received / total);
        },
      );

      _set(url, status: DownloadStatus.saving, progress: 1);
      await Gal.putVideo(filePath);
      _markDone(url);

      // 清理临时文件
      try {
        await File(filePath).delete();
      } catch (_) {}
    } catch (e) {
      _set(url, status: DownloadStatus.error, error: '$e');
    }
  }

  Future<bool> _ensureGalleryAccess() async {
    if (await Gal.hasAccess(toAlbum: true)) return true;
    return Gal.requestAccess(toAlbum: true);
  }

  Future<void> _downloadSelectedOhos(
    List<ParsedImage> images,
    List<ParsedVideo> videos,
  ) async {
    final cacheDir = await getAppCacheDirectory();
    await cacheDir.create(recursive: true);
    final downloaded = <_DownloadedOhosMedia>[];

    for (final image in images) {
      final file = await _downloadOhosFile(
        url: image.url,
        mediaType: 'image',
        extension: _imageExtension(image),
        cacheDir: cacheDir,
      );
      if (file != null) downloaded.add(file);
    }
    for (final video in videos) {
      final file = await _downloadOhosFile(
        url: video.url,
        mediaType: 'video',
        extension: video.videoType ?? 'mp4',
        cacheDir: cacheDir,
        referer: 'https://www.doubao.com/',
      );
      if (file != null) downloaded.add(file);
    }

    if (downloaded.isEmpty) return;
    for (final media in downloaded) {
      _set(media.url, status: DownloadStatus.saving, progress: 1);
    }

    try {
      final result = await saveOhosMediaBatch(
        downloaded.map((media) => media.file).toList(),
      );
      for (var i = 0; i < downloaded.length; i++) {
        final media = downloaded[i];
        if (result.cancelled) {
          _set(media.url, status: DownloadStatus.idle);
        } else if (result.savedIndices.contains(i)) {
          _markDone(media.url);
        } else {
          _set(
            media.url,
            status: DownloadStatus.error,
            error: result.errors[i] ?? '保存到相册失败',
          );
        }
      }
    } catch (error) {
      for (final media in downloaded) {
        _set(media.url, status: DownloadStatus.error, error: '$error');
      }
    } finally {
      for (final media in downloaded) {
        try {
          await File(media.file.path).delete();
        } catch (_) {}
      }
    }
  }

  Future<_DownloadedOhosMedia?> _downloadOhosFile({
    required String url,
    required String mediaType,
    required String extension,
    required Directory cacheDir,
    String? referer,
  }) async {
    if (state[url]?.status == DownloadStatus.downloading) return null;
    _set(url, status: DownloadStatus.downloading);
    final safeExtension = extension.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final fileName =
        '${_filename(url)}.${safeExtension.isEmpty ? 'bin' : safeExtension}';
    final path = _join(cacheDir.path, fileName);
    try {
      await _dio.download(
        url,
        path,
        options: Options(headers: {
          'user-agent': _pcUaHeader,
          if (referer != null) 'referer': referer,
        }),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _set(url, progress: received / total);
          }
        },
      );
      return _DownloadedOhosMedia(
        url: url,
        file: OhosMediaFile(
          path: path,
          mediaType: mediaType,
          fileName: fileName,
        ),
      );
    } catch (error) {
      _set(url, status: DownloadStatus.error, error: '$error');
      try {
        await File(path).delete();
      } catch (_) {}
      return null;
    }
  }

  String _imageExtension(ParsedImage image) {
    final candidate =
        image.filename ?? Uri.tryParse(image.url)?.pathSegments.last;
    if (candidate != null && candidate.contains('.')) {
      final extension = candidate.split('.').last.toLowerCase();
      if (const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension)) {
        return extension;
      }
    }
    return 'jpg';
  }

  String _join(String directory, String fileName) {
    return '$directory${Platform.pathSeparator}$fileName';
  }

  String _filename(String url) {
    final uri = Uri.parse(url);
    final seg = uri.pathSegments.lastOrNull ?? 'media';
    return seg.length > 32 ? seg.substring(0, 32) : seg;
  }
}

class _DownloadedOhosMedia {
  final String url;
  final OhosMediaFile file;

  const _DownloadedOhosMedia({
    required this.url,
    required this.file,
  });
}

final downloadProvider =
    StateNotifierProvider<DownloadManager, Map<String, DownloadTask>>((ref) {
  return DownloadManager(ref.watch(dioProvider));
});

const _pcUaHeader =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0';

// ───────────────────────── 设置 ─────────────────────────

class SettingsState {
  final String defaultMode; // 'doubao' | 'douyin'
  final bool autoParse;
  final bool darkMode;
  final String douyinCookie; // 抖音 Web Cookie 整串（原样保存备用）
  final String tiktokCookie; // TikTok Web Cookie 整串（原样保存备用）
  final bool loginGuideShown; // 是否已展示过登录引导
  final bool privacyNoticeShown; // 是否已选"不再提示"
  // 关键字段（从 Cookie 整串提取并单独持久化，供解析稳定使用）
  final String douyinMsToken;
  final String tiktokMsToken;
  final String douyinTtwid;
  final String tiktokTtwid;
  final String douyinSessionid;
  final String tiktokSessionid;
  final String douyinSvWebId;
  final String tiktokSvWebId;

  const SettingsState({
    this.defaultMode = 'doubao',
    this.autoParse = true,
    this.darkMode = false,
    this.douyinCookie = '',
    this.tiktokCookie = '',
    this.loginGuideShown = false,
    this.privacyNoticeShown = false,
    this.douyinMsToken = '',
    this.tiktokMsToken = '',
    this.douyinTtwid = '',
    this.tiktokTtwid = '',
    this.douyinSessionid = '',
    this.tiktokSessionid = '',
    this.douyinSvWebId = '',
    this.tiktokSvWebId = '',
  });

  SettingsState copyWith({
    String? defaultMode,
    bool? autoParse,
    bool? darkMode,
    String? douyinCookie,
    String? tiktokCookie,
    bool? loginGuideShown,
    bool? privacyNoticeShown,
    String? douyinMsToken,
    String? tiktokMsToken,
    String? douyinTtwid,
    String? tiktokTtwid,
    String? douyinSessionid,
    String? tiktokSessionid,
    String? douyinSvWebId,
    String? tiktokSvWebId,
  }) {
    return SettingsState(
      defaultMode: defaultMode ?? this.defaultMode,
      autoParse: autoParse ?? this.autoParse,
      darkMode: darkMode ?? this.darkMode,
      douyinCookie: douyinCookie ?? this.douyinCookie,
      tiktokCookie: tiktokCookie ?? this.tiktokCookie,
      loginGuideShown: loginGuideShown ?? this.loginGuideShown,
      privacyNoticeShown: privacyNoticeShown ?? this.privacyNoticeShown,
      douyinMsToken: douyinMsToken ?? this.douyinMsToken,
      tiktokMsToken: tiktokMsToken ?? this.tiktokMsToken,
      douyinTtwid: douyinTtwid ?? this.douyinTtwid,
      tiktokTtwid: tiktokTtwid ?? this.tiktokTtwid,
      douyinSessionid: douyinSessionid ?? this.douyinSessionid,
      tiktokSessionid: tiktokSessionid ?? this.tiktokSessionid,
      douyinSvWebId: douyinSvWebId ?? this.douyinSvWebId,
      tiktokSvWebId: tiktokSvWebId ?? this.tiktokSvWebId,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(
    this._prefs, {
    Future<Directory> Function()? cacheDirectory,
  })  : _cacheDirectory = cacheDirectory ?? getAppCacheDirectory,
        super(const SettingsState()) {
    _load();
  }

  final AppPreferences _prefs;
  final Future<Directory> Function() _cacheDirectory;

  SettingsState get current => state;

  static const _kMode = 'settings_defaultMode';
  static const _kAutoParse = 'settings_autoParse';
  static const _kDarkMode = 'settings_darkMode';
  static const _kDouyinCookie = 'settings_douyinCookie';
  static const _kTiktokCookie = 'settings_tiktokCookie';
  static const _kLoginGuideShown = 'settings_loginGuideShown';
  static const _kPrivacyNoticeShown = 'settings_privacyNoticeShown';
  static const _kDouyinMsToken = 'settings_douyinMsToken';
  static const _kTiktokMsToken = 'settings_tiktokMsToken';
  static const _kDouyinTtwid = 'settings_douyinTtwid';
  static const _kTiktokTtwid = 'settings_tiktokTtwid';
  static const _kDouyinSessionid = 'settings_douyinSessionid';
  static const _kTiktokSessionid = 'settings_tiktokSessionid';
  static const _kDouyinSvWebId = 'settings_douyinSvWebId';
  static const _kTiktokSvWebId = 'settings_tiktokSvWebId';

  void _load() {
    state = SettingsState(
      defaultMode: _prefs.getString(_kMode) ?? 'doubao',
      autoParse: _prefs.getBool(_kAutoParse) ?? true,
      darkMode: _prefs.getBool(_kDarkMode) ?? false,
      douyinCookie: _prefs.getString(_kDouyinCookie) ?? '',
      tiktokCookie: _prefs.getString(_kTiktokCookie) ?? '',
      loginGuideShown: _prefs.getBool(_kLoginGuideShown) ?? false,
      privacyNoticeShown: _prefs.getBool(_kPrivacyNoticeShown) ?? false,
      douyinMsToken: _prefs.getString(_kDouyinMsToken) ?? '',
      tiktokMsToken: _prefs.getString(_kTiktokMsToken) ?? '',
      douyinTtwid: _prefs.getString(_kDouyinTtwid) ?? '',
      tiktokTtwid: _prefs.getString(_kTiktokTtwid) ?? '',
      douyinSessionid: _prefs.getString(_kDouyinSessionid) ?? '',
      tiktokSessionid: _prefs.getString(_kTiktokSessionid) ?? '',
      douyinSvWebId: _prefs.getString(_kDouyinSvWebId) ?? '',
      tiktokSvWebId: _prefs.getString(_kTiktokSvWebId) ?? '',
    );
  }

  void setMode(String mode) {
    _prefs.setString(_kMode, mode);
    state = state.copyWith(defaultMode: mode);
  }

  void setAutoParse(bool v) {
    _prefs.setBool(_kAutoParse, v);
    state = state.copyWith(autoParse: v);
  }

  void setDarkMode(bool value) {
    _prefs.setBool(_kDarkMode, value);
    state = state.copyWith(darkMode: value);
  }

  void setDouyinCookie(String value) {
    final trimmed = value.trim();
    _prefs.setString(_kDouyinCookie, trimmed);
    final msToken = _extractCookieValue(trimmed, 'msToken');
    final ttwid = _extractCookieValue(trimmed, 'ttwid');
    final sessionid = _extractCookieValue(trimmed, 'sessionid');
    final sVwebId = _extractCookieValue(trimmed, 's_v_web_id');
    _prefs.setString(_kDouyinMsToken, msToken);
    _prefs.setString(_kDouyinTtwid, ttwid);
    _prefs.setString(_kDouyinSessionid, sessionid);
    _prefs.setString(_kDouyinSvWebId, sVwebId);
    state = state.copyWith(
      douyinCookie: trimmed,
      douyinMsToken: msToken,
      douyinTtwid: ttwid,
      douyinSessionid: sessionid,
      douyinSvWebId: sVwebId,
    );
  }

  void setTiktokCookie(String value) {
    final trimmed = value.trim();
    _prefs.setString(_kTiktokCookie, trimmed);
    final msToken = _extractCookieValue(trimmed, 'msToken');
    final ttwid = _extractCookieValue(trimmed, 'ttwid');
    final sessionid = _extractCookieValue(trimmed, 'sessionid');
    final sVwebId = _extractCookieValue(trimmed, 's_v_web_id');
    _prefs.setString(_kTiktokMsToken, msToken);
    _prefs.setString(_kTiktokTtwid, ttwid);
    _prefs.setString(_kTiktokSessionid, sessionid);
    _prefs.setString(_kTiktokSvWebId, sVwebId);
    state = state.copyWith(
      tiktokCookie: trimmed,
      tiktokMsToken: msToken,
      tiktokTtwid: ttwid,
      tiktokSessionid: sessionid,
      tiktokSvWebId: sVwebId,
    );
  }

  void setLoginGuideShown(bool v) {
    _prefs.setBool(_kLoginGuideShown, v);
    state = state.copyWith(loginGuideShown: v);
  }

  void setPrivacyNoticeShown(bool v) {
    _prefs.setBool(_kPrivacyNoticeShown, v);
    state = state.copyWith(privacyNoticeShown: v);
  }

  String _extractCookieValue(String cookieStr, String key) {
    final regex = RegExp('$key=([^;]+)');
    final match = regex.firstMatch(cookieStr);
    return match?.group(1) ?? '';
  }

  /// 只清空临时缓存目录，设置和解析历史均保留。
  Future<void> clearCache() async {
    final dir = await _cacheDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  throw UnimplementedError('需要在 main 中 override');
});

// ───────────────────────── Tab 导航 ─────────────────────────

/// 当前 Tab 索引（0=首页, 1=最近, 2=设置）
/// 用于跨页面切换 tab（登录成功后跳转设置页）
final tabIndexProvider = StateProvider<int>((ref) => 0);

// ───────────────────────── 解析历史 ─────────────────────────

String canonicalHistoryUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return trimmed;

  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  final port = uri.hasPort ? ':${uri.port}' : '';
  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '/') path = '';
  return '$host$port$path';
}

String formatHistoryTimestamp(int milliseconds, {DateTime? referenceTime}) {
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final now = referenceTime ?? DateTime.now();
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final date = '${value.month}/${value.day} $hour:$minute';
  return value.year == now.year ? date : '${value.year}/$date';
}

bool isHistoryItemInRange(
  HistoryItem item,
  DateTime start,
  DateTime end,
) {
  final value = DateTime.fromMillisecondsSinceEpoch(item.parsedAt);
  final startOfDay = DateTime(start.year, start.month, start.day);
  final afterEnd = DateTime(end.year, end.month, end.day + 1);
  return !value.isBefore(startOfDay) && value.isBefore(afterEnd);
}

class HistoryItem {
  final String id;
  final String url;
  final String sourceType; // 'doubao' | 'douyin'
  final String mediaType; // 'image' | 'video'
  final int count;
  final List<String> thumbnailColors; // 渐变色 hex（fallback）
  final String? thumbnailUrl; // 首图/视频封面 URL（用于真实缩略图）
  final int parsedAt; // 毫秒时间戳

  const HistoryItem({
    required this.id,
    required this.url,
    required this.sourceType,
    required this.mediaType,
    required this.count,
    required this.thumbnailColors,
    this.thumbnailUrl,
    required this.parsedAt,
  });

  HistoryItem copyWith({int? parsedAt}) {
    return HistoryItem(
      id: id,
      url: url,
      sourceType: sourceType,
      mediaType: mediaType,
      count: count,
      thumbnailColors: thumbnailColors,
      thumbnailUrl: thumbnailUrl,
      parsedAt: parsedAt ?? this.parsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'sourceType': sourceType,
        'mediaType': mediaType,
        'count': count,
        'thumbnailColors': thumbnailColors,
        'thumbnailUrl': thumbnailUrl,
        'parsedAt': parsedAt,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
        id: j['id'] as String,
        url: j['url'] as String,
        sourceType: j['sourceType'] as String,
        mediaType: j['mediaType'] as String,
        count: j['count'] as int,
        thumbnailColors: (j['thumbnailColors'] as List).cast<String>(),
        thumbnailUrl: j['thumbnailUrl'] as String?,
        parsedAt: j['parsedAt'] as int,
      );
}

class HistoryState {
  final List<HistoryItem> items;
  const HistoryState({this.items = const []});
}

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier(
    this._prefs, {
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        super(const HistoryState()) {
    _load();
  }

  final AppPreferences _prefs;
  final DateTime Function() _now;
  static const _kKey = 'history_items';

  HistoryState get current => state;

  void _load() {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      final decoded = list
          .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final deduplicated = _deduplicate(decoded);
      state = HistoryState(items: deduplicated);
      if (deduplicated.length != decoded.length) _persist();
    } catch (_) {}
  }

  List<HistoryItem> _deduplicate(List<HistoryItem> items) {
    final sorted = [...items]
      ..sort((left, right) => right.parsedAt.compareTo(left.parsedAt));
    final byUrl = <String, HistoryItem>{};
    for (final item in sorted) {
      byUrl.putIfAbsent(canonicalHistoryUrl(item.url), () => item);
    }
    return byUrl.values.toList();
  }

  void _persist() {
    _prefs.setString(
        _kKey, jsonEncode(state.items.map((e) => e.toJson()).toList()));
  }

  void addHistory({
    required String url,
    required String sourceType,
    required String mediaType,
    required int count,
    required List<String> thumbnailColors,
    String? thumbnailUrl,
  }) {
    final timestamp = _now().millisecondsSinceEpoch;
    final key = canonicalHistoryUrl(url);
    HistoryItem? existing;
    for (final candidate in state.items) {
      if (canonicalHistoryUrl(candidate.url) == key) {
        existing = candidate;
        break;
      }
    }
    if (existing != null) {
      state = HistoryState(items: [
        existing.copyWith(parsedAt: timestamp),
        ...state.items.where(
          (item) => canonicalHistoryUrl(item.url) != key,
        ),
      ]);
      _persist();
      return;
    }

    final item = HistoryItem(
      id: timestamp.toString(),
      url: url,
      sourceType: sourceType,
      mediaType: mediaType,
      count: count,
      thumbnailColors: thumbnailColors,
      thumbnailUrl: thumbnailUrl,
      parsedAt: timestamp,
    );
    state = HistoryState(items: [item, ...state.items]);
    _persist();
  }

  void removeHistory(String id) {
    removeHistories([id]);
  }

  void removeHistories(Iterable<String> ids) {
    final removed = ids.toSet();
    if (removed.isEmpty) return;
    state = HistoryState(
      items: state.items.where((item) => !removed.contains(item.id)).toList(),
    );
    _persist();
  }

  void clearHistory() {
    state = const HistoryState();
    _persist();
  }

  /// 按日期分组：今天 / 昨天 / 更早
  Map<String, List<HistoryItem>> grouped({
    Iterable<HistoryItem>? items,
  }) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <String, List<HistoryItem>>{
      '今天': [],
      '昨天': [],
      '更早': [],
    };
    for (final item in items ?? state.items) {
      final dt = DateTime.fromMillisecondsSinceEpoch(item.parsedAt);
      final day = DateTime(dt.year, dt.month, dt.day);
      if (day == today) {
        groups['今天']!.add(item);
      } else if (day == yesterday) {
        groups['昨天']!.add(item);
      } else {
        groups['更早']!.add(item);
      }
    }
    return groups..removeWhere((_, v) => v.isEmpty);
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, HistoryState>((ref) {
  throw UnimplementedError('需要在 main 中 override');
});

// ───────────────────────── 缓存大小 ─────────────────────────

/// 计算 cacheDir 占用字节数（递归统计所有文件）
final cacheSizeProvider = FutureProvider<int>((ref) async {
  final dir = await getAppCacheDirectory();
  if (!dir.existsSync()) return 0;
  int total = 0;
  try {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
  } catch (_) {}
  return total;
});
