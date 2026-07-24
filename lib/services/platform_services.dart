import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const platformChannel = MethodChannel('io.github.bytedance_nomark/platform');

bool get isOhos => Platform.operatingSystem == 'ohos';

Future<Directory> getAppCacheDirectory() async {
  if (!isOhos) return getTemporaryDirectory();
  final path = await platformChannel.invokeMethod<String>('getCacheDir');
  if (path == null || path.isEmpty) {
    throw const FileSystemException('无法获取鸿蒙缓存目录');
  }
  return Directory(path);
}

class OhosMediaFile {
  final String path;
  final String mediaType;
  final String fileName;

  const OhosMediaFile({
    required this.path,
    required this.mediaType,
    required this.fileName,
  });

  Map<String, Object> toMap() => {
        'path': path,
        'mediaType': mediaType,
        'fileName': fileName,
      };
}

class OhosSaveResult {
  final Set<int> savedIndices;
  final Map<int, String> errors;
  final bool cancelled;

  const OhosSaveResult({
    this.savedIndices = const {},
    this.errors = const {},
    this.cancelled = false,
  });
}

Future<OhosSaveResult> saveOhosMediaBatch(List<OhosMediaFile> files) async {
  final raw = await platformChannel.invokeMethod<Map<Object?, Object?>>(
    'saveMediaBatch',
    {'files': files.map((file) => file.toMap()).toList()},
  );
  if (raw == null) return const OhosSaveResult();
  final saved = (raw['savedIndices'] as List<Object?>? ?? const [])
      .whereType<num>()
      .map((value) => value.toInt())
      .toSet();
  final rawErrors = raw['errors'] as Map<Object?, Object?>? ?? const {};
  return OhosSaveResult(
    savedIndices: saved,
    errors: rawErrors.map(
      (key, value) => MapEntry(int.parse(key.toString()), value.toString()),
    ),
    cancelled: raw['cancelled'] == true,
  );
}

// ───────────────────────── 震动反馈 ─────────────────────────

/// 震动反馈等级
enum HapticLevel {
  light, // 轻震动：点击解析按钮、点击复选框
  medium, // 中震动：开关切换、下载完成
  heavy, // 强震动：切换解析模式
}

/// 触发震动反馈（自动适配 Android/iOS/HarmonyOS）
Future<void> triggerHaptic(HapticLevel level) async {
  if (isOhos) {
    try {
      await platformChannel
          .invokeMethod('hapticFeedback', {'level': level.name});
    } catch (_) {}
    return;
  }
  // Android/iOS 走 Flutter HapticFeedback
  switch (level) {
    case HapticLevel.light:
      await HapticFeedback.lightImpact();
      break;
    case HapticLevel.medium:
      await HapticFeedback.mediumImpact();
      break;
    case HapticLevel.heavy:
      await HapticFeedback.heavyImpact();
      break;
  }
}
