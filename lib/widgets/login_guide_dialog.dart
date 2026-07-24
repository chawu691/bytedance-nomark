import 'package:flutter/material.dart';

class LoginGuideDialog {
  /// 返回 'douyin' | 'tiktok' | 'skip' | null
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('抖音解析需要登录'),
        content: const Text('使用抖音解析功能需要登录，点击下方登录'),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'douyin'),
            child: const Text('登录抖音'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'tiktok'),
            child: const Text('登录 TikTok'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'skip'),
            child: const Text('暂不登录（此功能将不可用！）'),
          ),
        ],
      ),
    );
  }
}
