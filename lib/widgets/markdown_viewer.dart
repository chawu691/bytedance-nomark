import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/app_theme.dart';

class MarkdownViewerPage extends StatelessWidget {
  final String title;
  final String assetPath;

  const MarkdownViewerPage({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(assetPath),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('加载失败: ${snapshot.error}',
                  style: TextStyle(color: context.palette.mutedForeground)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Markdown(
            data: snapshot.data!,
            selectable: true,
            styleSheet:
                MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              h1: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.palette.foreground),
              h2: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: context.palette.foreground),
              h3: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.palette.foreground),
              p: TextStyle(
                  fontSize: 15, height: 1.6, color: context.palette.foreground),
              code: TextStyle(
                fontSize: 13,
                backgroundColor: context.palette.muted,
                color: context.palette.foreground,
              ),
              codeblockDecoration: BoxDecoration(
                color: context.palette.muted,
                borderRadius: BorderRadius.circular(8),
              ),
              blockquoteDecoration: const BoxDecoration(
                border: Border(
                    left: BorderSide(color: Color(0xFFFF6A3D), width: 3)),
              ),
              tableBorder: TableBorder.all(color: context.palette.border),
              tableHead: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }
}
