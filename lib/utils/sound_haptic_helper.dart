import 'package:flutter/services.dart';

enum ScanResultType {
  valid,      // 🟢 Vert
  alreadyUsed,// 🟠 Orange
  invalid,    // 🔴 Rouge
  banned,     // 🔴🚫 Rouge Écarlate (Banni)
}

class SoundHapticHelper {
  static void triggerFeedback(ScanResultType type) {
    switch (type) {
      case ScanResultType.valid:
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        break;
      case ScanResultType.alreadyUsed:
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 150), () {
          HapticFeedback.heavyImpact();
        });
        SystemSound.play(SystemSoundType.alert);
        break;
      case ScanResultType.invalid:
        HapticFeedback.vibrate();
        SystemSound.play(SystemSoundType.alert);
        break;
      case ScanResultType.banned:
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 100), () => HapticFeedback.heavyImpact());
        Future.delayed(const Duration(milliseconds: 200), () => HapticFeedback.heavyImpact());
        SystemSound.play(SystemSoundType.alert);
        break;
    }
  }

  static void triggerSuccess() => triggerFeedback(ScanResultType.valid);
  static void triggerWarning() => triggerFeedback(ScanResultType.alreadyUsed);
  static void triggerError() => triggerFeedback(ScanResultType.invalid);
  static void triggerBanned() => triggerFeedback(ScanResultType.banned);
}
