import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'abogus.dart';

enum DouyinLoginPollState {
  waiting,
  scanned,
  success,
  expired,
  verificationRequired,
  networkError,
}

class DouyinLoginChallenge {
  final String sessionKey;
  final Uint8List imageBytes;
  final DateTime expiresAt;
  final Uri pollEndpoint;
  final Map<String, dynamic> pollParameters;
  final bool pollWithPost;
  final String imageExtension;

  const DouyinLoginChallenge({
    required this.sessionKey,
    required this.imageBytes,
    required this.expiresAt,
    required this.pollEndpoint,
    required this.pollParameters,
    required this.pollWithPost,
    this.imageExtension = 'png',
  });
}

class DouyinLoginPollResult {
  final DouyinLoginPollState state;
  final String? cookieString;
  final String? message;

  const DouyinLoginPollResult(this.state, {this.cookieString, this.message});
}

class DouyinLoginFailure implements Exception {
  final DouyinLoginPollState state;
  final String message;

  const DouyinLoginFailure(this.state, this.message);

  @override
  String toString() => message;
}

class DouyinQrLoginClient {
  static const int maxJsonBytes = 64 * 1024;
  static const int maxQrBytes = 512 * 1024;

  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/130.0.0.0 Safari/537.36';

  static const List<String> cookieKeys = [
    'sessionid',
    'sessionid_ss',
    'sid_guard',
    'sid_tt',
    'uid_tt',
    'uid_tt_ss',
    'ttwid',
    'msToken',
    'odin_tt',
    'passport_csrf_token',
    's_v_web_id',
  ];

  final Dio _dio;
  final CookieJar _cookieJar;
  final bool _ownsDio;
  bool _closed = false;

  DouyinQrLoginClient({Dio? dio, CookieJar? cookieJar})
      : _dio = dio ?? Dio(),
        _cookieJar = cookieJar ?? CookieJar(),
        _ownsDio = dio == null {
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<DouyinLoginChallenge> createChallenge({
    String existingTtwid = '',
  }) async {
    _ensureOpen();
    final configuredTtwid = existingTtwid.trim();
    if (_isSafeCookieValue(configuredTtwid)) {
      final cookie = Cookie('ttwid', configuredTtwid)
        ..domain = '.douyin.com'
        ..path = '/';
      await _cookieJar.saveFromResponse(
        Uri.parse('https://www.douyin.com/'),
        [cookie],
      );
    }
    await _bootstrapAnonymousSession();

    DouyinLoginFailure? lastFailure;
    for (final modern in [false, true]) {
      try {
        return await _requestChallenge(modern: modern);
      } on DouyinLoginFailure catch (error) {
        if (error.state == DouyinLoginPollState.verificationRequired) rethrow;
        lastFailure = error;
      }
    }
    throw lastFailure ??
        const DouyinLoginFailure(
          DouyinLoginPollState.networkError,
          '暂时无法生成登录二维码，请稍后重试',
        );
  }

  Future<DouyinLoginPollResult> poll(
    DouyinLoginChallenge challenge,
  ) async {
    _ensureOpen();
    if (DateTime.now().isAfter(challenge.expiresAt)) {
      return const DouyinLoginPollResult(DouyinLoginPollState.expired);
    }

    try {
      final params = Map<String, dynamic>.from(challenge.pollParameters);
      if (challenge.pollWithPost) {
        params['a_bogus'] = ABogus().getValue(params, method: 'POST');
      }
      final response = await _requestJson(
        challenge.pollEndpoint.toString(),
        method: challenge.pollWithPost ? 'POST' : 'GET',
        queryParameters: challenge.pollWithPost ? null : params,
        data: challenge.pollWithPost ? params : null,
        headers: challenge.pollWithPost
            ? const {'Content-Type': Headers.formUrlEncodedContentType}
            : null,
      );
      if (_requiresVerification(response)) {
        return const DouyinLoginPollResult(
          DouyinLoginPollState.verificationRequired,
          message: '当前登录需要在网页中完成验证',
        );
      }

      final data = _dataMap(response);
      final rawStatus = data['status'] ??
          data['qr_status'] ??
          data['status_code'] ??
          response['status'];
      final status = rawStatus?.toString().toLowerCase();
      if (status == '1' || status == '0' || status == 'new') {
        return const DouyinLoginPollResult(DouyinLoginPollState.waiting);
      }
      if (status == '2' || status == 'scanned') {
        return const DouyinLoginPollResult(DouyinLoginPollState.scanned);
      }
      if (status == '4' || status == '5' || status == 'expired') {
        return const DouyinLoginPollResult(DouyinLoginPollState.expired);
      }
      if (status == '3') {
        final redirect = _firstString(data, const [
          'redirect_url',
          'redirectUrl',
          'callback_url',
        ]);
        if (redirect != null) await _followTrustedRedirects(redirect);
        final cookieString = await exportLoginCookies();
        if (!_hasLoginCookie(cookieString)) {
          return const DouyinLoginPollResult(
            DouyinLoginPollState.verificationRequired,
            message: '扫码已确认，但登录凭据未完成写入',
          );
        }
        return DouyinLoginPollResult(
          DouyinLoginPollState.success,
          cookieString: cookieString,
        );
      }
      return const DouyinLoginPollResult(DouyinLoginPollState.waiting);
    } on DouyinLoginFailure catch (error) {
      return DouyinLoginPollResult(error.state, message: error.message);
    } on DioException {
      return const DouyinLoginPollResult(
        DouyinLoginPollState.networkError,
        message: '网络连接失败，请重试',
      );
    } catch (_) {
      return const DouyinLoginPollResult(
        DouyinLoginPollState.networkError,
        message: '登录状态检查失败，请重试',
      );
    }
  }

  Future<String> exportLoginCookies() async {
    final merged = <String, Cookie>{};
    for (final uri in [
      Uri.parse('https://www.douyin.com/'),
      Uri.parse('https://sso.douyin.com/'),
      Uri.parse('https://passport.douyin.com/'),
    ]) {
      for (final cookie in await _cookieJar.loadForRequest(uri)) {
        if (cookieKeys.contains(cookie.name) &&
            _isSafeCookieValue(cookie.value)) {
          merged[cookie.name] = cookie;
        }
      }
    }
    return merged.values
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _cookieJar.deleteAll();
    if (_ownsDio) _dio.close(force: true);
  }

  Future<void> _bootstrapAnonymousSession() async {
    if (await _hasTtwid()) return;
    try {
      final response = await _requestJson(
        'https://ttwid.bytedance.com/ttwid/union/register/',
        method: 'POST',
        data: {
          'region': 'cn',
          'aid': 6383,
          'needFid': false,
          'service': 'www.douyin.com',
          'union': true,
          'fid': '',
        },
        headers: const {
          'Origin': 'https://www.douyin.com',
          'Referer': 'https://www.douyin.com/',
        },
      );
      final redirect = _firstString(response, const [
            'redirect_url',
            'redirectUrl',
          ]) ??
          _firstString(_dataMap(response), const [
            'redirect_url',
            'redirectUrl',
          ]);
      if (redirect != null) await _followTrustedRedirects(redirect);
    } on DouyinLoginFailure catch (error) {
      if (error.state == DouyinLoginPollState.verificationRequired) rethrow;
      throw const DouyinLoginFailure(
        DouyinLoginPollState.networkError,
        '匿名登录会话初始化失败，请重试',
      );
    } on DioException {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.networkError,
        '匿名登录会话初始化失败，请重试',
      );
    }
    if (!await _hasTtwid()) {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.networkError,
        '匿名登录会话初始化失败，请重试',
      );
    }
  }

  Future<DouyinLoginChallenge> _requestChallenge({
    required bool modern,
  }) async {
    final params = modern ? _modernParameters() : _legacyParameters();
    if (modern) params['a_bogus'] = ABogus().getValue(params);
    final endpoint = modern
        ? 'https://sso.douyin.com/passport/web/get_qrcode/'
        : 'https://sso.douyin.com/get_qrcode/';
    final response = await _requestJson(
      endpoint,
      queryParameters: params,
    );
    if (_requiresVerification(response)) {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.verificationRequired,
        '当前环境需要在网页中继续验证',
      );
    }
    final data = _dataMap(response);
    final sessionKey = _firstString(data, const [
      'token',
      'qrcode_token',
      'qr_token',
      'session_key',
    ]);
    final qrValue = _firstString(data, const [
      'qrcode',
      'qrcode_url',
      'qr_code',
      'qr_url',
    ]);
    if (sessionKey == null ||
        qrValue == null ||
        sessionKey.length > 512 ||
        qrValue.length > 2048 ||
        !RegExp(r'^[A-Za-z0-9._~=-]+$').hasMatch(sessionKey)) {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.networkError,
        '二维码接口暂时不可用',
      );
    }
    final imageBytes = await _loadQrImage(qrValue);
    final pollParameters = Map<String, dynamic>.from(params)..remove('a_bogus');
    pollParameters['token'] = sessionKey;
    return DouyinLoginChallenge(
      sessionKey: sessionKey,
      imageBytes: imageBytes,
      expiresAt: DateTime.now().add(const Duration(seconds: 180)),
      pollEndpoint: Uri.parse(
        modern
            ? 'https://sso.douyin.com/passport/web/check_qrconnect/'
            : 'https://sso.douyin.com/check_qrconnect/',
      ),
      pollParameters: pollParameters,
      pollWithPost: modern,
      imageExtension: _imageExtension(imageBytes),
    );
  }

  Map<String, dynamic> _legacyParameters() => {
        'aid': 6383,
        'account_sdk_source': 'sso',
        'device_platform': 'web_app',
        'sdk_version': '2.2.5_beta.1',
        'language': 'zh',
        'service': 'https://www.douyin.com/',
        'need_logo': true,
        'need_short_url': true,
      };

  Map<String, dynamic> _modernParameters() {
    final verifyFp = 'verify_${_randomToken(36)}';
    return {
      'aid': 6383,
      'app_id': 6383,
      'account_sdk_source': 'web',
      'device_platform': 'web_app',
      'passport_jssdk_version': '3.1.3',
      'passport_ztsdk_version': '3.1.3',
      'passport_jssdk_type': 'normal',
      'is_from_ttaccountsdk': 1,
      'cookie_enabled': true,
      'browser_language': 'zh-CN',
      'browser_platform': 'Win32',
      'browser_name': 'Chrome',
      'browser_version': '130.0.0.0',
      'language': 'zh',
      'host': 'https://www.douyin.com',
      'request_host': 'https://www.douyin.com',
      'service': 'https://www.douyin.com/',
      'mix_mode': 1,
      'need_logo': false,
      'is_new_login': 1,
      'verifyFp': verifyFp,
      'fp': verifyFp,
      'msToken': _randomToken(96),
    };
  }

  Future<Map<String, dynamic>> _requestJson(
    String url, {
    String method = 'GET',
    Map<String, dynamic>? queryParameters,
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    final bytes = await _requestBytes(
      url,
      limit: maxJsonBytes,
      method: method,
      queryParameters: queryParameters,
      data: data,
      headers: headers,
    );
    final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
    if (text.startsWith('<!DOCTYPE') || text.startsWith('<html')) {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.verificationRequired,
        '登录接口返回了网页验证',
      );
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } on FormatException {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.verificationRequired,
        '登录接口需要在网页中执行验证',
      );
    }
    throw const DouyinLoginFailure(
      DouyinLoginPollState.networkError,
      '登录接口返回了无效数据',
    );
  }

  Future<Uint8List> _requestBytes(
    String url, {
    required int limit,
    String method = 'GET',
    Map<String, dynamic>? queryParameters,
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    final cancelToken = CancelToken();
    try {
      final response = await _dio.request<List<int>>(
        url,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          responseType: ResponseType.bytes,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'User-Agent': desktopUserAgent,
            'Accept': 'application/json, text/plain, */*',
            ...?headers,
          },
        ),
        onReceiveProgress: (received, _) {
          if (received > limit && !cancelToken.isCancelled) {
            cancelToken.cancel('response_limit');
          }
        },
      );
      final status = response.statusCode ?? 0;
      if (status == 403 || status == 429) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.verificationRequired,
          '当前环境需要额外验证',
        );
      }
      if (status >= 300 && status < 400) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.verificationRequired,
          '登录接口返回了网页跳转',
        );
      }
      if (status >= 400) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.networkError,
          '登录服务暂时不可用',
        );
      }
      final bytes = Uint8List.fromList(response.data ?? const []);
      if (bytes.length > limit) {
        throw DouyinLoginFailure(
          DouyinLoginPollState.networkError,
          limit == maxQrBytes ? '二维码图片过大' : '登录接口响应过大',
        );
      }
      return bytes;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel && cancelToken.isCancelled) {
        throw DouyinLoginFailure(
          DouyinLoginPollState.networkError,
          limit == maxQrBytes ? '二维码图片过大' : '登录接口响应过大',
        );
      }
      rethrow;
    }
  }

  Future<Uint8List> _loadQrImage(String value) async {
    if (value.startsWith('data:image/')) {
      final comma = value.indexOf(',');
      if (comma < 0 || !value.substring(0, comma).contains(';base64')) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.networkError,
          '二维码图片格式无效',
        );
      }
      final bytes = base64Decode(value.substring(comma + 1));
      if (bytes.length > maxQrBytes || !_isImage(bytes)) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.networkError,
          '二维码图片格式无效或过大',
        );
      }
      return Uint8List.fromList(bytes);
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !_isTrustedHttpsUri(uri, _isTrustedQrHost)) {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.networkError,
        '二维码图片地址不可信',
      );
    }
    final bytes = await _requestBytes(value, limit: maxQrBytes);
    if (!_isImage(bytes)) {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.verificationRequired,
        '二维码接口返回了网页验证',
      );
    }
    return bytes;
  }

  Future<void> _followTrustedRedirects(String rawUrl) async {
    if (rawUrl.length > 2048) {
      throw const DouyinLoginFailure(
        DouyinLoginPollState.verificationRequired,
        '登录回调地址不可信',
      );
    }
    var uri = Uri.tryParse(rawUrl);
    for (var index = 0; index < 5 && uri != null; index++) {
      if (!_isTrustedHttpsUri(uri, _isTrustedRedirectHost)) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.verificationRequired,
          '登录回调地址不可信',
        );
      }
      final response = await _dio.get<ResponseBody>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 500,
          headers: const {'User-Agent': desktopUserAgent},
        ),
      );
      await response.data?.stream.listen((_) {}).cancel();
      final status = response.statusCode ?? 0;
      if (status == 403 || status == 429) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.verificationRequired,
          '当前环境需要额外验证',
        );
      }
      if (status >= 400) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.networkError,
          '登录确认请求失败，请重试',
        );
      }
      if (_hasLoginCookie(await exportLoginCookies())) return;
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return;
      if (location.length > 2048) {
        throw const DouyinLoginFailure(
          DouyinLoginPollState.verificationRequired,
          '登录回调地址不可信',
        );
      }
      uri = uri.resolve(location);
    }
    throw const DouyinLoginFailure(
      DouyinLoginPollState.verificationRequired,
      '登录回调跳转次数过多',
    );
  }

  static bool _requiresVerification(Map<String, dynamic> response) {
    for (final value in [response, response['data']]) {
      if (value is! Map) continue;
      for (final key in const [
        'verify_ticket',
        'captcha',
        'verify_center',
        'verify_center_decision_conf',
        'risk_control',
      ]) {
        final marker = value[key];
        if (marker != null && marker != false && marker.toString().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  static Map<String, dynamic> _dataMap(Map<String, dynamic> response) {
    final data = response['data'];
    return data is Map ? data.cast<String, dynamic>() : response;
  }

  static String? _firstString(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  static bool _isTrustedRedirectHost(String host) =>
      _hostMatches(host, 'douyin.com') || _hostMatches(host, 'iesdouyin.com');

  static bool _isTrustedQrHost(String host) =>
      _isTrustedRedirectHost(host) ||
      _hostMatches(host, 'bytedance.com') ||
      _hostMatches(host, 'douyinpic.com') ||
      _hostMatches(host, 'byteimg.com') ||
      _hostMatches(host, 'douyincdn.com') ||
      _hostMatches(host, 'pstatp.com');

  static bool _hostMatches(String host, String suffix) =>
      host == suffix || host.endsWith('.$suffix');

  static bool _isTrustedHttpsUri(
    Uri uri,
    bool Function(String host) hostCheck,
  ) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (uri.hasPort ? uri.port == 443 : true) &&
      hostCheck(uri.host.toLowerCase());

  Future<bool> _hasTtwid() async {
    for (final uri in [
      Uri.parse('https://www.douyin.com/'),
      Uri.parse('https://sso.douyin.com/'),
    ]) {
      for (final cookie in await _cookieJar.loadForRequest(uri)) {
        if (cookie.name == 'ttwid' && _isSafeCookieValue(cookie.value)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _isSafeCookieValue(String value) =>
      RegExp(r'^[\x21\x23-\x2b\x2d-\x3a\x3c-\x5b\x5d-\x7e]{1,4096}$')
          .hasMatch(value);

  static bool _isImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    final png = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8;
    final webp =
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    return png || jpeg || webp;
  }

  static String _imageExtension(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'webp';
    }
    return 'png';
  }

  static bool _hasLoginCookie(String cookies) =>
      RegExp(r'(?:^|;\s*)(?:sessionid|sessionid_ss)=[^;]+').hasMatch(cookies);

  static String _randomToken(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('DouyinQrLoginClient is closed');
  }
}
