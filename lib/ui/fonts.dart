import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';

/// Font families bundled in pubspec.yaml for [AppFont.classic].
const classicFontFamily = 'Nunito';
const classicMonoFamily = 'GeistMono';

/// Weights of the Classic look (after Komi Store's Classic type scale):
/// ExtraBold headings, Bold titles and controls, Medium running text. Sizes
/// stay on the Material 3 scale so layouts do not shift between fonts.
TextTheme classicTextTheme(TextTheme base) {
  TextStyle? w(TextStyle? s, FontWeight weight) => s?.copyWith(fontWeight: weight);
  return base.copyWith(
    displayLarge: w(base.displayLarge, FontWeight.w800),
    displayMedium: w(base.displayMedium, FontWeight.w800),
    displaySmall: w(base.displaySmall, FontWeight.w800),
    headlineLarge: w(base.headlineLarge, FontWeight.w800),
    headlineMedium: w(base.headlineMedium, FontWeight.w800),
    headlineSmall: w(base.headlineSmall, FontWeight.w800),
    titleLarge: w(base.titleLarge, FontWeight.w800),
    titleMedium: w(base.titleMedium, FontWeight.w700),
    titleSmall: w(base.titleSmall, FontWeight.w700),
    bodyLarge: w(base.bodyLarge, FontWeight.w500),
    bodyMedium: w(base.bodyMedium, FontWeight.w500),
    bodySmall: w(base.bodySmall, FontWeight.w500),
    labelLarge: w(base.labelLarge, FontWeight.w700),
    labelMedium: w(base.labelMedium, FontWeight.w700),
    labelSmall: w(base.labelSmall, FontWeight.w700),
  );
}

/// Monospace family for move notation, evaluations and PGN: Geist Mono in
/// the Classic look, the platform monospace otherwise.
String monoFamily(BuildContext context) {
  final font = Provider.of<SettingsController?>(context, listen: false)?.appFont;
  return font == AppFont.classic ? classicMonoFamily : 'monospace';
}
