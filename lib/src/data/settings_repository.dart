import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/app_models.dart';
import 'app_database.dart';
import 'model_codec.dart';

class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;

  Future<AppSettings> loadSettings() async {
    final values = await _loadSettingsMap();
    return AppSettings(
      localeMode: decodeLocaleMode(values['localeMode']),
      transcriptionMode: decodeTranscriptionMode(values['transcriptionMode']),
      failureHandling: decodeFailureHandling(values['failureHandling']),
      audioRetentionPolicy: decodeAudioRetentionPolicy(
        values['audioRetentionPolicy'],
      ),
      checkUpdatesOnStartup: values['checkUpdatesOnStartup'] != 'false',
      callsign: values['callsign'] ?? '',
      qth: values['qth'] ?? '',
    );
  }

  Future<bool> loadSetupCompleted() async {
    final values = await _loadSettingsMap();
    return values['setupCompleted'] == 'true';
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _saveMany({
      'localeMode': encodeLocaleMode(settings.localeMode),
      'transcriptionMode': encodeTranscriptionMode(settings.transcriptionMode),
      'failureHandling': encodeFailureHandling(settings.failureHandling),
      'audioRetentionPolicy': encodeAudioRetentionPolicy(
        settings.audioRetentionPolicy,
      ),
      'checkUpdatesOnStartup': settings.checkUpdatesOnStartup.toString(),
      'callsign': settings.callsign,
      'qth': settings.qth,
    });
  }

  Future<void> saveCallsign(String callsign) async {
    await _saveSetting('callsign', callsign);
  }

  Future<List<StationEquipment>> loadEquipment() async {
    final values = await _loadSettingsMap();
    final json = values['stationEquipment'];
    if (json == null || json.isEmpty) {
      return const [];
    }
    try {
      final list = jsonDecode(json) as List<Object?>;
      return list.whereType<Map<String, Object?>>().map((item) {
        return StationEquipment(
          name: item['name'] as String? ?? '',
          antenna: item['antenna'] as String? ?? '',
          powerOptions: (item['powerOptions'] as List<Object?>?)
                  ?.whereType<String>()
                  .toList() ??
              const [],
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveEquipment(List<StationEquipment> equipment) async {
    final json = jsonEncode([
      for (final eq in equipment)
        {
          'name': eq.name,
          'antenna': eq.antenna,
          'powerOptions': eq.powerOptions,
        },
    ]);
    await _saveSetting('stationEquipment', json);
  }

  Future<void> saveSetupCompleted(bool completed) async {
    await _saveSetting('setupCompleted', completed.toString());
  }

  Future<bool> loadWelcomeShown() async {
    final values = await _loadSettingsMap();
    return values['welcomeShown'] == 'true';
  }

  Future<void> saveWelcomeShown() async {
    await _saveSetting('welcomeShown', 'true');
  }

  Future<Map<String, String>> _loadSettingsMap() async {
    final db = await _database.instance;
    final rows = await db.query('app_settings');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> _saveMany(Map<String, String> values) async {
    final db = await _database.instance;
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await _saveSettingWithDatabase(txn, entry.key, entry.value);
      }
    });
  }

  Future<void> _saveSetting(String key, String value) async {
    final db = await _database.instance;
    await _saveSettingWithDatabase(db, key, value);
  }

  Future<void> _saveSettingWithDatabase(
    DatabaseExecutor db,
    String key,
    String value,
  ) async {
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
