import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/media_providers.dart';

class PrivacyNoticeDialog {
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final shown = ref.read(settingsProvider).privacyNoticeShown;
    if (shown) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: const Text(
          '本软件不会把您的任何登录信息、身份信息记录到云端。所有解析功能纯本地实现',
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          OutlinedButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).setPrivacyNoticeShown(true);
              Navigator.pop(ctx);
            },
            child: const Text('不再提示'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭提示'),
          ),
        ],
      ),
    );
  }
}
