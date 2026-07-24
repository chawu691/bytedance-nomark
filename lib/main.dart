// 无印字节 - 移动端无水印下载图片与视频
// 三 Tab 架构：首页 / 最近 / 设置
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'pages/open_source_page.dart';
import 'providers/media_providers.dart';
import 'services/app_preferences.dart';
import 'services/doubao_parser.dart';
import 'services/platform_services.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await loadAppPreferences();
  runApp(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsNotifier(prefs)),
      historyProvider.overrideWith((_) => HistoryNotifier(prefs)),
    ],
    child: const DoubaoNomarkApp(),
  ));
}

class DoubaoNomarkApp extends ConsumerWidget {
  const DoubaoNomarkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final darkMode =
        ref.watch(settingsProvider.select((value) => value.darkMode));
    final overlayStyle = SystemUiOverlayStyle(
      systemNavigationBarColor:
          darkMode ? appDarkBackground : AppPalette.light.card,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: darkMode ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness:
          darkMode ? Brightness.light : Brightness.dark,
    );
    return MaterialApp(
      title: '无印字节',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: child!,
      ),
      home: const MainShell(),
    );
  }
}

// ───────────────────────── 颜色常量 ─────────────────────────
const _primary = Color(0xFFFF6A3D);
const _success = Color(0xFF22C55E);
const _info = Color(0xFF3B82F6);
const _error = Color(0xFFEF4444);
const _videoDark = Color(0xFF2A2A2A);

// ───────────────────────── SVG 图标（lucide，与 home.html 同源） ─────────────────────────
const _pasteSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1" ry="1"/></svg>
''';

const _closeSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
''';

const _trashSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
''';

const _batchSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 3h4"/><path d="M12 3v10"/><path d="M4 13h16"/><path d="M4 21h16"/><path d="M4 17h16"/><path d="m9 8 3 3 3-3"/></svg>
''';

const _calendarSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
''';

const _githubSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4"/><path d="M9 18c-4.51 2-5-2-7-2"/></svg>
''';

Widget _svgIcon(String svgString, {required Color color, double size = 20}) {
  return SvgPicture.string(
    svgString,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

void _noop() {}
void _noopValue(String _) {}

// ───────────────────────── 字节格式化 ─────────────────────────
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

// ───────────────────────── 主框架（底部 Tab） ─────────────────────────

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  DateTimeRange? _recentRange;
  bool _historyBatchMode = false;
  Set<String> _selectedHistoryIds = {};

  List<HistoryItem> _visibleHistory(List<HistoryItem> items) {
    final range = _recentRange;
    if (range == null) return items;
    return items
        .where((item) => isHistoryItemInRange(item, range.start, range.end))
        .toList();
  }

  Future<void> _pickRecentRange(List<HistoryItem> items) async {
    if (_historyBatchMode || items.isEmpty) return;
    final dates = items
        .map((item) => DateTime.fromMillisecondsSinceEpoch(item.parsedAt))
        .toList()
      ..sort();
    final now = DateTime.now();
    final activeRange = _recentRange;
    final first = activeRange != null && activeRange.start.isBefore(dates.first)
        ? activeRange.start
        : dates.first;
    final latestHistory = dates.last.isAfter(now) ? dates.last : now;
    final last = activeRange != null && activeRange.end.isAfter(latestHistory)
        ? activeRange.end
        : latestHistory;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(last.year, last.month, last.day),
      initialDateRange: _recentRange,
      helpText: '选择时间段',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
    );
    if (picked != null && mounted) {
      setState(() => _recentRange = picked);
    }
  }

  void _enterHistoryBatch() {
    setState(() {
      _historyBatchMode = true;
      _selectedHistoryIds = {};
    });
  }

  void _exitHistoryBatch() {
    setState(() {
      _historyBatchMode = false;
      _selectedHistoryIds = {};
    });
  }

  void _toggleHistory(String id) {
    setState(() {
      final selected = {..._selectedHistoryIds};
      selected.contains(id) ? selected.remove(id) : selected.add(id);
      _selectedHistoryIds = selected;
    });
  }

  void _confirmHistoryDeletion(List<HistoryItem> visibleItems) {
    final ids = _selectedHistoryIds.isEmpty
        ? visibleItems.map((item) => item.id).toSet()
        : _selectedHistoryIds;
    if (ids.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeleteHistorySheet(
        onDelete: () {
          ref.read(historyProvider.notifier).removeHistories(ids);
          if (mounted) _exitHistoryBatch();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final visibleHistory = _visibleHistory(history.items);
    final pages = [
      const HomePage(),
      RecentPage(
        range: _recentRange,
        batchMode: _historyBatchMode,
        selectedIds: _selectedHistoryIds,
        onPickRange: () => _pickRecentRange(history.items),
        onClearRange: () => setState(() => _recentRange = null),
        onEnterBatch: _enterHistoryBatch,
        onToggleItem: _toggleHistory,
      ),
      const SettingsPage(),
    ];

    return PopScope(
      canPop: !_historyBatchMode,
      // Flutter 3.22 OHOS 尚无 onPopInvokedWithResult。
      // ignore: deprecated_member_use
      onPopInvoked: (didPop) {
        if (!didPop && _historyBatchMode) _exitHistoryBatch();
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: _historyBatchMode
            ? _HistoryBatchBar(
                hasSelection: _selectedHistoryIds.isNotEmpty,
                onDelete: () => _confirmHistoryDeletion(visibleHistory),
                onCancel: _exitHistoryBatch,
              )
            : _buildNavigationBar(context),
      ),
    );
  }

  Widget _buildNavigationBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        backgroundColor: context.palette.card,
        selectedItemColor: _primary,
        unselectedItemColor: context.palette.mutedForeground,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined, size: 22),
            activeIcon: Icon(Icons.home_rounded, size: 22),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.access_time_outlined, size: 22),
            activeIcon: Icon(Icons.access_time_rounded, size: 22),
            label: '最近',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined, size: 22),
            activeIcon: Icon(Icons.settings_rounded, size: 22),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class _HistoryBatchBar extends StatelessWidget {
  final bool hasSelection;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _HistoryBatchBar({
    required this.hasSelection,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onDelete,
                  child: Center(
                    child: Text(
                      hasSelection ? '删除' : '全部删除',
                      style: const TextStyle(
                        color: _error,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: context.palette.border,
              ),
              Expanded(
                child: InkWell(
                  onTap: onCancel,
                  child: Center(
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: context.palette.mutedForeground,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 首页（home.html） ─────────────────────────

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _ctrl = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final has = _ctrl.text.isNotEmpty;
    if (has != _hasText) {
      setState(() => _hasText = has);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      _ctrl.text = data.text!;
      if (ref.read(settingsProvider).autoParse) {
        _parse();
      }
    }
  }

  void _clearInput() {
    _ctrl.clear();
    setState(() => _hasText = false);
  }

  Future<void> _parse() async {
    FocusScope.of(context).unfocus();
    await ref.read(parseProvider.notifier).parse(_ctrl.text);

    // 解析成功后记录历史
    final state = ref.read(parseProvider);
    final images = state.images;
    final videos = state.videos;
    if ((images != null && images.isNotEmpty) ||
        (videos != null && videos.isNotEmpty)) {
      final url = _ctrl.text.trim();
      final hasImg = images != null && images.isNotEmpty;
      final hasVid = videos != null && videos.isNotEmpty;
      final isVideo = !hasImg && hasVid;
      final count = (images?.length ?? 0) + (videos?.length ?? 0);

      // 取首图/视频封面作为缩略图
      final firstImg =
          (images != null && images.isNotEmpty) ? images.first.url : null;
      final firstVidCover =
          (videos != null && videos.isNotEmpty) ? videos.first.coverUrl : null;
      final thumbUrl = firstImg ?? firstVidCover;

      ref.read(historyProvider.notifier).addHistory(
            url: url,
            sourceType: 'doubao',
            mediaType: isVideo ? 'video' : 'image',
            count: count,
            thumbnailColors:
                isVideo ? ['#2A2A2A', '#2A2A2A'] : ['#93C5FD', '#3B82F6'],
            thumbnailUrl: thumbUrl,
          );
    }
  }

  void _goToDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DetailPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(parseProvider);
    final settings = ref.watch(settingsProvider);
    final hasResult = (state.images != null && state.images!.isNotEmpty) ||
        (state.videos != null && state.videos!.isNotEmpty);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 56),
                // 模式切换
                _buildModeSwitcher(settings.defaultMode),
                const SizedBox(height: 24),
                // 提示文字
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '粘贴对话分享链接，提取无水印素材',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: context.palette.mutedForeground),
                  ),
                ),
                const SizedBox(height: 16),
                // 输入区
                _buildInputArea(state),
                const SizedBox(height: 24),
                // 解析按钮
                _buildParseButton(state),
                // 结果预览条
                if (hasResult) ...[
                  const SizedBox(height: 24),
                  _buildPreviewStrip(state),
                ],
                // 错误提示
                if (state.error != null) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      state.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: context.palette.mutedForeground, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher(String currentMode) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segment('豆包', currentMode == 'doubao', () {
              ref.read(settingsProvider.notifier).setMode('doubao');
            }),
            _segment('抖音', currentMode == 'douyin', () {
              ref.read(settingsProvider.notifier).setMode('douyin');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('抖音模式暂未支持'),
                  duration: Duration(seconds: 2),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
            color: active ? Colors.white : context.palette.mutedForeground,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(ParseState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: context.palette.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.link_rounded,
                size: 18, color: context.palette.mutedForeground),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                style:
                    TextStyle(fontSize: 15, color: context.palette.foreground),
                decoration: InputDecoration(
                  hintText: '粘贴链接...',
                  hintStyle: TextStyle(
                      fontSize: 15, color: context.palette.mutedForeground),
                  isCollapsed: true,
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _parse(),
              ),
            ),
            // 清除叉号：仅在有内容时显示
            if (_hasText) ...[
              GestureDetector(
                onTap: _clearInput,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _svgIcon(_closeSvg,
                      color: context.palette.mutedForeground, size: 18),
                ),
              ),
              const SizedBox(width: 12),
            ],
            // 粘贴按钮：SVG 图标
            GestureDetector(
              onTap: _paste,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: _svgIcon(_pasteSvg, color: _primary, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParseButton(ParseState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: state.isLoading ? null : _parse,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: state.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  '解析',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPreviewStrip(ParseState state) {
    final images = state.images ?? const [];
    final videos = state.videos ?? const [];
    final totalCount = images.length + videos.length;
    final isVideo = images.isEmpty && videos.isNotEmpty;
    final label = isVideo
        ? '查看 $totalCount 个视频 →'
        : videos.isNotEmpty
            ? '查看 $totalCount 项 →'
            : '查看 $totalCount 张图片 →';

    final thumbs = <Widget>[];
    if (images.isNotEmpty) {
      for (var i = 0; i < images.length && i < 3; i++) {
        thumbs.add(_imageThumb(images[i].url));
      }
    } else if (videos.isNotEmpty) {
      for (var i = 0; i < videos.length && i < 3; i++) {
        thumbs.add(_videoThumb(videos[i].coverUrl));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _goToDetail,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.border),
          ),
          child: Row(
            children: [
              ...thumbs.expand((t) => [t, const SizedBox(width: 6)]),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: _primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageThumb(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 48,
          height: 48,
          color: context.palette.muted,
        ),
      ),
    );
  }

  Widget _videoThumb(String? coverUrl) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _videoDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child:
          const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 18),
    );
  }
}

// ───────────────────────── 详情页（方案B 选择逻辑） ─────────────────────────

class DetailPage extends ConsumerWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(parseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择内容',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: state.images == null && state.videos == null
            ? Center(
                child: Text('暂无解析结果',
                    style: TextStyle(color: context.palette.mutedForeground)))
            : Column(
                children: [
                  _buildSummaryCard(context, state),
                  _buildSelectAllToggles(context, ref, state),
                  Expanded(child: _buildResultContent(state)),
                  _buildBottomBar(context, ref, state),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, ParseState state) {
    final images = state.images ?? const [];
    final videos = state.videos ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.palette.border),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.manage_search_rounded,
                    color: _primary, size: 18),
                const SizedBox(width: 8),
                Text('内容检测结果',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: context.palette.foreground)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (images.isNotEmpty)
                  _countBadge(context, Icons.image_outlined, _info,
                      '${images.length} 张图片'),
                if (images.isNotEmpty && videos.isNotEmpty)
                  const SizedBox(width: 8),
                if (videos.isNotEmpty)
                  _countBadge(context, Icons.play_circle_outline,
                      const Color(0xFFA855F7), '${videos.length} 个视频'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _countBadge(
      BuildContext context, IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.palette.muted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(text,
              style:
                  TextStyle(fontSize: 13, color: context.palette.foreground)),
        ],
      ),
    );
  }

  Widget _buildSelectAllToggles(
      BuildContext context, WidgetRef ref, ParseState state) {
    final images = state.images ?? const [];
    final videos = state.videos ?? const [];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.palette.border),
        ),
        child: Column(
          children: [
            if (images.isNotEmpty) ...[
              _buildToggleRow(
                context: context,
                value: state.isAllImageSelected,
                onChanged: (v) => v
                    ? ref.read(parseProvider.notifier).selectAll()
                    : ref.read(parseProvider.notifier).deselectAll(),
                label: '全选图片',
              ),
            ],
            if (images.isNotEmpty && videos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1, color: context.palette.border),
              ),
            if (videos.isNotEmpty) ...[
              _buildToggleRow(
                context: context,
                value: state.isAllVideoSelected,
                onChanged: (v) => v
                    ? ref.read(parseProvider.notifier).selectAllVideos()
                    : ref.read(parseProvider.notifier).deselectAllVideos(),
                label: '全选视频',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required BuildContext context,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String label,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 22,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.palette.foreground)),
      ],
    );
  }

  Widget _buildResultContent(ParseState state) {
    final images = state.images ?? const [];
    final videos = state.videos ?? const [];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty) ...[
            _buildImageGrid(state),
            if (videos.isNotEmpty) const SizedBox(height: 16),
          ],
          if (videos.isNotEmpty) _buildVideoList(state),
        ],
      ),
    );
  }

  Widget _buildImageGrid(ParseState state) {
    final images = state.images ?? const [];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) =>
          _SelectableImageTile(image: images[i], state: state),
    );
  }

  Widget _buildVideoList(ParseState state) {
    final videos = state.videos ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < videos.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < videos.length - 1 ? 12 : 0),
            child: _SelectableVideoTile(video: videos[i], state: state),
          ),
      ],
    );
  }

  Widget _buildBottomBar(
      BuildContext context, WidgetRef ref, ParseState state) {
    final count = state.selectedCount;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(top: BorderSide(color: context.palette.border)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, -4))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: _primary, size: 16),
            const SizedBox(width: 4),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: '已选 ',
                  style: TextStyle(
                      fontSize: 13, color: context.palette.foreground)),
              TextSpan(
                  text: '$count',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _primary)),
              TextSpan(
                  text: ' 项',
                  style: TextStyle(
                      fontSize: 13, color: context.palette.foreground)),
            ])),
            const Spacer(),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: count == 0
                      ? null
                      : () async {
                          final notifier = ref.read(downloadProvider.notifier);
                          await notifier.downloadSelected(
                            images: (state.images ?? const [])
                                .where((image) =>
                                    state.selectedUrls.contains(image.url))
                                .toList(),
                            videos: (state.videos ?? const [])
                                .where((video) =>
                                    state.selectedVideoUrls.contains(video.url))
                                .toList(),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _primary,
                    disabledBackgroundColor: context.palette.muted,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: count > 0 ? 4 : 0,
                    shadowColor:
                        count > 0 ? _primary.withAlpha(77) : Colors.transparent,
                  ),
                  child: Text('下载所选 ($count)',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── 最近页（recent.html） ─────────────────────────

class RecentPage extends ConsumerWidget {
  final DateTimeRange? range;
  final bool batchMode;
  final Set<String> selectedIds;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;
  final VoidCallback onEnterBatch;
  final ValueChanged<String> onToggleItem;

  const RecentPage({
    super.key,
    this.range,
    this.batchMode = false,
    this.selectedIds = const {},
    this.onPickRange = _noop,
    this.onClearRange = _noop,
    this.onEnterBatch = _noop,
    this.onToggleItem = _noopValue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final visibleItems = range == null
        ? history.items
        : history.items
            .where(
                (item) => isHistoryItemInRange(item, range!.start, range!.end))
            .toList();
    final groups =
        ref.read(historyProvider.notifier).grouped(items: visibleItems);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(0, 56, 0, 0),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Text('最近',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: context.palette.foreground)),
                    const Spacer(),
                    IconButton(
                      tooltip: '按日期筛选',
                      onPressed: batchMode || history.items.isEmpty
                          ? null
                          : onPickRange,
                      icon: _svgIcon(
                        _calendarSvg,
                        color: range == null
                            ? context.palette.mutedForeground
                            : _primary,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: '批量管理',
                      onPressed: batchMode || visibleItems.isEmpty
                          ? null
                          : onEnterBatch,
                      icon: _svgIcon(
                        _batchSvg,
                        color: batchMode
                            ? _primary
                            : context.palette.mutedForeground,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (range != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                    decoration: BoxDecoration(
                      color: context.palette.muted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range_rounded,
                            size: 16, color: context.palette.mutedForeground),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatRange(range!),
                            style: TextStyle(
                                fontSize: 13,
                                color: context.palette.foreground),
                          ),
                        ),
                        IconButton(
                          tooltip: '清除日期筛选',
                          visualDensity: VisualDensity.compact,
                          onPressed: batchMode ? null : onClearRange,
                          icon: _svgIcon(_closeSvg,
                              color: context.palette.mutedForeground, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (history.items.isEmpty || visibleItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 56, color: Color(0xFFD4D4D4)),
                    const SizedBox(height: 16),
                    Text(
                      history.items.isEmpty ? '暂无记录' : '该时间段暂无记录',
                      style: TextStyle(
                          color: context.palette.mutedForeground, fontSize: 14),
                    ),
                  ],
                ),
              )
            else ...[
              for (final entry in groups.entries)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, idx) {
                      if (idx == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(entry.key,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: context.palette.mutedForeground)),
                        );
                      }
                      final item = entry.value[idx - 1];
                      return _HistoryTile(
                        item: item,
                        batchMode: batchMode,
                        selected: selectedIds.contains(item.id),
                        onToggle: () => onToggleItem(item.id),
                      );
                    },
                    childCount: entry.value.length + 1,
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 96),
                  child: Center(
                    child: Text('仅显示最近 30 天的记录',
                        style: TextStyle(
                            fontSize: 12,
                            color: context.palette.mutedForeground
                                .withAlpha(179))),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRange(DateTimeRange value) {
    return '${value.start.year}/${value.start.month}/${value.start.day}'
        ' – '
        '${value.end.year}/${value.end.month}/${value.end.day}';
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryItem item;
  final bool batchMode;
  final bool selected;
  final VoidCallback onToggle;

  const _HistoryTile({
    required this.item,
    this.batchMode = false,
    this.selected = false,
    this.onToggle = _noop,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: batchMode ? onToggle : () => _reopen(context),
      onLongPress: batchMode ? null : () => _showDeleteSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (batchMode) ...[
              Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                activeColor: _primary,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
            ],
            _buildThumb(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(),
                    style: TextStyle(
                        fontSize: 15, color: context.palette.foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _shortUrl(),
                    style: TextStyle(
                        fontSize: 12, color: context.palette.mutedForeground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatHistoryTimestamp(item.parsedAt),
                    style: TextStyle(
                        fontSize: 11,
                        color: context.palette.mutedForeground.withAlpha(179)),
                  ),
                ],
              ),
            ),
            if (!batchMode)
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: context.palette.mutedForeground),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb() {
    final url = item.thumbnailUrl;
    // 无 URL：回退到原有占位（视频深色盒 / 图片渐变）
    if (url == null || url.isEmpty) {
      return _gradientFallback();
    }
    // 有 URL：真实缩略图，视频叠 play 图标
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _gradientFallback(),
            ),
            if (item.mediaType == 'video')
              Container(
                color: const Color(0x66000000),
                alignment: Alignment.center,
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  /// 无 thumbnailUrl 时的回退占位（保留原有视觉）
  Widget _gradientFallback() {
    if (item.mediaType == 'video') {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _videoDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.play_arrow_rounded,
            color: Colors.white70, size: 18),
      );
    }
    final colors = item.thumbnailColors;
    final c1 = _hexColor(colors.isNotEmpty ? colors[0] : '#93C5FD');
    final c2 = _hexColor(colors.length > 1 ? colors[1] : '#3B82F6');
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c1, c2]),
      ),
    );
  }

  String _title() {
    final source = item.sourceType == 'douyin' ? '抖音' : '豆包对话';
    final unit = item.mediaType == 'video' ? '个视频' : '张图片';
    return '$source · ${item.count}$unit';
  }

  String _shortUrl() {
    final uri = Uri.tryParse(item.url);
    if (uri == null) return item.url;
    return '${uri.host}${uri.path}';
  }

  Color _hexColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  void _reopen(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    container.read(parseProvider.notifier).parse(item.url).then((_) {
      final state = container.read(parseProvider);
      if (state.images != null || state.videos != null) {
        navigator.push(
          MaterialPageRoute(builder: (_) => const DetailPage()),
        );
      }
    });
  }

  void _showDeleteSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DeleteHistorySheet(
        onDelete: () {
          final container = ProviderScope.containerOf(context, listen: false);
          container.read(historyProvider.notifier).removeHistory(item.id);
        },
      ),
    );
  }
}

/// 底部升起的删除确认操作表（iOS Action Sheet 风格）
/// 两行：删除（红色，trash SVG）+ 取消（灰色，close SVG）
class _DeleteHistorySheet extends StatelessWidget {
  final VoidCallback onDelete;
  const _DeleteHistorySheet({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 第一行：删除（红色）
            InkWell(
              onTap: () {
                onDelete();
                Navigator.of(context).pop();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _svgIcon(_trashSvg, color: _error, size: 18),
                    const SizedBox(width: 8),
                    const Text('删除',
                        style: TextStyle(
                            fontSize: 16,
                            color: _error,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: context.palette.border),
            // 第二行：取消（灰色）
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _svgIcon(_closeSvg,
                        color: context.palette.mutedForeground, size: 18),
                    const SizedBox(width: 8),
                    Text('取消',
                        style: TextStyle(
                            fontSize: 16,
                            color: context.palette.mutedForeground,
                            fontWeight: FontWeight.w500)),
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

// ───────────────────────── 设置页（settings.html） ─────────────────────────

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);
    final history = ref.watch(historyProvider);
    final cacheAsync = ref.watch(cacheSizeProvider);
    final cacheText = cacheAsync.when(
      data: (bytes) => _formatBytes(bytes),
      loading: () => '计算中...',
      error: (error, stackTrace) => '--',
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text('设置',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: palette.foreground)),
              ),
              // 通用
              _sectionTitle(context, '通用'),
              _cardGroup(context, [
                // 默认模式：segmented control（与首页一致）
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('默认模式',
                          style: TextStyle(
                              fontSize: 15, color: palette.foreground)),
                      _buildModeSwitcherCompact(
                          context, settings.defaultMode, ref),
                    ],
                  ),
                ),
                _toggleRow(
                  context,
                  label: '自动解析',
                  value: settings.autoParse,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setAutoParse(v),
                ),
                _toggleRow(
                  context,
                  label: '黑夜模式',
                  value: settings.darkMode,
                  onChanged: (value) =>
                      ref.read(settingsProvider.notifier).setDarkMode(value),
                ),
              ]),
              // 关于
              _sectionTitle(context, '关于'),
              _cardGroup(context, [
                _row(context,
                    label: '版本',
                    trailing: Text('v1.0.0',
                        style: TextStyle(
                            fontSize: 13, color: palette.mutedForeground))),
                InkWell(
                  onTap: () => launchUrl(
                    Uri.parse('https://github.com/chawu691/bytedance-nomark'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('开源项目',
                            style: TextStyle(
                                fontSize: 15, color: palette.foreground)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _svgIcon(_githubSvg,
                                color: palette.mutedForeground, size: 18),
                            const SizedBox(width: 6),
                            Icon(Icons.open_in_new_rounded,
                                size: 14, color: palette.mutedForeground),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OpenSourcePage()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('使用条款',
                            style: TextStyle(
                                fontSize: 15, color: palette.foreground)),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: palette.mutedForeground),
                      ],
                    ),
                  ),
                ),
              ]),
              // 危险操作
              const SizedBox(height: 8),
              _cardGroup(context, [
                _row(
                  context,
                  label: '缓存占用',
                  trailing: Text(cacheText,
                      style: TextStyle(
                          fontSize: 13, color: palette.mutedForeground)),
                ),
                InkWell(
                  onTap: () => _confirmClearCache(context, ref),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text('清除缓存',
                          style: TextStyle(
                              fontSize: 15,
                              color: _error,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
              ]),
              if (history.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text('共 ${history.items.length} 条记录',
                      style: TextStyle(
                          fontSize: 12, color: palette.mutedForeground)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 紧凑版 segmented control（用于设置页）
  Widget _buildModeSwitcherCompact(
      BuildContext context, String currentMode, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segmentCompact(context, '豆包', currentMode == 'doubao', () {
            ref.read(settingsProvider.notifier).setMode('doubao');
          }),
          _segmentCompact(context, '抖音', currentMode == 'douyin', () {
            ref.read(settingsProvider.notifier).setMode('douyin');
          }),
        ],
      ),
    );
  }

  Widget _segmentCompact(
      BuildContext context, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? _primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
            color: active ? Colors.white : context.palette.mutedForeground,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 13,
              color: context.palette.mutedForeground,
              letterSpacing: 0.5)),
    );
  }

  Widget _cardGroup(BuildContext context, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1 && children[i] is! Divider)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, color: context.palette.border),
              ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context,
      {required String label, required Widget trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 15, color: context.palette.foreground)),
          trailing,
        ],
      ),
    );
  }

  Widget _toggleRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 15, color: context.palette.foreground)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: _primary,
            activeThumbColor: Colors.white,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: context.palette.border,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  void _confirmClearCache(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: ctx.palette.card,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await ref.read(settingsProvider.notifier).clearCache();
                  PaintingBinding.instance.imageCache.clear();
                  PaintingBinding.instance.imageCache.clearLiveImages();
                  ref.invalidate(cacheSizeProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已清除缓存'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _svgIcon(_trashSvg, color: _error, size: 18),
                      const SizedBox(width: 8),
                      const Text('清除缓存',
                          style: TextStyle(
                              fontSize: 16,
                              color: _error,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: ctx.palette.border),
              InkWell(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _svgIcon(_closeSvg,
                          color: ctx.palette.mutedForeground, size: 18),
                      const SizedBox(width: 8),
                      Text('取消',
                          style: TextStyle(
                              fontSize: 16,
                              color: ctx.palette.mutedForeground,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 可选中图片卡片 ─────────────────────────

class _ImagePreviewPage extends StatelessWidget {
  final String url;

  const _ImagePreviewPage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: Colors.white70, size: 48),
                    SizedBox(height: 12),
                    Text('图片加载失败', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x66000000),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openVideoPreview(
  BuildContext context,
  ParsedVideo video,
) async {
  try {
    if (!kIsWeb && isOhos) {
      await platformChannel.invokeMethod<void>(
        'openMedia',
        {'url': video.url, 'mediaType': 'video'},
      );
      return;
    }
    if (!kIsWeb && Platform.isWindows) {
      await Process.start(
        'rundll32.exe',
        ['url.dll,FileProtocolHandler', video.url],
      );
      return;
    }
    if (!kIsWeb && Platform.isLinux) {
      await Process.start('xdg-open', [video.url]);
      return;
    }
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _VideoPreviewPage(url: video.url),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法播放视频：$error')),
      );
    }
  }
}

class _VideoPreviewPage extends StatefulWidget {
  final String url;

  const _VideoPreviewPage({required this.url});

  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialization;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: const {
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'referer': 'https://www.doubao.com/',
      },
    );
    _initialization = _controller.initialize().then((_) {
      _controller.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
    if (mounted) setState(() {});
  }

  String _formatVideoTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('视频播放'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: FutureBuilder<void>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text(
                '视频加载失败',
                style: TextStyle(color: Colors.white70),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator(color: Colors.white);
            }
            final ratio = _controller.value.aspectRatio;
            final pos = _controller.value.position;
            final dur = _controller.value.duration;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: ratio > 0 ? ratio : 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _togglePlayback,
                        onLongPressStart: (_) {
                          _controller.setPlaybackSpeed(2.0);
                          setState(() => _playbackSpeed = 2.0);
                        },
                        onLongPressEnd: (_) {
                          _controller.setPlaybackSpeed(1.0);
                          setState(() => _playbackSpeed = 1.0);
                        },
                        child: VideoPlayer(_controller),
                      ),
                      if (!_controller.value.isPlaying)
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0x99000000),
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 36),
                            ),
                          ),
                        ),
                      if (_playbackSpeed != 1.0)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xCC000000),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                color: _primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        _formatVideoTime(pos),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        _formatVideoTime(dur),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: _primary,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SelectableImageTile extends ConsumerWidget {
  final ParsedImage image;
  final ParseState state;
  const _SelectableImageTile({required this.image, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = state.selectedUrls.contains(image.url);
    final task = ref.watch(downloadProvider)[image.url];
    final isBusy = task?.status == DownloadStatus.downloading ||
        task?.status == DownloadStatus.saving;
    final isDone = task?.status == DownloadStatus.done;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ImagePreviewPage(url: image.url),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? _primary : context.palette.border,
              width: 2.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              image.url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: context.palette.muted,
                child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: context.palette.mutedForeground),
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x8C000000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatSize(image.width, image.height),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: _buildStatusBadge(
                isSelected,
                isBusy,
                isDone,
                () => ref.read(parseProvider.notifier).toggleSelect(image.url),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    bool selected,
    bool busy,
    bool done,
    VoidCallback onToggle,
  ) {
    if (busy) {
      return Container(
        width: 20,
        height: 20,
        padding: const EdgeInsets.all(3),
        child: const CircularProgressIndicator(strokeWidth: 2, color: _primary),
      );
    }
    if (done) {
      return Container(
        width: 20,
        height: 20,
        decoration:
            const BoxDecoration(shape: BoxShape.circle, color: _success),
        child: const Icon(Icons.check, color: Colors.white, size: 12),
      );
    }
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: selected,
            onChanged: (_) => onToggle(),
            activeColor: _primary,
            checkColor: Colors.white,
            shape: const CircleBorder(),
            side: const BorderSide(color: Color(0xD9FFFFFF), width: 2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  String _formatSize(int? w, int? h) {
    if (w == null || h == null) return '';
    if (w >= 3840 || h >= 2160) return '4K';
    if (w >= 2560 || h >= 1440) return '2K';
    if (w >= 1920 || h >= 1080) return '1080p';
    if (w >= 1280 || h >= 720) return '720p';
    if (w >= 1000) return 'SD';
    return '${w}x$h';
  }
}

// ───────────────────────── 可选中视频卡片 ─────────────────────────

class _SelectableVideoTile extends ConsumerWidget {
  final ParsedVideo video;
  final ParseState state;
  const _SelectableVideoTile({required this.video, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = state.selectedVideoUrls.contains(video.url);
    final task = ref.watch(downloadProvider)[video.url];
    final isBusy = task?.status == DownloadStatus.downloading ||
        task?.status == DownloadStatus.saving;
    final isDone = task?.status == DownloadStatus.done;

    return GestureDetector(
      onTap: () => _openVideoPreview(context, video),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? _primary : context.palette.border,
              width: 2.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (video.coverUrl != null)
                    Image.network(
                      video.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: context.palette.muted,
                        child: Center(
                          child: Icon(Icons.video_library_outlined,
                              color: context.palette.mutedForeground, size: 28),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: context.palette.muted,
                      child: Center(
                        child: Icon(Icons.video_library_outlined,
                            color: context.palette.mutedForeground, size: 28),
                      ),
                    ),
                  Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x99000000),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _formatDuration(video.duration),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.palette.foreground),
                    ),
                    if (video.width != null && video.height != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${video.width}x${video.height}',
                          style: TextStyle(
                              fontSize: 12,
                              color: context.palette.mutedForeground),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _buildStatusBadge(
                isSelected,
                isBusy,
                isDone,
                () => ref
                    .read(parseProvider.notifier)
                    .toggleVideoSelect(video.url),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    bool selected,
    bool busy,
    bool done,
    VoidCallback onToggle,
  ) {
    if (busy) {
      return Container(
        width: 20,
        height: 20,
        padding: const EdgeInsets.all(3),
        child: const CircularProgressIndicator(strokeWidth: 2, color: _primary),
      );
    }
    if (done) {
      return Container(
        width: 20,
        height: 20,
        decoration:
            const BoxDecoration(shape: BoxShape.circle, color: _success),
        child: const Icon(Icons.check, color: Colors.white, size: 12),
      );
    }
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: selected,
            onChanged: (_) => onToggle(),
            activeColor: _primary,
            checkColor: Colors.white,
            shape: const CircleBorder(),
            side: const BorderSide(color: Color(0xD9FFFFFF), width: 2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '';
    final s = seconds.toInt();
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
