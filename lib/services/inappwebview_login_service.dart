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
  }) async {
    final completer = Completer<WebViewLoginResult?>();
    final browser = _LoginInAppBrowser(
      targetHost: targetHost,
      cookieKeys: cookieKeys,
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
        webViewSettings: InAppWebViewSettings(userAgent: pcUserAgent),
      ),
    );
    return completer.future;
  }
}

class _LoginInAppBrowser extends InAppBrowser {
  final String targetHost;
  final List<String> cookieKeys;
  final void Function(WebViewLoginResult) onLoginDetected;
  final void Function() onClose;

  _LoginInAppBrowser({
    required this.targetHost,
    required this.cookieKeys,
    required this.onLoginDetected,
    required this.onClose,
  });

  @override
  void onLoadStop(WebUri? url) async {
    if (url == null) return;
    if (!url.host.contains(targetHost)) return;
    final cookies = await CookieManager().getCookies(
      url: WebUri('https://$targetHost'),
    );
    final cookieMap = {for (var c in cookies) c.name: c.value};
    // 仅 sessionid 是登录态标志；ttwid 是首次访问就下发的跟踪 Cookie，不能作为登录判据
    if (cookieMap.containsKey('sessionid')) {
      final cookieString =
          cookies.map((c) => '${c.name}=${c.value}').join('; ');
      final keyCookies = <String, String>{};
      for (final key in cookieKeys) {
        keyCookies[key] = cookieMap[key] ?? '';
      }
      onLoginDetected(WebViewLoginResult(
        cookieString: cookieString,
        keyCookies: keyCookies,
      ));
      close();
    }
  }

  @override
  void onExit() => onClose();
}
