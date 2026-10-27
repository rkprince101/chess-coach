import 'package:chess/coach/demo_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a fenced JSON demo with moves, arrows and highlights', () {
    const raw = '''
Here you go:
```json
{
  "title": "The knight fork",
  "intro": "A fork attacks two things at once.",
  "steps": [
    {
      "title": "Royal fork",
      "fen": "8/2k3q1/8/8/3N4/8/8/4K3 w - - 0 1",
      "text": "Look at the knight.",
      "moves": ["Ne6+", "Kd7", "Nxg7"],
      "arrows": ["d4e6", "e6-c7", "bad"],
      "highlights": ["c7", "g7", "z9"],
      "after": "The queen is gone."
    }
  ],
  "summary": "Knights fork best."
}
```
''';
    final demo = parseDemo(raw)!;
    expect(demo.title, 'The knight fork');
    expect(demo.steps, hasLength(1));
    final step = demo.steps.first;
    expect(step.moves.map((m) => m.uci), ['d4e6', 'c7d7', 'e6g7']);
    expect(step.shapes, hasLength(4)); // 2 arrows + 2 highlights, junk ignored
    expect(step.positions, hasLength(4));
    expect(step.afterText, 'The queen is gone.');
    expect(demo.problems, isEmpty);
  });

  test('drops illegal FENs and truncates at the first illegal move', () {
    const raw = '''
{"title":"t","intro":"i","summary":"s","steps":[
  {"title":"bad fen","fen":"8/8/8/8/8/8/8/8 w - - 0 1","text":"","moves":[]},
  {"title":"bad move","fen":"6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1","text":"","moves":["Ra8+","Kxa8"]},
  {"title":"over","fen":"7k/6Q1/6K1/8/8/8/8/8 b - - 0 1","text":"","moves":[]}
]}''';
    final demo = parseDemo(raw)!;
    expect(demo.steps, hasLength(1));
    expect(demo.steps.first.title, 'bad move');
    expect(demo.steps.first.moves, hasLength(1));
    expect(demo.steps.first.truncated, isTrue);
    expect(demo.problems.length, 3);
    expect(demo.problems.join(), contains('Kxa8'));
  });

  test('returns null for junk', () {
    expect(parseDemo('no json here'), isNull);
    expect(parseDemo('{"steps": []}'), isNull);
  });

  test('matches built-in lessons and seeds the prompt with verified positions', () {
    final lessons = matchingLessons('Knight fork');
    expect(lessons.map((l) => l.id), contains('fork'));
    final prompt = demoPrompt('Knight fork');
    expect(prompt, contains('8/2k3q1/8/8/3N4/8/8/4K3 w - - 0 1'));
    expect(prompt, contains('Return ONLY a JSON object'));
    expect(demoPrompt('Prophylaxis'), isNot(contains('Verified positions')));
  });
}
