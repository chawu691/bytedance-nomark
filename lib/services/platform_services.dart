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
