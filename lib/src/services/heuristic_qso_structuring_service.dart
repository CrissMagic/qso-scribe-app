import '../domain/app_models.dart';
import '../domain/service_contracts.dart';

class HeuristicQsoStructuringService implements QsoStructuringService {
  const HeuristicQsoStructuringService();

  QsoDraft createDraftFromText({
    required String rawText,
    String? audioPath,
    DateTime? dateTime,
    LogStatus status = LogStatus.needsReview,
  }) {
    final callsign = _extractCallsign(rawText);
    final frequency = _extractFrequency(rawText);
    final band = _extractBand(rawText, frequency);
    final mode = _extractMode(rawText);
    final reports = _extractSignalReports(rawText);

    return QsoDraft(
      callsign: QsoField(
        value: callsign ?? '',
        confidence: callsign == null ? 0.2 : 0.78,
        sourceText: rawText,
      ),
      dateTime: QsoField(value: dateTime ?? _extractDateTime(rawText)),
      band: QsoField(value: band ?? '', confidence: band == null ? 0.2 : 0.8),
      frequency: QsoField(
        value: frequency ?? '',
        confidence: frequency == null ? 0.2 : 0.84,
      ),
      mode: QsoField(value: mode ?? '', confidence: mode == null ? 0.2 : 0.8),
      sentRst: QsoField(
        value: reports.sent ?? '',
        confidence: reports.sent == null ? 0.2 : 0.7,
      ),
      receivedRst: QsoField(
        value: reports.received ?? '',
        confidence: reports.received == null ? 0.2 : 0.7,
      ),
      status: status,
      audioPath: audioPath,
      rawTranscript: rawText,
    );
  }

  @override
  Future<QsoDraftPatch> applyTranscript(
    TranscriptSegment segment,
    QsoDraft currentDraft,
  ) async {
    final patchDraft = createDraftFromText(
      rawText: segment.text,
      audioPath: currentDraft.audioPath,
      dateTime: currentDraft.dateTime.value,
      status: currentDraft.status,
    );
    return QsoDraftPatch(
      sourceSegment: segment,
      updatedFields: {
        if (patchDraft.callsign.value.isNotEmpty)
          'callsign': patchDraft.callsign,
        if (patchDraft.band.value.isNotEmpty) 'band': patchDraft.band,
        if (patchDraft.frequency.value.isNotEmpty)
          'frequency': patchDraft.frequency,
        if (patchDraft.mode.value.isNotEmpty) 'mode': patchDraft.mode,
        if (patchDraft.sentRst.value.isNotEmpty) 'sentRst': patchDraft.sentRst,
        if (patchDraft.receivedRst.value.isNotEmpty)
          'receivedRst': patchDraft.receivedRst,
      },
    );
  }

  String? _extractCallsign(String text) {
    final normalized = text.toUpperCase();
    final direct = RegExp(
      r'\b[A-Z]{1,2}[0-9][A-Z0-9]{1,4}\b',
    ).firstMatch(normalized);
    if (direct != null) {
      return direct.group(0);
    }

    final spoken = _spokenCallsign(text);
    if (spoken != null &&
        RegExp(r'^[A-Z]{1,2}[0-9][A-Z0-9]{1,4}$').hasMatch(spoken)) {
      return spoken;
    }
    return null;
  }

  String? _spokenCallsign(String text) {
    final tokens = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 -]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    final buffer = StringBuffer();
    for (final token in tokens) {
      final mapped = _phoneticMap[token] ?? _numberWords[token];
      if (mapped != null) {
        buffer.write(mapped);
      } else if (RegExp(r'^[a-z]$').hasMatch(token)) {
        buffer.write(token.toUpperCase());
      } else if (RegExp(r'^[0-9]$').hasMatch(token)) {
        buffer.write(token);
      } else if (buffer.isNotEmpty && buffer.length >= 3) {
        break;
      } else {
        buffer.clear();
      }
    }
    return buffer.isEmpty ? null : buffer.toString();
  }

  String? _extractFrequency(String text) {
    final match = RegExp(
      r'\b(1[0-9]|2[0-9]|4[0-9]|5[0-9]|7[0-9]|14|18|21|24|28|50|144|430|432)(?:\.(\d{2,4}))?\b',
    ).firstMatch(text);
    return match?.group(0);
  }

  String? _extractBand(String text, String? frequency) {
    final direct = RegExp(
      r'\b(160m|80m|40m|30m|20m|17m|15m|12m|10m|6m|2m|70cm)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (direct != null) {
      return direct.group(0)!.toLowerCase();
    }

    final mhz = double.tryParse(frequency ?? '');
    if (mhz == null) {
      return null;
    }
    if (mhz >= 14 && mhz < 15) return '20m';
    if (mhz >= 7 && mhz < 8) return '40m';
    if (mhz >= 21 && mhz < 22) return '15m';
    if (mhz >= 28 && mhz < 30) return '10m';
    if (mhz >= 50 && mhz < 54) return '6m';
    if (mhz >= 144 && mhz < 148) return '2m';
    if (mhz >= 430 && mhz < 450) return '70cm';
    return null;
  }

  String? _extractMode(String text) {
    final match = RegExp(
      r'\b(SSB|USB|LSB|CW|FM|AM|FT8|FT4|RTTY)\b',
      caseSensitive: false,
    ).firstMatch(text);
    final value = match?.group(0);
    if (value == null) {
      return null;
    }
    return switch (value.toUpperCase()) {
      'USB' || 'LSB' => 'SSB',
      _ => value.toUpperCase(),
    };
  }

  DateTime? _extractDateTime(String text) {
    final isoDate = RegExp(
      r'\b(20\d{2})[-/](0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])(?:[ T](\d{1,2}):(\d{2}))?\b',
    ).firstMatch(text);
    if (isoDate == null) {
      return null;
    }
    final year = int.parse(isoDate.group(1)!);
    final month = int.parse(isoDate.group(2)!);
    final day = int.parse(isoDate.group(3)!);
    final hour = int.tryParse(isoDate.group(4) ?? '') ?? 0;
    final minute = int.tryParse(isoDate.group(5) ?? '') ?? 0;
    return DateTime(year, month, day, hour, minute);
  }

  ({String? sent, String? received}) _extractSignalReports(String text) {
    final reports = RegExp(r'\b([1-5][1-9]|[1-5]NN|5[1-9])\b')
        .allMatches(text.toUpperCase())
        .map((match) => match.group(1)!.replaceAll('NN', '99'))
        .toList();
    return (
      sent: reports.isNotEmpty ? reports.first : null,
      received: reports.length > 1
          ? reports[1]
          : reports.isNotEmpty
          ? reports.first
          : null,
    );
  }

  static const _phoneticMap = {
    'alpha': 'A',
    'alfa': 'A',
    'bravo': 'B',
    'charlie': 'C',
    'delta': 'D',
    'echo': 'E',
    'foxtrot': 'F',
    'golf': 'G',
    'hotel': 'H',
    'india': 'I',
    'juliett': 'J',
    'juliet': 'J',
    'kilo': 'K',
    'lima': 'L',
    'mike': 'M',
    'november': 'N',
    'oscar': 'O',
    'papa': 'P',
    'quebec': 'Q',
    'quebecq': 'Q',
    'romeo': 'R',
    'sierra': 'S',
    'tango': 'T',
    'uniform': 'U',
    'victor': 'V',
    'whiskey': 'W',
    'xray': 'X',
    'x-ray': 'X',
    'yankee': 'Y',
    'zulu': 'Z',
  };

  static const _numberWords = {
    'zero': '0',
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
  };
}
