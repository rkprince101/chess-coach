import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CoachMode {
  strict('Strict', 'Pause after every questionable move and offer a retry'),
  relaxed('Relaxed', 'Explain mistakes but let the game continue'),
  off('Off', 'No coaching, just play');

  const CoachMode(this.label, this.description);

  final String label;
  final String description;
}

enum PlayerLevel {
  beginner('Beginner', 'I am learning how the pieces move'),
  intermediate('Intermediate', 'I know the rules and some tactics'),
  advanced('Advanced', 'I want deeper strategic explanations');

  const PlayerLevel(this.label, this.description);

  final String label;
  final String description;
}

/// LLM backends the coach can talk to. All but Claude speak the OpenAI
/// `/chat/completions` protocol; [fixedBaseUrl] is null when the user
/// supplies their own server address.
enum CoachProvider {
  groq('Groq', 'https://api.groq.com/openai/v1', 'openai/gpt-oss-120b',
      'Key from console.groq.com. Fast hosted open models such as openai/gpt-oss-120b.'),
  grok('Grok (xAI)', 'https://api.x.ai/v1', 'grok-4', 'Key from console.x.ai.'),
  claude('Claude', 'https://api.anthropic.com', 'claude-opus-5', 'Key from console.anthropic.com.'),
  custom('Custom', null, '', 'Any OpenAI-compatible server: OpenAI, OpenRouter, Ollama, LM Studio…');

  const CoachProvider(this.label, this.fixedBaseUrl, this.defaultModel, this.help);

  final String label;
  final String? fixedBaseUrl;
  final String defaultModel;
  final String help;

  bool get isOpenAiCompatible => this != CoachProvider.claude;
}

/// User preferences, persisted with shared_preferences.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) {
    provider = CoachProvider.values.byName(_prefs.getString('provider') ?? CoachProvider.groq.name);
    for (final p in CoachProvider.values) {
      _keys[p] = _prefs.getString('key_${p.name}') ?? '';
      _models[p] = _prefs.getString('model_${p.name}') ?? p.defaultModel;
    }
    customBaseUrl = _prefs.getString('customBaseUrl') ?? 'https://api.openai.com/v1';
    effort = _prefs.getString('effort') ?? 'medium';
    coachMode = CoachMode.values.byName(_prefs.getString('coachMode') ?? CoachMode.strict.name);
    playerLevel =
        PlayerLevel.values.byName(_prefs.getString('playerLevel') ?? PlayerLevel.beginner.name);
    engineLevel = _prefs.getInt('engineLevel') ?? 3;
    thinkTimeMs = _prefs.getInt('thinkTimeMs') ?? (kIsWeb ? 500 : 1000);
    playAsWhite = _prefs.getBool('playAsWhite') ?? true;
    revealBestMove = _prefs.getBool('revealBestMove') ?? false;
    showEvalBar = _prefs.getBool('showEvalBar') ?? true;
    autoPreview = _prefs.getBool('autoPreview') ?? true;
    voiceEnabled = _prefs.getBool('voiceEnabled') ?? false;
    voicePack = _prefs.getString('voicePack') ?? 'kokoro-int8-en';
    voiceSpeaker = _prefs.getInt('voiceSpeaker') ?? 0;
    voiceSpeed = _prefs.getDouble('voiceSpeed') ?? 1.0;
    voicePreview = _prefs.getBool('voicePreview') ?? true;
    voiceLessons = _prefs.getBool('voiceLessons') ?? true;
    coachEnabled = _prefs.getBool('coachEnabled') ?? true;
    eloRating = _prefs.getInt('eloRating') ?? 800;
    themeSeedColor = _prefs.getInt('themeSeedColor') ?? 0xFF6750A4;
    showCoachDetails = _prefs.getBool('showCoachDetails') ?? true;
  }

  static const claudeModels = ['claude-opus-5', 'claude-sonnet-5', 'claude-haiku-4-5'];
  static const efforts = ['low', 'medium', 'high'];

  final SharedPreferences _prefs;
  final Map<CoachProvider, String> _keys = {};
  final Map<CoachProvider, String> _models = {};

  late CoachProvider provider;
  late String customBaseUrl;

  /// Claude-only thinking effort.
  late String effort;
  late CoachMode coachMode;
  late PlayerLevel playerLevel;
  late int engineLevel;
  late int thinkTimeMs;
  late bool playAsWhite;
  late bool revealBestMove;
  late bool showEvalBar;

  /// Automatically replay the engine's punishing line on the board when a
  /// move is flagged.
  late bool autoPreview;

  /// On-device neural voice.
  late bool voiceEnabled;
  late String voicePack;
  late int voiceSpeaker;
  late double voiceSpeed;
  late bool voicePreview;
  late bool voiceLessons;
  late bool coachEnabled;
  late int eloRating;
  late int themeSeedColor;
  late bool showCoachDetails;

  String keyFor(CoachProvider p) => _keys[p] ?? '';
  String modelFor(CoachProvider p) => _models[p] ?? p.defaultModel;
  String baseUrlFor(CoachProvider p) => p.fixedBaseUrl ?? customBaseUrl;

  /// Active provider shortcuts.
  String get apiKey => keyFor(provider);
  String get model => modelFor(provider);
  String get baseUrl => baseUrlFor(provider);

  /// Whether the active provider is configured well enough to call.
  bool get hasApiKey => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsController(prefs);
  }

  Future<void> setProvider(CoachProvider v) async {
    provider = v;
    await _prefs.setString('provider', v.name);
    notifyListeners();
  }

  Future<void> setKey(CoachProvider p, String v) async {
    _keys[p] = v.trim();
    await _prefs.setString('key_${p.name}', _keys[p]!);
    notifyListeners();
  }

  Future<void> setModel(CoachProvider p, String v) async {
    _models[p] = v.trim();
    await _prefs.setString('model_${p.name}', _models[p]!);
    notifyListeners();
  }

  Future<void> setCustomBaseUrl(String v) async {
    customBaseUrl = v.trim();
    await _prefs.setString('customBaseUrl', customBaseUrl);
    notifyListeners();
  }

  Future<void> setEffort(String v) async {
    effort = v;
    await _prefs.setString('effort', v);
    notifyListeners();
  }

  Future<void> setCoachMode(CoachMode v) async {
    coachMode = v;
    await _prefs.setString('coachMode', v.name);
    notifyListeners();
  }

  Future<void> setPlayerLevel(PlayerLevel v) async {
    playerLevel = v;
    await _prefs.setString('playerLevel', v.name);
    notifyListeners();
  }

  Future<void> setEngineLevel(int v) async {
    engineLevel = v.clamp(1, 8);
    await _prefs.setInt('engineLevel', engineLevel);
    notifyListeners();
  }

  Future<void> setThinkTimeMs(int v) async {
    thinkTimeMs = v;
    await _prefs.setInt('thinkTimeMs', v);
    notifyListeners();
  }

  Future<void> setPlayAsWhite(bool v) async {
    playAsWhite = v;
    await _prefs.setBool('playAsWhite', v);
    notifyListeners();
  }

  Future<void> setRevealBestMove(bool v) async {
    revealBestMove = v;
    await _prefs.setBool('revealBestMove', v);
    notifyListeners();
  }

  Future<void> setShowEvalBar(bool v) async {
    showEvalBar = v;
    await _prefs.setBool('showEvalBar', v);
    notifyListeners();
  }

  Future<void> setAutoPreview(bool v) async {
    autoPreview = v;
    await _prefs.setBool('autoPreview', v);
    notifyListeners();
  }

  Future<void> setVoiceEnabled(bool v) async {
    voiceEnabled = v;
    await _prefs.setBool('voiceEnabled', v);
    notifyListeners();
  }

  Future<void> setVoicePack(String v) async {
    voicePack = v;
    await _prefs.setString('voicePack', v);
    notifyListeners();
  }

  Future<void> setVoiceSpeaker(int v) async {
    voiceSpeaker = v;
    await _prefs.setInt('voiceSpeaker', v);
    notifyListeners();
  }

  Future<void> setVoiceSpeed(double v) async {
    voiceSpeed = v;
    await _prefs.setDouble('voiceSpeed', v);
    notifyListeners();
  }

  Future<void> setVoicePreview(bool v) async {
    voicePreview = v;
    await _prefs.setBool('voicePreview', v);
    notifyListeners();
  }

  Future<void> setVoiceLessons(bool v) async {
    voiceLessons = v;
    await _prefs.setBool('voiceLessons', v);
    notifyListeners();
  }

  Future<void> setCoachEnabled(bool v) async {
    coachEnabled = v;
    await _prefs.setBool('coachEnabled', v);
    notifyListeners();
  }

  Future<void> setEloRating(int v) async {
    eloRating = v.clamp(400, 2000);
    await _prefs.setInt('eloRating', eloRating);
    // Map Elo to engine level for backward compat
    engineLevel = _eloToEngineLevel(eloRating);
    await _prefs.setInt('engineLevel', engineLevel);
    notifyListeners();
  }

  Future<void> setThemeSeedColor(int v) async {
    themeSeedColor = v;
    await _prefs.setInt('themeSeedColor', v);
    notifyListeners();
  }

  Future<void> setShowCoachDetails(bool v) async {
    showCoachDetails = v;
    await _prefs.setBool('showCoachDetails', v);
    notifyListeners();
  }

  int _eloToEngineLevel(int elo) {
    if (elo < 600) return 1;
    if (elo < 800) return 2;
    if (elo < 1000) return 3;
    if (elo < 1200) return 4;
    if (elo < 1400) return 5;
    if (elo < 1600) return 6;
    if (elo < 1800) return 7;
    return 8;
  }

  String get eloLabel {
    if (eloRating < 600) return 'Beginner';
    if (eloRating < 800) return 'Novice';
    if (eloRating < 1000) return 'Casual';
    if (eloRating < 1200) return 'Intermediate';
    if (eloRating < 1400) return 'Advanced';
    if (eloRating < 1600) return 'Expert';
    if (eloRating < 1800) return 'Master';
    return 'Grandmaster';
  }
}
