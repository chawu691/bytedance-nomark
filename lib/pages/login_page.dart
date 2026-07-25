import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show showCookieSheet;
import '../providers/media_providers.dart';
import '../services/douyin_qr_login_client.dart';
import '../services/platform_services.dart';
import '../services/webview_login_service.dart';
import '../theme/app_theme.dart';
import '../widgets/privacy_notice_dialog.dart';

class LoginPage extends ConsumerStatefulWidget {
  final String platform;
  final DouyinQrLoginClient Function()? douyinClientFactory;
  final WebViewLoginService Function()? webViewServiceFactory;
  final Future<void> Function(Uint8List bytes)? saveQrOverride;
  final Future<bool> Function(Uri uri)? externalLauncher;
  final bool? mobileOverride;

  const LoginPage({
    super.key,
    required this.platform,
    this.douyinClientFactory,
    this.webViewServiceFactory,
    this.saveQrOverride,
    this.externalLauncher,
    this.mobileOverride,
  });

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  DouyinQrLoginClient? _client;
  DouyinLoginChallenge? _challenge;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  String _status = '准备中...';
  String? _error;
  bool _busy = true;
  bool _pollInFlight = false;
  bool _completed = false;
  int _secondsLeft = 0;

  bool get _isDouyin => widget.platform == 'douyin';

  bool get _isMobile =>
      widget.mobileOverride ?? (isOhos || Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLogin());
  }

  Future<void> _startLogin() async {
    await PrivacyNoticeDialog.show(context, ref);
    if (!mounted) return;
    if (!_isDouyin) {
      await _openTikTokLogin();
    } else if (_isMobile) {
      await _createDouyinChallenge();
    } else {
      await _openDesktopDouyinLogin();
    }
  }

  Future<void> _openTikTokLogin() async {
    setState(() {
      _busy = true;
      _status = '正在打开登录页...';
      _error = null;
    });
    WebViewLoginResult? result;
    try {
      result = await _webViewService.openLoginPage(
        loginUrl: 'https://www.tiktok.com/login',
        targetHost: 'tiktok.com',
        cookieKeys: const ['ttwid', 'msToken', 'sessionid', 's_v_web_id'],
      );
    } catch (_) {
      result = null;
    }
    if (!mounted || _completed) return;
    if (result == null) {
      setState(() {
        _busy = false;
        _status = '网页登录已关闭';
      });
      _showManualCookieSheet(browserOpened: true);
      return;
    }
    await _completeLogin(result.cookieString);
  }

  Future<void> _openDesktopDouyinLogin() async {
    setState(() {
      _busy = true;
      _status = '正在外部浏览器中打开抖音...';
      _error = null;
    });
    try {
      final uri = Uri.parse('https://www.douyin.com/');
      final opened = await (widget.externalLauncher?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) throw const FileSystemException('browser_not_opened');
    } catch (_) {
      if (mounted) _error = '无法自动打开浏览器，请手动访问 douyin.com';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '请在浏览器登录后粘贴 Cookie';
    });
    _showManualCookieSheet(browserOpened: true);
  }

  Future<void> _createDouyinChallenge() async {
    await _stopProtocolSession();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _challenge = null;
      _error = null;
      _status = '正在生成登录二维码...';
      _secondsLeft = 0;
    });
    final client = widget.douyinClientFactory?.call() ?? DouyinQrLoginClient();
    _client = client;
    try {
      final existingTtwid = ref.read(settingsProvider).douyinTtwid;
      final challenge = await client.createChallenge(
        existingTtwid: existingTtwid,
      );
      if (!mounted || client != _client) {
        await client.close();
        return;
      }
      setState(() {
        _challenge = challenge;
        _busy = false;
        _status = '等待扫码';
        _secondsLeft = challenge.expiresAt
            .difference(DateTime.now())
            .inSeconds
            .clamp(0, 180);
      });
      _startPolling();
    } on DouyinLoginFailure catch (error) {
      if (!mounted || client != _client) return;
      if (error.state == DouyinLoginPollState.verificationRequired) {
        await _openDouyinWebFallback();
      } else {
        await _showProtocolError(error.message);
      }
    } catch (_) {
      if (mounted && client == _client) {
        await _showProtocolError('网络连接失败，请稍后重试');
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollOnce()),
    );
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final challenge = _challenge;
      if (!mounted || challenge == null) return;
      final seconds = challenge.expiresAt
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, 180);
      setState(() => _secondsLeft = seconds);
      if (seconds == 0) _expireChallenge();
    });
  }

  Future<void> _pollOnce() async {
    final challenge = _challenge;
    final client = _client;
    if (_pollInFlight || challenge == null || client == null || _completed) {
      return;
    }
    _pollInFlight = true;
    try {
      final result = await client.poll(challenge);
      if (!mounted || client != _client || _completed) return;
      if (DateTime.now().isAfter(challenge.expiresAt)) {
        await _expireChallenge();
        return;
      }
      switch (result.state) {
        case DouyinLoginPollState.waiting:
          if (_status != '等待扫码') setState(() => _status = '等待扫码');
          break;
        case DouyinLoginPollState.scanned:
          setState(() => _status = '已扫码，请在抖音中确认');
          break;
        case DouyinLoginPollState.success:
          final cookie = result.cookieString;
          if (cookie == null || cookie.isEmpty) {
            await _openDouyinWebFallback();
          } else {
            await _completeLogin(cookie);
          }
          break;
        case DouyinLoginPollState.expired:
          await _expireChallenge();
          break;
        case DouyinLoginPollState.verificationRequired:
          await _openDouyinWebFallback();
          break;
        case DouyinLoginPollState.networkError:
          await _showProtocolError(result.message ?? '网络连接失败，请重试');
          break;
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _expireChallenge() async {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    if (!mounted || _completed) return;
    setState(() {
      _status = '二维码已过期';
      _error = '请重新生成二维码';
      _secondsLeft = 0;
    });
  }

  Future<void> _showProtocolError(String message) async {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    final client = _client;
    _client = null;
    await client?.close();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _challenge = null;
      _status = '暂时无法连接登录服务';
      _error = message;
    });
  }

  Future<void> _openDouyinWebFallback() async {
    await _stopProtocolSession();
    if (!mounted || _completed) return;
    setState(() {
      _busy = true;
      _challenge = null;
      _status = '正在打开网页登录验证...';
      _error = null;
    });
    WebViewLoginResult? result;
    try {
      result = await _webViewService.openLoginPage(
        loginUrl:
            'https://sso.douyin.com/get_qrcode/?service=https%3A%2F%2Fwww.douyin.com%2F'
            '&need_back_url=true&size=180&aid=6383&language=zh',
        targetHost: 'douyin.com',
        cookieKeys: DouyinQrLoginClient.cookieKeys,
        cookieUrls: const [
          'https://www.douyin.com/',
          'https://sso.douyin.com/',
        ],
        successCookieKeys: const ['sessionid', 'sessionid_ss'],
        userAgent: douyinSsoUserAgent,
      );
    } catch (_) {
      result = null;
    }
    if (!mounted || _completed) return;
    if (result != null) {
      await _completeLogin(result.cookieString);
      return;
    }
    setState(() {
      _busy = false;
      _status = '网页登录已关闭';
      _error = '可以重新生成二维码，或手动粘贴 Cookie';
    });
  }

  Future<void> _saveQr() async {
    final challenge = _challenge;
    if (challenge == null) return;
    final bytes = challenge.imageBytes;
    final fileName = 'douyin_login_qr_${DateTime.now().millisecondsSinceEpoch}.'
        '${challenge.imageExtension}';
    try {
      final override = widget.saveQrOverride;
      if (override != null) {
        await override(bytes);
      } else if (isOhos) {
        final directory = await getAppCacheDirectory();
        final file = File(
          '${directory.path}${Platform.pathSeparator}$fileName',
        );
        try {
          await file.writeAsBytes(bytes, flush: true);
          final result = await saveOhosMediaBatch([
            OhosMediaFile(
              path: file.path,
              mediaType: 'image',
              fileName: file.uri.pathSegments.last,
            ),
          ]);
          if (!result.savedIndices.contains(0)) {
            throw FileSystemException(
              result.errors[0] ?? '未能保存到相册',
              file.path,
            );
          }
        } finally {
          if (await file.exists()) await file.delete();
        }
      } else {
        final hasAccess = await Gal.hasAccess(toAlbum: true) ||
            await Gal.requestAccess(toAlbum: true);
        if (!hasAccess) throw const FileSystemException('未授予相册权限');
        await Gal.putImageBytes(
          bytes,
          name: fileName,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('二维码已保存，请在抖音扫一扫中从相册识别')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('二维码保存失败，请检查相册权限')),
      );
    }
  }

  void _showManualCookieSheet({bool browserOpened = false}) {
    if (!mounted) return;
    showCookieSheet(
      context: context,
      title: _isDouyin ? '粘贴抖音 Cookie' : '粘贴 TikTok Cookie',
      initialValue: '',
      hint: browserOpened
          ? '完成登录后，从浏览器开发者工具复制 Cookie 粘贴到下方'
          : '从已登录的浏览器复制 Cookie 粘贴到下方',
      onSave: (value) {
        final cookie = value.trim();
        if (cookie.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cookie 不能为空')),
          );
          return;
        }
        unawaited(_completeLogin(cookie));
      },
    );
  }

  Future<void> _completeLogin(String cookie) async {
    if (_completed || cookie.trim().isEmpty) return;
    _completed = true;
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    if (_isDouyin) {
      ref.read(settingsProvider.notifier).setDouyinCookie(cookie);
    } else {
      ref.read(settingsProvider.notifier).setTiktokCookie(cookie);
    }
    final client = _client;
    _client = null;
    await client?.close();
    await triggerHaptic(HapticLevel.medium);
    if (!mounted) return;
    ref.read(tabIndexProvider.notifier).state = 2;
    Navigator.of(context).pop();
  }

  Future<void> _stopProtocolSession() async {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _pollTimer = null;
    _countdownTimer = null;
    final client = _client;
    _client = null;
    await client?.close();
  }

  WebViewLoginService get _webViewService =>
      widget.webViewServiceFactory?.call() ?? createWebViewLoginService();

  Future<void> _cancel() async {
    if (_completed) return;
    _completed = true;
    await _stopProtocolSession();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    final client = _client;
    _client = null;
    if (client != null) unawaited(client.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final challenge = _challenge;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_completed) {
          _completed = true;
          unawaited(_stopProtocolSession());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isDouyin ? '登录抖音' : '登录 TikTok'),
          leading: IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_busy) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                    ],
                    if (challenge != null) ...[
                      Container(
                        width: 252,
                        height: 252,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: palette.border),
                        ),
                        child: Image.memory(
                          challenge.imageBytes,
                          key: const Key('douyin-login-qr'),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _secondsLeft > 0 ? '剩余 $_secondsLeft 秒' : '已过期',
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.foreground,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.mutedForeground,
                        ),
                      ),
                    ],
                    if (challenge != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '保存二维码后，可在抖音扫一扫中从相册识别；也可以使用另一台设备扫码。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          height: 1.5,
                          fontSize: 13,
                          color: palette.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        key: const Key('save-douyin-qr'),
                        onPressed: _saveQr,
                        icon: const Icon(Icons.save_alt_rounded),
                        label: const Text('保存二维码到相册'),
                      ),
                    ],
                    if (!_busy && _isDouyin) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('retry-douyin-qr'),
                          onPressed: _createDouyinChallenge,
                          child: Text(
                            challenge == null ? '生成二维码' : '重新生成二维码',
                          ),
                        ),
                      ),
                      if (_isMobile) ...[
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _openDouyinWebFallback,
                          child: const Text('使用网页登录'),
                        ),
                      ],
                      TextButton(
                        onPressed: () => _showManualCookieSheet(),
                        child: const Text('手动粘贴 Cookie'),
                      ),
                    ],
                    if (!_busy && !_isDouyin)
                      TextButton(
                        onPressed: () => _showManualCookieSheet(),
                        child: const Text('手动粘贴 Cookie'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
