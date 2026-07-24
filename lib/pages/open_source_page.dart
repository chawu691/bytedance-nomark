import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/markdown_viewer.dart';
import 'repo_list_page.dart';

class OpenSourcePage extends StatelessWidget {
  const OpenSourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开源与条款',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        children: [
          _row(
            context,
            icon: Icons.gavel_outlined,
            label: '开源许可证',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MarkdownViewerPage(
                  title: '开源许可证',
                  assetPath: 'LICENSE',
                ),
              ),
            ),
          ),
          _divider(context),
          _row(
            context,
            icon: Icons.code_rounded,
            label: '使用到的开源项目',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RepoListPage()),
            ),
          ),
          _divider(context),
          _row(
            context,
            icon: Icons.description_outlined,
            label: '使用条款',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MarkdownViewerPage(
                  title: '使用条款',
                  assetPath: 'TERMS_OF_USE.md',
                ),
              ),
            ),
          ),
          _divider(context),
          _row(
            context,
            icon: Icons.shield_outlined,
            label: '隐私协议',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MarkdownViewerPage(
                  title: '隐私协议',
                  assetPath: 'PRIVACY_POLICY.md',
                ),
              ),
            ),
          ),
          _divider(context),
          _row(
            context,
            icon: Icons.article_outlined,
            label: '第三方依赖许可证',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MarkdownViewerPage(
                  title: '第三方依赖许可证',
                  assetPath: 'THIRD_PARTY_LICENSES.md',
                ),
              ),
            ),
          ),
          _divider(context),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(height: 1, color: context.palette.border),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: context.palette.mutedForeground),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.palette.foreground),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: context.palette.mutedForeground),
          ],
        ),
      ),
    );
  }
}
