import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qso_scribe_app/src/services/qso_artifact_service.dart';

void main() {
  test('copies imported audio into app storage', () async {
    final temp = await Directory.systemTemp.createTemp('qso-artifact-');
    try {
      final appDir = Directory(p.join(temp.path, 'app'))..createSync();
      final source = File(p.join(temp.path, 'source.wav'))
        ..writeAsStringSync('audio');
      final service = QsoArtifactService(
        appDirectoryProvider: () async => appDir,
      );

      final retainedPath = await service.copyAudioImportToAppStorage(
        source.path,
      );

      expect(File(retainedPath).readAsStringSync(), 'audio');
      expect(
        p.isWithin(p.join(appDir.path, 'imports', 'audio'), retainedPath),
        isTrue,
      );
      expect(p.basename(retainedPath), endsWith('_source.wav'));
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('deletes only app-owned audio candidates', () async {
    final temp = await Directory.systemTemp.createTemp('qso-artifact-');
    try {
      final appDir = Directory(p.join(temp.path, 'app'))..createSync();
      final ownedDir = Directory(p.join(appDir.path, 'audio'))..createSync();
      final ownedPcm = File(p.join(ownedDir.path, 'qso.pcm'))
        ..writeAsStringSync('pcm');
      final ownedWav = File(p.join(ownedDir.path, 'qso.wav'))
        ..writeAsStringSync('wav');
      final external = File(p.join(temp.path, 'external.wav'))
        ..writeAsStringSync('external');
      final service = QsoArtifactService(
        appDirectoryProvider: () async => appDir,
      );

      await service.deleteOwnedAudioFileIfExists(ownedPcm.path);
      await service.deleteOwnedAudioFileIfExists(external.path);

      expect(ownedPcm.existsSync(), isFalse);
      expect(ownedWav.existsSync(), isFalse);
      expect(external.existsSync(), isTrue);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('trashes and restores app-owned audio', () async {
    final temp = await Directory.systemTemp.createTemp('qso-artifact-');
    try {
      final appDir = Directory(p.join(temp.path, 'app'))..createSync();
      final ownedDir = Directory(p.join(appDir.path, 'audio'))..createSync();
      final owned = File(p.join(ownedDir.path, 'qso.wav'))
        ..writeAsStringSync('audio');
      final service = QsoArtifactService(
        appDirectoryProvider: () async => appDir,
      );

      final trashFiles = await service.trashOwnedAudioFileIfExists(owned.path);

      expect(trashFiles, hasLength(1));
      expect(owned.existsSync(), isFalse);
      expect(File(trashFiles.single.key).existsSync(), isTrue);

      await service.restoreFromTrash(trashFiles);

      expect(owned.readAsStringSync(), 'audio');
      expect(File(trashFiles.single.key).existsSync(), isFalse);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
