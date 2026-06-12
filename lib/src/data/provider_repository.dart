import '../domain/app_models.dart';
import 'app_database.dart';

class ProviderRepository {
  ProviderRepository(this._database);

  final AppDatabase _database;

  Future<List<ProviderProfile>> listProviders() async {
    final db = await _database.instance;
    final rows = await db.query(
      'provider_profiles',
      where: 'user_configured = 1',
      orderBy: 'name ASC',
    );
    return rows.map(_decodeProvider).toList();
  }

  Future<ProviderConnection?> findConnection(String id) async {
    final db = await _database.instance;
    final rows = await db.query(
      'provider_profiles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    return ProviderConnection(
      id: row['id'] as String,
      name: row['name'] as String,
      type: row['type'] as String,
      baseUrl: row['base_url'] as String?,
      apiKey: row['api_key'] as String?,
    );
  }

  Future<void> saveProvider({
    required String id,
    required String name,
    required String type,
    String? baseUrl,
    String? apiKey,
  }) async {
    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.query(
      'provider_profiles',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('provider_profiles', {
        'id': id,
        'name': name,
        'type': type,
        'base_url': baseUrl,
        'api_key': apiKey,
        'user_configured': 1,
        'created_at': now,
        'updated_at': now,
      });
      return;
    }

    await db.update(
      'provider_profiles',
      {
        'name': name,
        'type': type,
        'base_url': baseUrl,
        'api_key': apiKey,
        'user_configured': 1,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  ProviderProfile _decodeProvider(Map<String, Object?> row) {
    final apiKey = row['api_key'] as String?;
    return ProviderProfile(
      id: row['id'] as String,
      name: row['name'] as String,
      type: row['type'] as String,
      baseUrl: row['base_url'] as String?,
      hasApiKey: apiKey != null && apiKey.isNotEmpty,
    );
  }
}

class ProviderConnection {
  const ProviderConnection({
    required this.id,
    required this.name,
    required this.type,
    this.baseUrl,
    this.apiKey,
  });

  final String id;
  final String name;
  final String type;
  final String? baseUrl;
  final String? apiKey;

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;
}
