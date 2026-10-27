/// Downloadable on-device neural voice packs (sherpa-onnx model bundles).
/// Nothing is bundled in the app; the user picks one in Settings and it is
/// fetched once into app storage.
enum VoiceEngine { kokoro, kitten, vits }

class VoicePack {
  const VoicePack({
    required this.id,
    required this.title,
    required this.description,
    required this.engine,
    required this.url,
    required this.downloadMb,
    required this.speakerNames,
    this.defaultSpeaker = 0,
  });

  final String id;
  final String title;
  final String description;
  final VoiceEngine engine;
  final String url;
  final int downloadMb;

  /// Human names for speaker ids, when the pack has several voices.
  final List<String> speakerNames;
  final int defaultSpeaker;

  String get archiveName => url.substring(url.lastIndexOf('/') + 1);
}

const _base = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

const List<VoicePack> voicePacks = [
  VoicePack(
    id: 'kokoro-int8-en',
    title: 'Kokoro (most natural)',
    description: '103 MB download. Warm, expressive English voices; the best quality that runs offline on a phone.',
    engine: VoiceEngine.kokoro,
    url: '$_base/kokoro-int8-en-v0_19.tar.bz2',
    downloadMb: 103,
    speakerNames: [
      'Default (American female)',
      'Bella (American female)',
      'Nicole (American female)',
      'Sarah (American female)',
      'Sky (American female)',
      'Adam (American male)',
      'Michael (American male)',
      'Emma (British female)',
      'Isabella (British female)',
      'George (British male)',
      'Lewis (British male)',
    ],
    defaultSpeaker: 3,
  ),
  VoicePack(
    id: 'kitten-nano-en',
    title: 'Kitten (light)',
    description: '31 MB download. Small model, quick on older phones, clearly synthetic but pleasant.',
    engine: VoiceEngine.kitten,
    url: '$_base/kitten-nano-en-v0_8-int8.tar.bz2',
    downloadMb: 31,
    speakerNames: [
      'Voice 1 (male)',
      'Voice 1 (female)',
      'Voice 2 (male)',
      'Voice 2 (female)',
      'Voice 3 (male)',
      'Voice 3 (female)',
      'Voice 4 (male)',
      'Voice 4 (female)',
    ],
  ),
  VoicePack(
    id: 'piper-lessac-en',
    title: 'Piper Lessac (fastest)',
    description: '21 MB download. Classic neural voice, instant even on low-end devices.',
    engine: VoiceEngine.vits,
    url: '$_base/vits-piper-en_US-lessac-medium-int8.tar.bz2',
    downloadMb: 21,
    speakerNames: ['Lessac (American)'],
  ),
];

VoicePack? voicePackById(String id) {
  for (final p in voicePacks) {
    if (p.id == id) return p;
  }
  return null;
}
