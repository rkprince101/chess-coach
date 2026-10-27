import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings.dart';
import '../../voice/voice_service.dart';
import '../screens/settings_screen.dart';

/// App-bar toggle for the spoken coach. Tapping mutes/unmutes when a voice
/// pack is installed, otherwise it opens Settings to download one.
class VoiceButton extends StatelessWidget {
  const VoiceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceService>();
    final settings = context.watch<SettingsController>();
    if (!voice.available) return const SizedBox.shrink();
    final on = voice.enabled;
    final installed = voice.selectedPackInstalled;
    final icon = !installed
        ? Icons.record_voice_over_outlined
        : on
            ? (voice.speaking ? Icons.graphic_eq_rounded : Icons.volume_up_rounded)
            : Icons.volume_off_rounded;
    return IconButton(
      tooltip: !installed
          ? 'Download a voice for the coach'
          : on
              ? 'Mute the coach'
              : 'Unmute the coach',
      icon: Icon(icon),
      onPressed: () {
        if (!installed) {
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
          return;
        }
        if (on) voice.stop();
        settings.setVoiceEnabled(!on);
      },
    );
  }
}
