import 'package:chess/coach/coach_service.dart';
import 'package:chess/coach/llm_client.dart';
import 'package:chess/engine/engine_service.dart';
import 'package:chess/services/settings.dart';
import 'package:chess/ui/screens/topic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLlm implements LlmClient {
  FakeLlm(this.reply);
  final String reply;
  int calls = 0;

  @override
  Stream<String> streamText({required String system, required List<Map<String, dynamic>> messages, int maxTokens = 2048}) async* {
    calls++;
    yield reply;
  }
}

const demoJson = '''
{"title":"The knight fork","intro":"A fork attacks two things at once.","summary":"Knights fork best.",
 "steps":[{"title":"Royal fork","fen":"8/2k3q1/8/8/3N4/8/8/4K3 w - - 0 1","text":"Look at the knight on d4.",
 "moves":["Ne6+","Kd7","Nxg7"],"arrows":["d4e6"],"highlights":["c7","g7"],"after":"The queen is gone."}]}
''';

void main() {
  testWidgets('TopicScreen walks through a verified board demo', (tester) async {
    SharedPreferences.setMockInitialValues({'key_groq': 'k'});
    final settings = await SettingsController.load();
    final llm = FakeLlm(demoJson);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        Provider(create: (_) => EngineService()),
        Provider(create: (_) => CoachService(settings, clientOverride: llm)),
      ],
      child: const MaterialApp(home: TopicScreen(topic: 'Knight fork')),
    ));
    await tester.pumpAndSettle();

    expect(llm.calls, 1);
    expect(find.text('The knight fork'), findsOneWidget);
    expect(find.textContaining('Royal fork'), findsOneWidget);
    expect(find.text('Next move'), findsOneWidget);
    expect(find.textContaining('Practise:'), findsOneWidget);

    await tester.tap(find.text('Next move'));
    await tester.pumpAndSettle();
    expect(find.textContaining('knight jumps from d4 to e6'), findsOneWidget);

    await tester.tap(find.text('Next move'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next move'));
    await tester.pumpAndSettle();
    expect(find.text('The queen is gone.'), findsOneWidget);
    expect(find.textContaining('Rule of thumb'), findsOneWidget);
    expect(find.text('Next move'), findsNothing);
  });

  testWidgets('TopicScreen falls back to text when the demo is unusable', (tester) async {
    SharedPreferences.setMockInitialValues({'key_groq': 'k'});
    final settings = await SettingsController.load();
    final llm = FakeLlm('Sorry, plain prose only.');
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        Provider(create: (_) => EngineService()),
        Provider(create: (_) => CoachService(settings, clientOverride: llm)),
      ],
      child: const MaterialApp(home: TopicScreen(topic: 'Prophylaxis')),
    ));
    await tester.pumpAndSettle();

    // Two demo attempts plus one text explanation.
    expect(llm.calls, 3);
    expect(find.text('No board demo this time'), findsOneWidget);
    expect(find.text('Sorry, plain prose only.'), findsOneWidget);
  });
}
