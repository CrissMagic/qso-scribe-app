import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AppDirectoryProvider = Future<Directory> Function();

class QsoArtifactService {
  QsoArtifactService({AppDirectoryProvider? appDirectoryProvider})
    : _appDirectoryProvider =
          appDirectoryProvider ?? getApplicationDocumentsDirectory;

  final AppDirectoryProvider _appDirectoryProvider;

  Future<String> copyAudioImportToAppStorage(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw StateError('audio_file_missing');
    }
    final appDir = await _appDirectoryProvider();
    final audioDir = Directory(p.join(appDir.path, 'imports', 'audio'));
    if (!audioDir.existsSync()) {
      await audioDir.create(recursive: true);
    }
    final extension = p.extension(source.path);
    final originalName = p.basenameWithoutExtension(source.path);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final fileName =
        '${timestamp}_$originalName${extension.isEmpty ? '.audio' : extension}';
    final retainedPath = p.join(audioDir.path, fileName);
    return source.copy(retainedPath).then((file) => file.path);
  }

  Future<List<MapEntry<String, String>>> trashOwnedAudioFileIfExists(
    String path,
  ) async {
    final appRoot = await _appRoot();
    final trashDir = Directory(p.join(appRoot, '.trash'));
    final trashFiles = <MapEntry<String, String>>[];
    for (final file in _audioCandidates(path)) {
      if (!file.existsSync()) continue;
      final filePath = p.normalize(file.absolute.path);
      if (!_isOwnedPath(filePath, appRoot)) continue;
      if (!trashDir.existsSync()) {
        await trashDir.create(recursive: true);
      }
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final dest = p.join(trashDir.path, '${stamp}_${p.basename(filePath)}');
      await file.rename(dest);
      trashFiles.add(MapEntry(dest, filePath));
    }
    return trashFiles;
  }

  Future<void> restoreFromTrash(
    List<MapEntry<String, String>> trashFiles,
  ) async {
    if (trashFiles.isEmpty) return;
    final appRoot = await _appRoot();
    for (final file in trashFiles) {
      final src = File(file.key);
      if (!src.existsSync()) continue;
      final originalPath = p.normalize(file.value);
      if (!_isOwnedPath(originalPath, appRoot)) continue;
      await Directory(p.dirname(originalPath)).create(recursive: true);
      await src.rename(originalPath);
    }
  }

  Future<void> deleteOwnedAudioFileIfExists(String path) async {
    final appRoot = await _appRoot();
    for (final file in _audioCandidates(path)) {
      if (!file.existsSync()) continue;
      final filePath = p.normalize(file.absolute.path);
      if (_isOwnedPath(filePath, appRoot)) {
        await file.delete();
      }
    }
  }

  Future<String> _appRoot() async {
    final appDir = await _appDirectoryProvider();
    return p.normalize(appDir.path);
  }

  List<File> _audioCandidates(String path) {
    return [
      File(path),
      if (p.extension(path).toLowerCase() == '.pcm')
        File(p.setExtension(path, '.wav')),
    ];
  }

  bool _isOwnedPath(String filePath, String appRoot) {
    return filePath == appRoot || p.isWithin(appRoot, filePath);
  }
}
