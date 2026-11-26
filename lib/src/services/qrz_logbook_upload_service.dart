import 'dart:async';

import 'package:http/http.dart' as http;

import '../data/adif_codec.dart';
import '../domain/app_models.dart';

enum QrzUploadFailureReason {
  missingApiKey,
  requiredFieldsMissing,
  httpError,
  networkError,
  rejected,
  badResponse,
}

class QrzUploadException implements Exception {
  const QrzUploadException(this.reason, {this.statusCode, this.message});

  final QrzUploadFailureReason reason;
  final int? statusCode;
  final String? message;

  @override
  String toString() => message ?? reason.name;
}

class QrzUploadResult {
  const QrzUploadResult({this.remoteId});

  final String? remoteId;
}

class QrzLogbookUploadService {
  QrzLogbookUploadService({http.Client? httpClient, Uri? endpoint})
    : _httpClient = httpClient ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse('https://logbook.qrz.com/api');

  final http.Client _httpClient;
  final Uri _endpoint;

  Future<QrzUploadResult> upload({
    required String apiKey,
    required QsoDraft qso,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const QrzUploadException(QrzUploadFailureReason.missingApiKey);
    }
    if (qso.isFmo || !qso.hasRequiredFields) {
      throw const QrzUploadException(
        QrzUploadFailureReason.requiredFieldsMissing,
      );
    }

    http.Response response;
    try {
      response = await _httpClient
          .post(
            _endpoint,
            headers: const {
              'User-Agent': 'qso-scribe-app',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'KEY': apiKey.trim(),
              'ACTION': 'INSERT',
              'ADIF': toAdifRecord(qso),
            },
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const QrzUploadException(QrzUploadFailureReason.networkError);
    } on http.ClientException catch (error) {
      throw QrzUploadException(
        QrzUploadFailureReason.networkError,
        message: error.message,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QrzUploadException(
        QrzUploadFailureReason.httpError,
        statusCode: response.statusCode,
      );
    }

    final fields = parseQrzUploadResponse(response.body);
    final result = fields['RESULT']?.toUpperCase();
    if (result == 'OK') {
      final logIds = fields['LOGIDS'];
      return QrzUploadResult(
        remoteId: fields['LOGID'] ?? logIds?.split(',').first.trim(),
      );
    }
    if (result == 'FAIL') {
      throw QrzUploadException(
        QrzUploadFailureReason.rejected,
        message: fields['REASON'] ?? response.body.trim(),
      );
    }
    throw QrzUploadException(
      QrzUploadFailureReason.badResponse,
      message: response.body.trim(),
    );
  }

  void close() => _httpClient.close();
}

Map<String, String> parseQrzUploadResponse(String body) {
  final result = <String, String>{};
  for (final part in body.split(RegExp(r'[\r\n&]+'))) {
    final index = part.indexOf('=');
    if (index <= 0) {
      continue;
    }
    result[part.substring(0, index).trim().toUpperCase()] = part
        .substring(index + 1)
        .trim();
  }
  return result;
}
