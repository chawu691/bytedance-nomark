import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class LoginGuideDialog {
  /// 返回 'douyin' | 'tiktok' | 'skip' | null
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('登录账号'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '使用抖音或 TikTok 解析需要先登录账号，否则该功能不可用。\n\n登录信息仅保存在本设备，不会上传云端。',
            textAlign: TextAlign.start,
            style: TextStyle(height: 1.4),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, 'douyin'),
            child: const Text('登录抖音'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, 'tiktok'),
            child: const Text('登录 TikTok'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, 'skip'),
            child: const Text('暂不登录'),
          ),
        ],
      ),
    );
  }
}
