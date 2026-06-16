import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../domain/app_models.dart';
import '../state/app_state.dart';
import 'screens.dart';
import 'theme.dart';

class QsoScribeApp extends ConsumerWidget {
  const QsoScribeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeMode = ref.watch(localeModeProvider);
    final setupCompleted = ref.watch(setupCompletedProvider);
    final welcomeShown = ref.watch(welcomeShownProvider);

    final isSetupDone = setupCompleted.maybeWhen(
      data: (completed) => completed,
      orElse: () => false,
    );
    final isWelcomeDone = welcomeShown.maybeWhen(
      data: (shown) => shown,
      orElse: () => false,
    );

    Widget home;
    if (!isSetupDone) {
      home = const FirstRunSetupScreen();
    } else if (!isWelcomeDone) {
      home = const WelcomeScreen();
    } else {
      home = const MainShell();
    }

    return MaterialApp(
      title: 'QSO Scribe',
      debugShowCheckedModeBanner: false,
      locale: localeMode.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: home,
    );
  }
}
