// 跨平台 WebView 登录服务抽象
// 统一 Android/iOS/macOS/Windows（flutter_inappwebview）、OHOS（原生 ArkTS Web）、Linux（fallback）
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'platform_services.dart';

/// WebView 登录结果
class WebViewLoginResult {
  /// 整串 Cookie（原样保存备用）
  final String cookieString;

  /// 关键字段（ttwid、msToken、sessionid、s_v_web_id 等）
  final Map<String, String> keyCookies;

  const WebViewLoginResult({
    required this.cookieString,
    required this.keyCookies,
  });
}

/// 跨平台 WebView 登录服务抽象
abstract class WebViewLoginService {
  /// 打开登录页，检测到登录 Cookie 后返回结果；用户取消返回 null
  Future<WebViewLoginResult?> openLoginPage({
    required String loginUrl,
    required String targetHost,
    required List<String> cookieKeys,
    List<String> cookieUrls = const [],
    List<String> successCookieKeys = const ['sessionid'],
    String userAgent = mobileUserAgent,
  });
}

/// TikTok 等现有移动登录页使用的 UA。
const mobileUserAgent =
    'Mozilla/5.0 (Linux; Android 15; Pixel 10) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/130.0.0.0 Mobile Safari/537.36';

/// 抖音 SSO 二维码页需要执行桌面版 JavaScript。
const douyinSsoUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/130.0.0.0 Safari/537.36';

/// 平台工厂：根据当前平台返回对应实现
WebViewLoginService createWebViewLoginService() {
  if (isOhos) return _OhosWebViewLoginService();
  if (Platform.isLinux) return _LinuxFallbackLoginService();
  // Android/iOS/macOS/Windows 走 flutter_inappwebview
  return _createInAppWebViewService();
}

// OHOS 实现：通过 MethodChannel 调用原生 ArkTS Web 组件
class _OhosWebViewLoginService implements WebViewLoginService {
  @override
  Future<WebViewLoginResult?> openLoginPage({
    required String loginUrl,
    required String targetHost,
    required List<String> cookieKeys,
    List<String> cookieUrls = const [],
    List<String> successCookieKeys = const ['sessionid'],
    String userAgent = mobileUserAgent,
  }) async {
    try {
      final cookieStr = await platformChannel.invokeMethod<String>(
        'openLoginPage',
        {
          'loginUrl': loginUrl,
          'targetHost': targetHost,
          'cookieKeys': cookieKeys,
          'cookieUrls': cookieUrls,
          'successCookieKeys': successCookieKeys,
          'userAgent': userAgent,
        },
      );
      if (cookieStr == null || cookieStr.isEmpty) return null;
      final keyCookies = <String, String>{};
      for (final key in cookieKeys) {
        final regex = RegExp('(?:^|;\\s*)${RegExp.escape(key)}=([^;]+)');
        final match = regex.firstMatch(cookieStr);
        keyCookies[key] = match?.group(1) ?? '';
      }
      return WebViewLoginResult(
        cookieString: cookieStr,
        keyCookies: keyCookies,
      );
    } catch (_) {
      return null;
    }
  }
}

// Linux fallback：打开外部浏览器，返回 null 触发上层手动粘贴
class _LinuxFallbackLoginService implements WebViewLoginService {
  @override
  Future<WebViewLoginResult?> openLoginPage({
    required String loginUrl,
    required String targetHost,
    required List<String> cookieKeys,
    List<String> cookieUrls = const [],
    List<String> successCookieKeys = const ['sessionid'],
    String userAgent = mobileUserAgent,
  }) async {
    await launchUrl(Uri.parse(loginUrl), mode: LaunchMode.externalApplication);
    // 返回 null 触发上层 LoginPage 弹出手动粘贴框
    return null;
  }
}

// Android/iOS/macOS/Windows 实现：用 flutter_inappwebview
// 实现位于 inappwebview_login_service.dart，通过此工厂创建
WebViewLoginService _createInAppWebViewService() {
  // ignore: prefer_function_declarations_over_variables
  return _inAppWebViewServiceFactory();
}

// 工厂函数指针，由 inappwebview_login_service.dart 设置
WebViewLoginService Function() _inAppWebViewServiceFactory =
    _defaultInAppWebViewFactory;

WebViewLoginService _defaultInAppWebViewFactory() {
  // 运行时由 inappwebview_login_service.dart 的 registerInAppWebViewFactory 注册
  throw UnsupportedError(
      'flutter_inappwebview 未注册，请确保 inappwebview_login_service.dart 已被 import');
}

/// 注册 flutter_inappwebview 工厂（由 inappwebview_login_service.dart 调用）
void registerInAppWebViewFactory(WebViewLoginService Function() factory) {
  _inAppWebViewServiceFactory = factory;
}
