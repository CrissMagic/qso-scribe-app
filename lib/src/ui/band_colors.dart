import 'package:flutter/material.dart';

import 'theme.dart';

const _bandPalette = <String, Color>{
  '160m': Color(0xFFDC2626),
  '80m': Color(0xFFEA580C),
  '60m': Color(0xFFD97706),
  '40m': Color(0xFFCA8A04),
  '30m': Color(0xFF65A30D),
  '20m': Color(0xFF16A34A),
  '17m': Color(0xFF0891B2),
  '15m': Color(0xFF2563EB),
  '12m': Color(0xFF7C3AED),
  '10m': Color(0xFFC026D3),
  '6m': Color(0xFFDB2777),
  '4m': Color(0xFFE11D48),
  '2m': Color(0xFF0D9488),
  '1.25m': Color(0xFF0F766E),
  '70cm': Color(0xFF4F46E5),
  '33cm': Color(0xFF6366F1),
  '23cm': Color(0xFF818CF8),
};

String _normalizeBand(String input) {
  final trimmed = input.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  if (_bandPalette.containsKey(trimmed)) return trimmed;
  final digits = trimmed.replaceAll(RegExp(r'[^0-9.]'), '');
  if (digits.isEmpty) return '';
  final value = double.tryParse(digits);
  if (value == null) return '';
  final candidates = _bandPalette.keys.where((key) {
    final numeric = double.tryParse(key.replaceAll('m', ''));
    return numeric != null && (numeric - value).abs() < 0.01;
  });
  return candidates.isEmpty ? '' : candidates.first;
}

Color bandColor(String? band, {Color fallback = const Color(0xFF4ADE80)}) {
  if (band == null) return fallback;
  final key = _normalizeBand(band);
  if (key.isEmpty) return fallback;
  return _bandPalette[key] ?? fallback;
}

Color bandColorDim(String? band, BuildContext context, {double alpha = 0.18}) {
  final osc = Theme.of(context).extension<OscilloscopeColors>();
  final base = bandColor(
    band,
    fallback: osc?.phosphor ?? const Color(0xFF4ADE80),
  );
  return base.withAlpha((255 * alpha).round());
}
