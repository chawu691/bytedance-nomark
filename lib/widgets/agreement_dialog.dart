import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../widgets/markdown_viewer.dart';

/// 首次启动时弹出的使用条款 / 隐私协议同意对话框
/// 返回 true 表示用户点击"开始"；false / null 表示用户退出
class AgreementDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _AgreementDialogView(),
    );
  }
}

class _AgreementDialogView extends StatelessWidget {
  const _AgreementDialogView();

  Future<void> _openDoc(BuildContext context, String title, String asset) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarkdownViewerPage(title: title, assetPath: asset),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 链接蓝色与 iOS 系统蓝一致，确保深浅色都可见
    const linkColor = Color(0xFF0A84FF);
    const mutedColor = Color(0xFF8E8E93);
    return Dialog(
      backgroundColor: const Color(0xFFF2F2F7),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 22, 24, 8),
              child: Text(
                '使用条款与隐私协议',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ),
            // 正文
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Text(
                '欢迎使用无印字节。在开始使用前，请阅读并同意我们的使用条款与隐私协议。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: const Color(0xFF3C3C43).withValues(alpha: 0.85),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 按钮：开始（主操作） / 退出（次要）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        color: const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(10),
                        pressedOpacity: 0.7,
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          '退出',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        color: linkColor,
                        borderRadius: BorderRadius.circular(10),
                        pressedOpacity: 0.85,
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text(
                          '开始',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 同意小字 + 蓝色下划线条款链接
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: mutedColor,
                ),
                textAlign: TextAlign.center,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('点击开始即代表你已阅读并同意 '),
                    GestureDetector(
                      onTap: () => _openDoc(context, '使用条款', 'TERMS_OF_USE.md'),
                      child: const Text(
                        '使用条款',
                        style: TextStyle(
                          color: linkColor,
                          decoration: TextDecoration.underline,
                          decorationColor: linkColor,
                          decorationThickness: 1.2,
                        ),
                      ),
                    ),
                    const Text(' 及 '),
                    GestureDetector(
                      onTap: () => _openDoc(context, '隐私协议', 'PRIVACY_POLICY.md'),
                      child: const Text(
                        '隐私协议',
                        style: TextStyle(
                          color: linkColor,
                          decoration: TextDecoration.underline,
                          decorationColor: linkColor,
                          decorationThickness: 1.2,
                        ),
                      ),
                    ),
                    const Text('。'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
