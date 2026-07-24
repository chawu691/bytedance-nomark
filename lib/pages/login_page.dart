import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show showCookieSheet;
import '../providers/media_providers.dart';
import '../services/platform_services.dart';
import '../services/webview_login_service.dart';
import '../theme/app_theme.dart';
import '../widgets/privacy_notice_dialog.dart';

class LoginPage extends ConsumerStatefulWidget {
  final String platform; // 'douyin' | 'tiktok'
  const LoginPage({super.key, required this.platform});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  String _status = '准备中...';
  bool _waitingForManualPaste = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLogin());
  }

  Future<void> _startLogin() async {
    // 1. 显示隐私提示
    await PrivacyNoticeDialog.show(context, ref);

    // 2. 打开浏览器登录
    setState(() => _status = '正在打开登录页...');
    final service = createWebViewLoginService();
    final isDouyin = widget.platform == 'douyin';
    // 移动端首页：伪装 Pixel 10 + 移动端 URL，避开桌面端扫码风控。
    // 用户在移动端页面点击"登录"按钮触发手机号/验证码登录流程。
    final loginUrl = isDouyin
        ? 'https://m.douyin.com'
        : 'https://www.tiktok.com/login';
    final targetHost = isDouyin ? 'douyin.com' : 'tiktok.com';
    final cookieKeys = ['ttwid', 'msToken', 'sessionid', 's_v_web_id'];

    final result = await service.openLoginPage(
      loginUrl: loginUrl,
      targetHost: targetHost,
      cookieKeys: cookieKeys,
    );

    // 3. Linux fallback: result == null → 弹出手动粘贴框（复用 showCookieSheet）
    if (result == null) {
      if (!mounted) return;
      setState(() => _waitingForManualPaste = true);
      final isDouyinPlatform = widget.platform == 'douyin';
      showCookieSheet(
        context: context,
        title: isDouyinPlatform ? '粘贴抖音 Cookie' : '粘贴 TikTok Cookie',
        initialValue: '',
        hint: '浏览器已打开，完成登录后从浏览器开发者工具复制 Cookie 粘贴到下方',
        onSave: (value) {
          _saveCookie(value);
          triggerHaptic(HapticLevel.medium);
          _finishAndReturn();
        },
      );
      return;
    }

    // 4. 保存 Cookie
    _saveCookie(result.cookieString);
    await triggerHaptic(HapticLevel.medium);
    _finishAndReturn();
  }

  void _saveCookie(String cookie) {
    if (widget.platform == 'douyin') {
      ref.read(settingsProvider.notifier).setDouyinCookie(cookie);
    } else {
      ref.read(settingsProvider.notifier).setTiktokCookie(cookie);
    }
  }

  void _finishAndReturn() {
    if (!mounted) return;
    // 跳转到设置页（即使原来在首页）
    ref.read(tabIndexProvider.notifier).state = 2;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.platform == 'douyin' ? '登录抖音' : '登录 TikTok'),
      ),
      body: _waitingForManualPaste
          ? const SizedBox.shrink()
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_status, style: TextStyle(fontSize: 14, color: palette.mutedForeground)),
                ],
              ),
            ),
    );
  }
}
