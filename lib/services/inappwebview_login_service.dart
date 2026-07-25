// flutter_inappwebview 登录服务实现（Android/iOS/macOS/Windows）
// 用 InAppBrowser 打开登录页，PC UA 伪装，CookieManager 检测登录成功后关闭返回
import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'webview_login_service.dart';

/// 注册 InAppWebView 登录服务工厂
/// 需在 main() 中调用 registerInAppWebViewFactory(InAppWebViewLoginService.new)
void registerInAppWebViewLoginService() {
  registerInAppWebViewFactory(InAppWebViewLoginService.new);
}

class InAppWebViewLoginService implements WebViewLoginService {
  @override
  Future<WebViewLoginResult?> openLoginPage({
    required String loginUrl,
    required String targetHost,
    required List<String> cookieKeys,
    List<String> cookieUrls = const [],
    List<String> successCookieKeys = const ['sessionid'],
    String userAgent = mobileUserAgent,
  }) async {
    final completer = Completer<WebViewLoginResult?>();
    final browser = _LoginInAppBrowser(
      targetHost: targetHost,
      cookieKeys: cookieKeys,
      cookieUrls: cookieUrls.isEmpty
          ? ['https://$targetHost/']
          : List<String>.from(cookieUrls),
      successCookieKeys: successCookieKeys,
      onLoginDetected: (result) {
        if (!completer.isCompleted) completer.complete(result);
      },
      onClose: () {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    await browser.openUrlRequest(
      urlRequest: URLRequest(url: WebUri(loginUrl)),
      settings: InAppBrowserClassSettings(
        browserSettings: InAppBrowserSettings(hideUrlBar: true),
        webViewSettings: InAppWebViewSettings(userAgent: userAgent),
      ),
    );
    browser.startCookiePolling();
    return completer.future;
  }
}

class _LoginInAppBrowser extends InAppBrowser {
  final String targetHost;
  final List<String> cookieKeys;
  final List<String> cookieUrls;
  final List<String> successCookieKeys;
  final void Function(WebViewLoginResult) onLoginDetected;
  final void Function() onClose;
  Timer? _pollTimer;
  bool _checking = false;
  bool _finished = false;

  _LoginInAppBrowser({
    required this.targetHost,
    required this.cookieKeys,
    required this.cookieUrls,
    required this.successCookieKeys,
    required this.onLoginDetected,
    required this.onClose,
  });

  void startCookiePolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkCookies(),
    );
  }

  @override
  void onLoadStop(WebUri? url) async {
    if (url == null) return;
    if (url.host != targetHost && !url.host.endsWith('.$targetHost')) return;
    await _checkCookies();
  }

  Future<void> _checkCookies() async {
    if (_checking || _finished) return;
    _checking = true;
    try {
      final cookieMap = <String, String>{};
      for (final url in cookieUrls) {
        final cookies = await CookieManager().getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          if (cookieKeys.contains(cookie.name) && cookie.value.isNotEmpty) {
            cookieMap[cookie.name] = cookie.value;
          }
        }
      }
      final loggedIn = successCookieKeys.any(
        (key) => cookieMap[key]?.isNotEmpty == true,
      );
      if (!loggedIn) return;
      _finished = true;
      _pollTimer?.cancel();
      final cookieString = cookieMap.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
      onLoginDetected(WebViewLoginResult(
        cookieString: cookieString,
        keyCookies: {
          for (final key in cookieKeys) key: cookieMap[key] ?? '',
        },
      ));
      close();
    } finally {
      _checking = false;
    }
  }

  @override
  void onExit() {
    _pollTimer?.cancel();
    onClose();
  }
}
