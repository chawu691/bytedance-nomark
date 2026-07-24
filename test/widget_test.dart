// 无印字节基础交互测试
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doubao_nomark/main.dart';
import 'package:doubao_nomark/pages/repo_list_page.dart';
import 'package:doubao_nomark/providers/media_providers.dart';
import 'package:doubao_nomark/services/app_preferences.dart';
import 'package:doubao_nomark/services/doubao_parser.dart';

class _PresetParseNotifier extends ParseNotifier {
  _PresetParseNotifier(ParseState initial) {
    state = initial;
  }
}

Future<SharedPreferencesAdapter> _preferences() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferencesAdapter(await SharedPreferences.getInstance());
}

void main() {
  testWidgets('App 启动并显示标题', (WidgetTester tester) async {
    final prefs = await _preferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => SettingsNotifier(prefs)),
          historyProvider.overrideWith((_) => HistoryNotifier(prefs)),
        ],
        child: const DoubaoNomarkApp(),
      ),
    );

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, '无印字节');
    expect(find.text('解析'), findsOneWidget);
  });

  testWidgets('黑夜模式使用指定背景和前景色', (tester) async {
    final prefs = await _preferences();
    final settings = SettingsNotifier(prefs)..setDarkMode(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => settings),
          historyProvider.overrideWith((_) => HistoryNotifier(prefs)),
        ],
        child: const DoubaoNomarkApp(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme!.scaffoldBackgroundColor, const Color(0xFF1E1E1E));
    expect(app.darkTheme!.colorScheme.onSurface, const Color(0xFFD4D4D4));
  });

  testWidgets('仓库页可以加载两张仓库图片', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RepoListPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RepoListPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('解析结果复选框只切换选择，点击图片打开预览', (tester) async {
    const image = ParsedImage(
      url: 'https://example.com/preview.jpg',
      width: 1920,
      height: 1080,
    );
    final parse = _PresetParseNotifier(
      const ParseState(
        images: [image],
        selectedUrls: {'https://example.com/preview.jpg'},
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          parseProvider.overrideWith((_) => parse),
        ],
        child: const MaterialApp(home: DetailPage()),
      ),
    );

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('最近页交换图标位置并可进入批量管理', (tester) async {
    final prefs = await _preferences();
    final history = HistoryNotifier(prefs);
    history.addHistory(
      url: 'https://doubao.com/thread/a',
      sourceType: 'doubao',
      mediaType: 'image',
      count: 1,
      thumbnailColors: const ['#111111', '#222222'],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => SettingsNotifier(prefs)),
          historyProvider.overrideWith((_) => history),
        ],
        child: const DoubaoNomarkApp(),
      ),
    );
    await tester.tap(find.text('最近'));
    await tester.pumpAndSettle();

    final calendar = find.byTooltip('按日期筛选');
    final batch = find.byTooltip('批量管理');
    expect(calendar, findsOneWidget);
    expect(batch, findsOneWidget);
    expect(tester.getCenter(calendar).dx, lessThan(tester.getCenter(batch).dx));

    await tester.tap(batch);
    await tester.pump();
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('全部删除'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('全部删除'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('首页'), findsOneWidget);

    await tester.tap(batch);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('日期范围条可清除且空结果有专用提示', (tester) async {
    final prefs = await _preferences();
    final history = HistoryNotifier(prefs);
    history.addHistory(
      url: 'https://doubao.com/thread/a',
      sourceType: 'doubao',
      mediaType: 'image',
      count: 1,
      thumbnailColors: const ['#111111', '#222222'],
    );
    var cleared = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyProvider.overrideWith((_) => history),
        ],
        child: MaterialApp(
          home: RecentPage(
            range: DateTimeRange(
              start: DateTime(2020, 1, 1),
              end: DateTime(2020, 1, 2),
            ),
            onClearRange: () => cleared = true,
          ),
        ),
      ),
    );

    expect(find.text('2020/1/1 – 2020/1/2'), findsOneWidget);
    expect(find.text('该时间段暂无记录'), findsOneWidget);
    await tester.tap(find.byTooltip('清除日期筛选'));
    expect(cleared, isTrue);
  });

  testWidgets('选中删除取消确认后保留选择', (tester) async {
    final prefs = await _preferences();
    var now = DateTime(2026, 7, 23, 12);
    final history = HistoryNotifier(prefs, now: () => now);
    for (final id in ['a', 'b']) {
      history.addHistory(
        url: 'https://doubao.com/thread/$id',
        sourceType: 'doubao',
        mediaType: 'image',
        count: 1,
        thumbnailColors: const ['#111111', '#222222'],
      );
      now = now.add(const Duration(milliseconds: 1));
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => SettingsNotifier(prefs)),
          historyProvider.overrideWith((_) => history),
        ],
        child: const DoubaoNomarkApp(),
      ),
    );
    await tester.tap(find.text('最近'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量管理'));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .where((checkbox) => checkbox.value == true),
      hasLength(1),
    );
    expect(history.current.items, hasLength(2));

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(history.current.items, hasLength(1));
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('批量全部删除需要确认', (tester) async {
    final prefs = await _preferences();
    final history = HistoryNotifier(prefs);
    history.addHistory(
      url: 'https://doubao.com/thread/a',
      sourceType: 'doubao',
      mediaType: 'image',
      count: 1,
      thumbnailColors: const ['#111111', '#222222'],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => SettingsNotifier(prefs)),
          historyProvider.overrideWith((_) => history),
        ],
        child: const DoubaoNomarkApp(),
      ),
    );
    await tester.tap(find.text('最近'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量管理'));
    await tester.pump();
    await tester.tap(find.text('全部删除'));
    await tester.pumpAndSettle();

    expect(history.current.items, hasLength(1));
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(history.current.items, isEmpty);
    expect(find.text('暂无记录'), findsOneWidget);
  });
}
