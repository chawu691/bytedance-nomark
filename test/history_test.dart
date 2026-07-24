import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:doubao_nomark/providers/media_providers.dart';
import 'package:doubao_nomark/services/app_preferences.dart';

class _MemoryPreferences implements AppPreferences {
  final Map<String, Object?> values;

  _MemoryPreferences([Map<String, Object?>? initial]) : values = {...?initial};

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

HistoryItem _item({
  required String id,
  required String url,
  required DateTime parsedAt,
  int count = 1,
}) {
  return HistoryItem(
    id: id,
    url: url,
    sourceType: 'doubao',
    mediaType: 'image',
    count: count,
    thumbnailColors: const ['#111111', '#222222'],
    thumbnailUrl: 'https://example.com/$id.jpg',
    parsedAt: parsedAt.millisecondsSinceEpoch,
  );
}

void main() {
  test('URL 判重忽略协议、www、查询、片段和末尾斜杠', () {
    const variants = [
      'https://www.Doubao.com/thread/AbC/?from=share#top',
      'HTTP://doubao.com/thread/AbC',
      'https://doubao.com/thread/AbC///',
    ];
    final keys = variants.map(canonicalHistoryUrl).toSet();

    expect(keys, {'doubao.com/thread/AbC'});
    expect(
      canonicalHistoryUrl('https://doubao.com/thread/abc'),
      isNot('doubao.com/thread/AbC'),
    );
  });

  test('加载旧记录时合并重复链接并保留最新项', () {
    final older = _item(
      id: 'older',
      url: 'https://www.doubao.com/thread/a?old=1',
      parsedAt: DateTime(2026, 7, 20, 7, 10),
      count: 1,
    );
    final newer = _item(
      id: 'newer',
      url: 'http://doubao.com/thread/a/',
      parsedAt: DateTime(2026, 7, 21, 18, 20),
      count: 9,
    );
    final prefs = _MemoryPreferences({
      'history_items': jsonEncode([older.toJson(), newer.toJson()]),
    });

    final notifier = HistoryNotifier(prefs);

    expect(notifier.current.items, hasLength(1));
    expect(notifier.current.items.single.id, 'newer');
    expect(notifier.current.items.single.count, 9);
    expect(
      jsonDecode(prefs.getString('history_items')!),
      hasLength(1),
    );
  });

  test('重复新增只更新时间并把旧记录移到首位', () {
    var now = DateTime(2026, 7, 23, 7, 10);
    final prefs = _MemoryPreferences();
    final notifier = HistoryNotifier(prefs, now: () => now);

    notifier.addHistory(
      url: 'https://www.doubao.com/thread/a?first=1',
      sourceType: 'doubao',
      mediaType: 'image',
      count: 2,
      thumbnailColors: const ['#111111', '#222222'],
      thumbnailUrl: 'https://example.com/original.jpg',
    );
    final original = notifier.current.items.single;
    now = DateTime(2026, 7, 23, 18, 20);
    notifier.addHistory(
      url: 'http://doubao.com/thread/b',
      sourceType: 'doubao',
      mediaType: 'video',
      count: 1,
      thumbnailColors: const ['#333333', '#444444'],
    );
    notifier.addHistory(
      url: 'http://doubao.com/thread/a/#again',
      sourceType: 'douyin',
      mediaType: 'video',
      count: 99,
      thumbnailColors: const ['#AAAAAA', '#BBBBBB'],
    );

    final updated = notifier.current.items.first;
    expect(notifier.current.items, hasLength(2));
    expect(updated.id, original.id);
    expect(updated.url, original.url);
    expect(updated.sourceType, original.sourceType);
    expect(updated.mediaType, original.mediaType);
    expect(updated.count, original.count);
    expect(updated.thumbnailUrl, original.thumbnailUrl);
    expect(updated.parsedAt, now.millisecondsSinceEpoch);
  });

  test('批量删除只移除指定 ID', () {
    final prefs = _MemoryPreferences();
    var now = DateTime(2026, 7, 23, 10);
    final notifier = HistoryNotifier(prefs, now: () => now);
    for (final id in ['a', 'b', 'c']) {
      notifier.addHistory(
        url: 'https://doubao.com/thread/$id',
        sourceType: 'doubao',
        mediaType: 'image',
        count: 1,
        thumbnailColors: const ['#111111', '#222222'],
      );
      now = now.add(const Duration(minutes: 1));
    }

    notifier
        .removeHistories({'a-id-does-not-exist', notifier.current.items[1].id});

    expect(notifier.current.items.map((item) => item.url), [
      'https://doubao.com/thread/c',
      'https://doubao.com/thread/a',
    ]);
  });

  test('时间格式同年省略年份，跨年显示年份', () {
    final reference = DateTime(2026, 7, 23, 20);

    expect(
      formatHistoryTimestamp(
        DateTime(2026, 7, 23, 7, 10).millisecondsSinceEpoch,
        referenceTime: reference,
      ),
      '7/23 07:10',
    );
    expect(
      formatHistoryTimestamp(
        DateTime(2026, 2, 3, 18, 20).millisecondsSinceEpoch,
        referenceTime: reference,
      ),
      '2/3 18:20',
    );
    expect(
      formatHistoryTimestamp(
        DateTime(2025, 12, 31, 23, 59).millisecondsSinceEpoch,
        referenceTime: reference,
      ),
      '2025/12/31 23:59',
    );
  });

  test('日期范围包含起止日全天', () {
    final start = DateTime(2026, 7, 10);
    final end = DateTime(2026, 7, 12);

    expect(
      isHistoryItemInRange(
        _item(
          id: 'start',
          url: 'https://example.com/start',
          parsedAt: DateTime(2026, 7, 10),
        ),
        start,
        end,
      ),
      isTrue,
    );
    expect(
      isHistoryItemInRange(
        _item(
          id: 'end',
          url: 'https://example.com/end',
          parsedAt: DateTime(2026, 7, 12, 23, 59, 59, 999),
        ),
        start,
        end,
      ),
      isTrue,
    );
    expect(
      isHistoryItemInRange(
        _item(
          id: 'after',
          url: 'https://example.com/after',
          parsedAt: DateTime(2026, 7, 13),
        ),
        start,
        end,
      ),
      isFalse,
    );
  });

  test('清除缓存不会删除历史记录或其他设置', () async {
    final cacheDir =
        await Directory.systemTemp.createTemp('doubao_nomark_cache_test_');
    addTearDown(() async {
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    });
    await File('${cacheDir.path}${Platform.pathSeparator}preview.jpg')
        .writeAsBytes([1, 2, 3]);
    final prefs = _MemoryPreferences({
      'history_items': '[{"id":"kept"}]',
      'settings_darkMode': true,
    });
    final notifier = SettingsNotifier(
      prefs,
      cacheDirectory: () async => cacheDir,
    );

    await notifier.clearCache();

    expect(await cacheDir.exists(), isTrue);
    expect(await cacheDir.list().isEmpty, isTrue);
    expect(prefs.getString('history_items'), '[{"id":"kept"}]');
    expect(prefs.getBool('settings_darkMode'), isTrue);
  });

  test('黑夜模式会持久化并在重新加载后恢复', () async {
    final prefs = _MemoryPreferences();
    final notifier = SettingsNotifier(prefs);

    notifier.setDarkMode(true);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.current.darkMode, isTrue);
    expect(prefs.getBool('settings_darkMode'), isTrue);
    expect(SettingsNotifier(prefs).current.darkMode, isTrue);
  });
}
