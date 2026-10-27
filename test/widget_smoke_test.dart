import 'package:chess/main.dart';
import 'package:chess/services/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home, lessons and settings screens render', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChessCoachApp(settings: settings));
    await tester.pumpAndSettle();
    expect(find.text('Play & Learn'), findsOneWidget);
    expect(find.textContaining('Add your AI API key'), findsOneWidget);

    await tester.tap(find.text('Lessons'));
    await tester.pumpAndSettle();
    expect(find.text('The knight'), findsOneWidget);

    await tester.tap(find.text('The pawn'));
    await tester.pumpAndSettle();
    expect(find.text('Marching forward'), findsOneWidget);
    expect(find.text('Hint'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Groq'), findsOneWidget);
    expect(find.text('Groq API key'), findsOneWidget);
    expect(find.text('Fetch models'), findsOneWidget);

    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    expect(find.text('Claude API key'), findsOneWidget);
    expect(find.text('Thinking effort'), findsOneWidget);
  });
}
