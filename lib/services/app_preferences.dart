import 'package:shared_preferences/shared_preferences.dart';

import 'platform_services.dart';

abstract class AppPreferences {
  String? getString(String key);
  bool? getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
  Future<void> remove(String key);
}

class SharedPreferencesAdapter implements AppPreferences {
  final SharedPreferences preferences;

  const SharedPreferencesAdapter(this.preferences);

  @override
  String? getString(String key) => preferences.getString(key);

  @override
  bool? getBool(String key) => preferences.getBool(key);

  @override
  Future<void> setString(String key, String value) async {
    await preferences.setString(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await preferences.setBool(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await preferences.remove(key);
  }
}

class OhosPreferencesAdapter implements AppPreferences {
  final Map<String, Object?> _values;

  OhosPreferencesAdapter(this._values);

  static Future<OhosPreferencesAdapter> load() async {
    final raw = await platformChannel
            .invokeMethod<Map<Object?, Object?>>('loadPreferences') ??
        const {};
    return OhosPreferencesAdapter(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
    await _set(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
    await _set(key, value);
  }

  Future<void> _set(String key, Object value) {
    return platformChannel.invokeMethod<void>(
      'setPreference',
      {'key': key, 'value': value},
    );
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
    await platformChannel.invokeMethod<void>(
      'removePreference',
      {'key': key},
    );
  }
}

Future<AppPreferences> loadAppPreferences() async {
  if (isOhos) return OhosPreferencesAdapter.load();
  return SharedPreferencesAdapter(await SharedPreferences.getInstance());
}
