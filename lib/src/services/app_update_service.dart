import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'release_info_service.dart';

typedef DownloadProgressCallback =
    void Function(int receivedBytes, int? totalBytes);
typedef TempDirectoryProvider = Future<Directory> Function();

enum AppUpdateFailureReason {
  httpError,
  networkError,
  timeout,
  fileSystemError,
  checksumMismatch,
  installPermissionRequired,
  installerUnavailable,
  invalidApkPath,
  platformError,
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.reason, {this.statusCode, this.message});

  final AppUpdateFailureReason reason;
  final int? statusCode;
  final String? message;

  @override
  String toString() {
    final code = statusCode == null ? '' : '-$statusCode';
    final detail = message == null ? '' : ': $message';
    return 'AppUpdateException(${reason.name}$code$detail)';
  }
}

class AppUpdateService {
  AppUpdateService({
    http.Client? httpClient,
    MethodChannel? methodChannel,
    TempDirectoryProvider? tempDirectoryProvider,
  }) : _httpClient = httpClient ?? http.Client(),
       _methodChannel =
           methodChannel ?? const MethodChannel('qso_scribe/app_update'),
       _tempDirectoryProvider = tempDirectoryProvider ?? getTemporaryDirectory;

  final http.Client _httpClient;
  final MethodChannel _methodChannel;
  final TempDirectoryProvider _tempDirectoryProvider;

  void close() {
    _httpClient.close();
  }

  Future<String> downloadApk(
    AppRelease release, {
    required DownloadProgressCallback onProgress,
  }) async {
    final uri = Uri.tryParse(release.apkAsset.downloadUrl);
    if (uri == null || !uri.hasScheme) {
      throw const AppUpdateException(AppUpdateFailureReason.networkError);
    }

    final request = http.Request('GET', uri)
      ..headers.addAll(const {
        'Accept': 'application/octet-stream',
        'User-Agent': 'qso-scribe-app',
      });

    final http.StreamedResponse response;
    try {
      response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const AppUpdateException(AppUpdateFailureReason.timeout);
    } on http.ClientException catch (error) {
      throw AppUpdateException(
        AppUpdateFailureReason.networkError,
        message: error.message,
      );
    } on SocketException catch (error) {
      throw AppUpdateException(
        AppUpdateFailureReason.networkError,
        message: error.message,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppUpdateException(
        AppUpdateFailureReason.httpError,
        statusCode: response.statusCode,
      );
    }

    final updateDir = await _updatesDirectory();
    final apkFile = File(
      p.join(
        updateDir.path,
        '${release.version}_${_safeFileName(release.apkAsset.name)}',
      ),
    );

    final fileSink = apkFile.openWrite();
    var receivedBytes = 0;
    var sinkClosed = false;

    Future<void> closeSink() async {
      if (!sinkClosed) {
        sinkClosed = true;
        await fileSink.close();
      }
    }

    try {
      await for (final chunk in response.stream.timeout(
        const Duration(minutes: 2),
      )) {
        receivedBytes += chunk.length;
        fileSink.add(chunk);
        onProgress(receivedBytes, response.contentLength);
      }
      await fileSink.flush();
      await closeSink();
    } on TimeoutException {
      await closeSink();
      await _deletePartialFile(apkFile);
      throw const AppUpdateException(AppUpdateFailureReason.timeout);
    } on FileSystemException catch (error) {
      await closeSink();
      await _deletePartialFile(apkFile);
      throw AppUpdateException(
        AppUpdateFailureReason.fileSystemError,
        message: error.message,
      );
    } on http.ClientException catch (error) {
      await closeSink();
      await _deletePartialFile(apkFile);
      throw AppUpdateException(
        AppUpdateFailureReason.networkError,
        message: error.message,
      );
    } on SocketException catch (error) {
      await closeSink();
      await _deletePartialFile(apkFile);
      throw AppUpdateException(
        AppUpdateFailureReason.networkError,
        message: error.message,
      );
    }

    final expectedDigest = release.apkAsset.sha256Digest;
    if (expectedDigest != null) {
      final actualDigest = await sha256.bind(apkFile.openRead()).first;
      if (actualDigest.toString().toLowerCase() !=
          expectedDigest.toLowerCase()) {
        await _deletePartialFile(apkFile);
        throw const AppUpdateException(AppUpdateFailureReason.checksumMismatch);
      }
    }

    return apkFile.path;
  }

  Future<void> openInstaller(String apkPath) async {
    if (apkPath.trim().isEmpty) {
      throw const AppUpdateException(AppUpdateFailureReason.invalidApkPath);
    }
    try {
      await _methodChannel.invokeMethod<void>('installApk', {'path': apkPath});
    } on PlatformException catch (error) {
      throw AppUpdateException(_failureReasonForCode(error.code));
    } on MissingPluginException catch (error) {
      throw AppUpdateException(
        AppUpdateFailureReason.platformError,
        message: error.message,
      );
    }
  }

  Future<Directory> _updatesDirectory() async {
    try {
      final tempDir = await _tempDirectoryProvider();
      final updateDir = Directory(p.join(tempDir.path, 'updates'));
      if (!updateDir.existsSync()) {
        await updateDir.create(recursive: true);
      }
      return updateDir;
    } on FileSystemException catch (error) {
      throw AppUpdateException(
        AppUpdateFailureReason.fileSystemError,
        message: error.message,
      );
    }
  }

  String _safeFileName(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty || !cleaned.toLowerCase().endsWith('.apk')
        ? 'qso-scribe-app-update-android.apk'
        : cleaned;
  }

  Future<void> _deletePartialFile(File file) async {
    if (file.existsSync()) {
      await file.delete();
    }
  }

  AppUpdateFailureReason _failureReasonForCode(String code) {
    return switch (code) {
      'install_permission_required' =>
        AppUpdateFailureReason.installPermissionRequired,
      'installer_unavailable' => AppUpdateFailureReason.installerUnavailable,
      'invalid_apk_path' => AppUpdateFailureReason.invalidApkPath,
      _ => AppUpdateFailureReason.platformError,
    };
  }
}
