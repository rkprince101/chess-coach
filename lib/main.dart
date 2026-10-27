import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'coach/coach_service.dart';
import 'engine/engine_service.dart';
import 'services/settings.dart';
import 'ui/screens/home_screen.dart';
import 'ui/widgets/segmented_list.dart';
import 'voice/voice_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status and navigation bars on every Android version (15+
  // enforces this anyway); screens pad themselves with the system insets.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final settings = await SettingsController.load();
  final voice = VoiceService(settings);
  unawaited(voice.init());
  runApp(ChessCoachApp(settings: settings, voice: voice));
}

class ChessCoachApp extends StatelessWidget {
  const ChessCoachApp({super.key, required this.settings, this.voice});

  final SettingsController settings;
  final VoiceService? voice;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: voice ?? VoiceService(settings)),
        Provider(create: (_) => EngineService(), dispose: (_, e) => e.dispose()),
        Provider(create: (_) => CoachService(settings)),
      ],
      child: MaterialApp(
        title: 'Chess Coach',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: ThemeMode.system,
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: _systemBars(Theme.of(context).brightness),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    );
  }

  /// Transparent bars with icons that contrast the theme. App bars override
  /// the status bar part; this covers the navigation bar and bar-less screens.
  static SystemUiOverlayStyle _systemBars(Brightness brightness) {
    final icons = brightness == Brightness.dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(settings.themeSeedColor),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Pages are one tone off the cards/list segments that sit on them.
      scaffoldBackgroundColor: pageColor(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: pageColor(scheme),
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: segmentColor(scheme),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(SegmentedList.outer)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
    );
  }
}
