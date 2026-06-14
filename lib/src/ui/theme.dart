import 'package:flutter/material.dart';

class OscilloscopeColors extends ThemeExtension<OscilloscopeColors> {
  const OscilloscopeColors({
    required this.phosphor,
    required this.phosphorDim,
    required this.amber,
    required this.gridLine,
    required this.trace,
    required this.statusDraft,
    required this.statusReview,
    required this.statusConfirmed,
    required this.statusExported,
    required this.statusFailed,
    required this.rec,
  });

  final Color phosphor;
  final Color phosphorDim;
  final Color amber;
  final Color gridLine;
  final Color trace;
  final Color statusDraft;
  final Color statusReview;
  final Color statusConfirmed;
  final Color statusExported;
  final Color statusFailed;
  final Color rec;

  @override
  OscilloscopeColors copyWith({
    Color? phosphor,
    Color? phosphorDim,
    Color? amber,
    Color? gridLine,
    Color? trace,
    Color? statusDraft,
    Color? statusReview,
    Color? statusConfirmed,
    Color? statusExported,
    Color? statusFailed,
    Color? rec,
  }) {
    return OscilloscopeColors(
      phosphor: phosphor ?? this.phosphor,
      phosphorDim: phosphorDim ?? this.phosphorDim,
      amber: amber ?? this.amber,
      gridLine: gridLine ?? this.gridLine,
      trace: trace ?? this.trace,
      statusDraft: statusDraft ?? this.statusDraft,
      statusReview: statusReview ?? this.statusReview,
      statusConfirmed: statusConfirmed ?? this.statusConfirmed,
      statusExported: statusExported ?? this.statusExported,
      statusFailed: statusFailed ?? this.statusFailed,
      rec: rec ?? this.rec,
    );
  }

  @override
  OscilloscopeColors lerp(ThemeExtension<OscilloscopeColors>? other, double t) {
    if (other is! OscilloscopeColors) {
      return this;
    }
    return OscilloscopeColors(
      phosphor: Color.lerp(phosphor, other.phosphor, t)!,
      phosphorDim: Color.lerp(phosphorDim, other.phosphorDim, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      gridLine: Color.lerp(gridLine, other.gridLine, t)!,
      trace: Color.lerp(trace, other.trace, t)!,
      statusDraft: Color.lerp(statusDraft, other.statusDraft, t)!,
      statusReview: Color.lerp(statusReview, other.statusReview, t)!,
      statusConfirmed: Color.lerp(statusConfirmed, other.statusConfirmed, t)!,
      statusExported: Color.lerp(statusExported, other.statusExported, t)!,
      statusFailed: Color.lerp(statusFailed, other.statusFailed, t)!,
      rec: Color.lerp(rec, other.rec, t)!,
    );
  }
}

const _darkPhosphor = Color(0xFF4ADE80);
const _darkAmber = Color(0xFFFBBF24);
const _lightPhosphor = Color(0xFF047857);
const _lightAmber = Color(0xFFB45309);

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: isDark ? _darkPhosphor : _lightPhosphor,
    onPrimary: isDark ? const Color(0xFF052E16) : Colors.white,
    primaryContainer: isDark
        ? const Color(0xFF0F3D2A)
        : const Color(0xFFD1FAE5),
    onPrimaryContainer: isDark
        ? const Color(0xFFBBF7D0)
        : const Color(0xFF064E3B),
    secondary: isDark ? _darkAmber : _lightAmber,
    onSecondary: isDark ? const Color(0xFF3D2A00) : Colors.white,
    secondaryContainer: isDark
        ? const Color(0xFF3D2A00)
        : const Color(0xFFFEF3C7),
    onSecondaryContainer: isDark
        ? const Color(0xFFFDE68A)
        : const Color(0xFF78350F),
    tertiary: isDark ? const Color(0xFF22D3EE) : const Color(0xFF0E7490),
    onTertiary: isDark ? const Color(0xFF003744) : Colors.white,
    error: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
    onError: isDark ? const Color(0xFF450A0A) : Colors.white,
    errorContainer: isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2),
    onErrorContainer: isDark
        ? const Color(0xFFFCA5A5)
        : const Color(0xFF7F1D1D),
    surface: isDark ? const Color(0xFF0F1623) : const Color(0xFFFFFFFF),
    onSurface: isDark ? const Color(0xFFD1FAE5) : const Color(0xFF0F172A),
    surfaceContainerHighest: isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9),
    onSurfaceVariant: isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569),
    outline: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
    outlineVariant: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
    scrim: isDark ? const Color(0xFF000000) : const Color(0xFF0F172A),
    shadow: isDark ? const Color(0xFF000000) : const Color(0x1A000000),
  );

  final oscilloscope = OscilloscopeColors(
    phosphor: isDark ? _darkPhosphor : _lightPhosphor,
    phosphorDim: isDark ? const Color(0xFF166534) : const Color(0xFFA7F3D0),
    amber: isDark ? _darkAmber : _lightAmber,
    gridLine: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
    trace: isDark ? const Color(0xFF22D3EE) : const Color(0xFF0891B2),
    statusDraft: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
    statusReview: isDark ? _darkAmber : _lightAmber,
    statusConfirmed: isDark ? _darkPhosphor : _lightPhosphor,
    statusExported: isDark ? const Color(0xFF22D3EE) : const Color(0xFF0891B2),
    statusFailed: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
    rec: const Color(0xFFFF5252),
  );

  const monoFamily = 'monospace';
  final baseTextTheme = isDark ? Typography().white : Typography().black;

  TextTheme buildTextTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontFamily: monoFamily),
      displayMedium: base.displayMedium?.copyWith(
        fontFamily: monoFamily,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 1.5,
      ),
      displaySmall: base.displaySmall?.copyWith(fontFamily: monoFamily),
      headlineLarge: base.headlineLarge?.copyWith(fontFamily: monoFamily),
      headlineMedium: base.headlineMedium?.copyWith(fontFamily: monoFamily),
      headlineSmall: base.headlineSmall?.copyWith(fontFamily: monoFamily),
      labelLarge: base.labelLarge?.copyWith(
        fontFamily: monoFamily,
        letterSpacing: 1.2,
      ),
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF0A0F1A)
        : const Color(0xFFF0F4F8),
    extensions: [oscilloscope],
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: monoFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: colorScheme.onSurface,
      ),
      shape: Border(bottom: BorderSide(color: oscilloscope.gridLine, width: 1)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: oscilloscope.gridLine, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: oscilloscope.gridLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: oscilloscope.gridLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      labelStyle: TextStyle(
        fontFamily: monoFamily,
        fontSize: 13,
        letterSpacing: 0.8,
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(
          fontFamily: monoFamily,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(
          fontFamily: monoFamily,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontFamily: monoFamily, letterSpacing: 0.8),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: monoFamily,
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          size: 22,
        );
      }),
    ),
    dividerTheme: DividerThemeData(
      color: oscilloscope.gridLine,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surface,
      side: BorderSide(color: oscilloscope.gridLine),
      labelStyle: TextStyle(
        fontFamily: monoFamily,
        fontSize: 12,
        letterSpacing: 0.6,
        color: colorScheme.onSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    textTheme: buildTextTheme(baseTextTheme),
  );
}
