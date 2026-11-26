import 'package:flutter/material.dart';

class OscilloscopeColors extends ThemeExtension<OscilloscopeColors> {
  const OscilloscopeColors({
    required this.phosphor,
    required this.gridLine,
    required this.statusDraft,
    required this.statusReview,
    required this.statusConfirmed,
    required this.statusExported,
    required this.statusFailed,
  });

  final Color phosphor;
  final Color gridLine;
  final Color statusDraft;
  final Color statusReview;
  final Color statusConfirmed;
  final Color statusExported;
  final Color statusFailed;

  @override
  OscilloscopeColors copyWith({
    Color? phosphor,
    Color? gridLine,
    Color? statusDraft,
    Color? statusReview,
    Color? statusConfirmed,
    Color? statusExported,
    Color? statusFailed,
  }) {
    return OscilloscopeColors(
      phosphor: phosphor ?? this.phosphor,
      gridLine: gridLine ?? this.gridLine,
      statusDraft: statusDraft ?? this.statusDraft,
      statusReview: statusReview ?? this.statusReview,
      statusConfirmed: statusConfirmed ?? this.statusConfirmed,
      statusExported: statusExported ?? this.statusExported,
      statusFailed: statusFailed ?? this.statusFailed,
    );
  }

  @override
  OscilloscopeColors lerp(ThemeExtension<OscilloscopeColors>? other, double t) {
    if (other is! OscilloscopeColors) {
      return this;
    }
    return OscilloscopeColors(
      phosphor: Color.lerp(phosphor, other.phosphor, t)!,
      gridLine: Color.lerp(gridLine, other.gridLine, t)!,
      statusDraft: Color.lerp(statusDraft, other.statusDraft, t)!,
      statusReview: Color.lerp(statusReview, other.statusReview, t)!,
      statusConfirmed: Color.lerp(statusConfirmed, other.statusConfirmed, t)!,
      statusExported: Color.lerp(statusExported, other.statusExported, t)!,
      statusFailed: Color.lerp(statusFailed, other.statusFailed, t)!,
    );
  }
}

const _darkPhosphor = Color(0xFF4ADE80);
const _darkAmber = Color(0xFFFBBF24);
const _lightPhosphor = Color(0xFF047857);
const _lightAmber = Color(0xFFB45309);

abstract final class AppLayout {
  static const smallGap = 8.0;
  static const groupGap = 12.0;
  static const gutter = 16.0;
  static const sectionGap = 24.0;
  static const controlHeight = 48.0;
  static const primaryActionHeight = 56.0;
  static const recordingActionHeight = 64.0;
  static const navigationHeight = 64.0;
  static const settingsPagePadding = EdgeInsets.fromLTRB(
    gutter,
    sectionGap,
    gutter,
    32,
  );

  static const controlRadius = BorderRadius.all(Radius.circular(8));
  static const panelRadius = BorderRadius.all(Radius.circular(12));
  static const modalRadius = Radius.circular(16);
  static const capsuleRadius = BorderRadius.all(Radius.circular(999));
}

/// QSO Scribe 的统一字号阶梯。
///
/// 业务组件通过语义角色使用公开层级；Material 未暴露为业务角色的槽位也在此集中定义，
/// 避免主题构建器出现第二套散落字号。
abstract final class AppTypeScale {
  static const double dataDisplay = 40;
  static const double pageTitle = 28;
  static const double metricValue = 20;
  static const double sectionTitle = 18;
  static const double itemTitle = 16;
  static const double body = 14;
  static const double supporting = 12;
  static const double micro = 11;

  static const double _materialDisplayLarge = 48;
  static const double _materialDisplaySmall = 32;
  static const double _materialHeadlineMedium = 24;
}

const appMonospaceFontFamily = 'monospace';
const appTabularFontFeatures = <FontFeature>[FontFeature.tabularFigures()];

/// 业务组件使用语义名称，而不是直接选择 Material 的视觉级别。
extension AppTextThemeRoles on TextTheme {
  TextStyle get appDataDisplay => displayMedium!;
  TextStyle get appPageTitle => headlineLarge!;
  TextStyle get appMetricValue => headlineSmall!;
  TextStyle get appSectionTitle => titleLarge!;
  TextStyle get appItemTitle => titleMedium!;
  TextStyle get appCompactTitle => titleSmall!;
  TextStyle get appLead => bodyLarge!;
  TextStyle get appBody => bodyMedium!;
  TextStyle get appSupporting => bodySmall!;
  TextStyle get appControlLabel => labelLarge!;
  TextStyle get appMetadata => labelMedium!;
  TextStyle get appMicroLabel => labelSmall!;
}

extension AppTextStyleRoles on TextStyle {
  TextStyle get appMonospace => copyWith(
    fontFamily: appMonospaceFontFamily,
    fontFeatures: appTabularFontFeatures,
  );

  TextStyle get appTabular => copyWith(fontFeatures: appTabularFontFeatures);
}

TextTheme _buildAppTextTheme(TextTheme base) {
  TextStyle style(
    TextStyle? source, {
    required double size,
    required FontWeight weight,
    required double height,
    double letterSpacing = 0,
    String? fontFamily,
    List<FontFeature>? fontFeatures,
  }) {
    return (source ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      fontFamily: fontFamily,
      fontFeatures: fontFeatures,
    );
  }

  return base.copyWith(
    displayLarge: style(
      base.displayLarge,
      size: AppTypeScale._materialDisplayLarge,
      weight: FontWeight.w700,
      height: 1,
    ),
    displayMedium: style(
      base.displayMedium,
      size: AppTypeScale.dataDisplay,
      weight: FontWeight.w700,
      height: 1,
      letterSpacing: 0.5,
      fontFamily: appMonospaceFontFamily,
      fontFeatures: appTabularFontFeatures,
    ),
    displaySmall: style(
      base.displaySmall,
      size: AppTypeScale._materialDisplaySmall,
      weight: FontWeight.w700,
      height: 1.1,
    ),
    headlineLarge: style(
      base.headlineLarge,
      size: AppTypeScale.pageTitle,
      weight: FontWeight.w700,
      height: 1.2,
    ),
    headlineMedium: style(
      base.headlineMedium,
      size: AppTypeScale._materialHeadlineMedium,
      weight: FontWeight.w700,
      height: 1.25,
    ),
    headlineSmall: style(
      base.headlineSmall,
      size: AppTypeScale.metricValue,
      weight: FontWeight.w600,
      height: 1.25,
    ),
    titleLarge: style(
      base.titleLarge,
      size: AppTypeScale.sectionTitle,
      weight: FontWeight.w700,
      height: 1.3,
    ),
    titleMedium: style(
      base.titleMedium,
      size: AppTypeScale.itemTitle,
      weight: FontWeight.w600,
      height: 1.35,
    ),
    titleSmall: style(
      base.titleSmall,
      size: AppTypeScale.body,
      weight: FontWeight.w600,
      height: 1.35,
    ),
    bodyLarge: style(
      base.bodyLarge,
      size: AppTypeScale.itemTitle,
      weight: FontWeight.w400,
      height: 1.5,
    ),
    bodyMedium: style(
      base.bodyMedium,
      size: AppTypeScale.body,
      weight: FontWeight.w400,
      height: 1.45,
    ),
    bodySmall: style(
      base.bodySmall,
      size: AppTypeScale.supporting,
      weight: FontWeight.w400,
      height: 1.4,
    ),
    labelLarge: style(
      base.labelLarge,
      size: AppTypeScale.body,
      weight: FontWeight.w600,
      height: 1.25,
      letterSpacing: 0.1,
    ),
    labelMedium: style(
      base.labelMedium,
      size: AppTypeScale.supporting,
      weight: FontWeight.w600,
      height: 1.25,
      letterSpacing: 0.1,
    ),
    labelSmall: style(
      base.labelSmall,
      size: AppTypeScale.micro,
      weight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.1,
    ),
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: isDark ? _darkPhosphor : _lightPhosphor,
    onPrimary: isDark ? const Color(0xFF052E16) : const Color(0xFFF5FFF9),
    primaryContainer: isDark
        ? const Color(0xFF0F3D2A)
        : const Color(0xFFD1FAE5),
    onPrimaryContainer: isDark
        ? const Color(0xFFBBF7D0)
        : const Color(0xFF064E3B),
    secondary: isDark ? _darkAmber : _lightAmber,
    onSecondary: isDark ? const Color(0xFF3D2A00) : const Color(0xFFFFFBF2),
    secondaryContainer: isDark
        ? const Color(0xFF3D2A00)
        : const Color(0xFFFEF3C7),
    onSecondaryContainer: isDark
        ? const Color(0xFFFDE68A)
        : const Color(0xFF78350F),
    tertiary: isDark ? const Color(0xFF22D3EE) : const Color(0xFF0E7490),
    onTertiary: isDark ? const Color(0xFF003744) : const Color(0xFFF3FDFF),
    error: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
    onError: isDark ? const Color(0xFF450A0A) : const Color(0xFFFFF8F7),
    errorContainer: isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2),
    onErrorContainer: isDark
        ? const Color(0xFFFCA5A5)
        : const Color(0xFF7F1D1D),
    surface: isDark ? const Color(0xFF0F1623) : const Color(0xFFFBFDFC),
    onSurface: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
    surfaceContainerHighest: isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9),
    onSurfaceVariant: isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569),
    outline: const Color(0xFF64748B),
    outlineVariant: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
    scrim: isDark ? const Color(0xFF000000) : const Color(0xFF0F172A),
    shadow: isDark ? const Color(0xFF000000) : const Color(0x1A000000),
  );

  final oscilloscope = OscilloscopeColors(
    phosphor: isDark ? _darkPhosphor : _lightPhosphor,
    gridLine: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
    statusDraft: colorScheme.onSurfaceVariant,
    statusReview: isDark ? _darkAmber : _lightAmber,
    statusConfirmed: isDark ? _darkPhosphor : _lightPhosphor,
    statusExported: colorScheme.tertiary,
    statusFailed: colorScheme.error,
  );

  final baseTextTheme = isDark ? Typography().white : Typography().black;
  final textTheme = _buildAppTextTheme(
    baseTextTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    ),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: AppLayout.controlRadius,
    borderSide: BorderSide(color: colorScheme.outline),
  );

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
      titleTextStyle: textTheme.appSectionTitle.copyWith(
        color: colorScheme.onSurface,
      ),
      shape: Border(bottom: BorderSide(color: oscilloscope.gridLine, width: 1)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppLayout.panelRadius,
        side: BorderSide(color: oscilloscope.gridLine, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
      labelStyle: textTheme.appSupporting.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      floatingLabelStyle: textTheme.appSupporting.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: textTheme.appBody.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      helperStyle: textTheme.appSupporting.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      errorStyle: textTheme.appSupporting.copyWith(color: colorScheme.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppLayout.controlHeight),
        shape: const RoundedRectangleBorder(
          borderRadius: AppLayout.controlRadius,
        ),
        textStyle: textTheme.appControlLabel,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppLayout.controlHeight),
        shape: const RoundedRectangleBorder(
          borderRadius: AppLayout.controlRadius,
        ),
        textStyle: textTheme.appControlLabel,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: textTheme.appControlLabel),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        textStyle: textTheme.appControlLabel,
        selectedBackgroundColor: colorScheme.primaryContainer,
        selectedForegroundColor: colorScheme.onPrimaryContainer,
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: textTheme.appItemTitle.copyWith(
        color: colorScheme.onSurface,
      ),
      subtitleTextStyle: textTheme.appBody.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      leadingAndTrailingTextStyle: textTheme.appMetadata.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppLayout.modalRadius),
      ),
      titleTextStyle: textTheme.appSectionTitle.copyWith(
        color: colorScheme.onSurface,
      ),
      contentTextStyle: textTheme.appBody.copyWith(
        color: colorScheme.onSurface,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppLayout.modalRadius),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: textTheme.appControlLabel,
      unselectedLabelStyle: textTheme.appControlLabel,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(textTheme.appMicroLabel),
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
      selectedColor: colorScheme.primaryContainer,
      checkmarkColor: colorScheme.onPrimaryContainer,
      side: BorderSide(color: oscilloscope.gridLine),
      labelStyle: textTheme.appMetadata.copyWith(color: colorScheme.onSurface),
      shape: const RoundedRectangleBorder(
        borderRadius: AppLayout.capsuleRadius,
      ),
    ),
    textTheme: textTheme,
  );
}
