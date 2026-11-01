import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Préférences locales, stockées dans un unique fichier JSON du dossier de
/// support de l'application.
///
/// Toute erreur (plugin absent, disque en lecture seule) retombe sur la valeur
/// par défaut : une préférence d'affichage ne doit jamais empêcher l'app de
/// démarrer.
class SettingsStore {
  static const String _fileName = 'settings.json';
  static const String _checkOnLaunchKey = 'checkOnLaunch';
  static const String _appIconKey = 'appIcon';
  static const String _deviceIdKey = 'deviceId';

  Future<File?> _file() async {
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      return File('${directory.path}/$_fileName');
    } catch (error) {
      debugPrint('Dossier de préférences indisponible : $error');
      return null;
    }
  }

  Future<bool> loadCheckOnLaunch({bool fallback = true}) async {
    final file = await _file();
    if (file == null) return fallback;
    try {
      if (!await file.exists()) return fallback;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data[_checkOnLaunchKey] is bool) {
        return data[_checkOnLaunchKey] as bool;
      }
    } catch (error) {
      debugPrint('Préférences illisibles : $error');
    }
    return fallback;
  }

  Future<String> loadAppIcon({String fallback = 'default'}) async {
    final file = await _file();
    if (file == null) return fallback;
    try {
      if (!await file.exists()) return fallback;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data[_appIconKey] is String) {
        return data[_appIconKey] as String;
      }
    } catch (error) {
      debugPrint('Préférences illisibles : $error');
    }
    return fallback;
  }

  /// Identifiant anonyme de l'appareil, créé une seule fois puis conservé.
  /// Il ne sert qu'au comptage d'usage anonyme du relais IA : ni compte, ni donnée
  /// personnelle.
  Future<String> deviceId() async {
    final file = await _file();
    if (file != null) {
      try {
        if (await file.exists()) {
          final data = jsonDecode(await file.readAsString());
          final stored = data is Map ? data[_deviceIdKey] : null;
          if (stored is String && _deviceIdPattern.hasMatch(stored)) {
            return stored;
          }
        }
      } catch (error) {
        debugPrint('Identifiant d’appareil illisible : $error');
      }
    }
    final generated = _newDeviceId();
    await _updateValue(_deviceIdKey, generated);
    return generated;
  }

  static final RegExp _deviceIdPattern = RegExp(r'^[a-f0-9]{32}$');

  static String _newDeviceId() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 16; index++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Future<void> saveCheckOnLaunch(bool value) async {
    await _updateValue(_checkOnLaunchKey, value);
  }

  Future<void> saveAppIcon(String value) async {
    await _updateValue(_appIconKey, value);
  }

  Future<void> _updateValue(String key, Object value) async {
    final file = await _file();
    if (file == null) return;
    try {
      final Map<String, dynamic> data;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } else {
        data = <String, dynamic>{};
      }
      data[key] = value;
      await file.writeAsString(jsonEncode(data));
    } catch (error) {
      debugPrint('Préférences non enregistrées : $error');
    }
  }
}
