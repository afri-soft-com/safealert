import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../theme.dart';

/// Faux appel entrant pour sortie discrète (aucune API).
class FakeCallScreen extends StatefulWidget {
  final VoidCallback onEnd;
  final String callerName;
  const FakeCallScreen({
    super.key,
    required this.onEnd,
    this.callerName = 'Maman',
  });

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen> {
  bool _answered = false;
  int _seconds = 0;
  Timer? _tick;
  bool _vibrating = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startRingVibration());
  }

  @override
  void dispose() {
    unawaited(_stopVibration());
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _startRingVibration() async {
    if (_vibrating) return;
    _vibrating = true;
    try {
      final has = await Vibration.hasVibrator();
      if (!has) {
        // Fallback soft haptic (may be weak / off on some Androids).
        HapticFeedback.vibrate();
        return;
      }
      final custom = await Vibration.hasCustomVibrationsSupport();
      if (custom) {
        // Ring pattern: buzz — pause — buzz… (repeat from index 0).
        await Vibration.vibrate(
          pattern: [0, 700, 350, 700, 350],
          repeat: 0,
          intensities: [0, 255, 0, 200, 0],
        );
      } else {
        // Devices without pattern support: pulse every 1.5s.
        await Vibration.vibrate(duration: 600);
        _tick ??= Timer.periodic(const Duration(milliseconds: 1500), (_) async {
          if (_answered || !mounted) return;
          try {
            await Vibration.vibrate(duration: 600);
          } catch (_) {
            await HapticFeedback.vibrate();
          }
        });
      }
    } catch (_) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
  }

  Future<void> _stopVibration() async {
    _vibrating = false;
    try {
      await Vibration.cancel();
    } catch (_) {}
  }

  Future<void> _answer() async {
    await _stopVibration();
    _tick?.cancel();
    _tick = null;
    if (!mounted) return;
    setState(() => _answered = true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds += 1);
    });
  }

  Future<void> _hangUp() async {
    await _stopVibration();
    _tick?.cancel();
    widget.onEnd();
  }

  String get _duration {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text(
                _answered ? 'En communication' : 'Appel entrant…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.vert.withValues(alpha: 0.3),
                child: Text(
                  widget.callerName.isNotEmpty
                      ? widget.callerName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontSize: 36, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.callerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_answered) ...[
                const SizedBox(height: 8),
                Text(_duration, style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Le téléphone vibre comme un vrai appel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
              ],
              const Spacer(),
              if (!_answered)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundBtn(Icons.call_end, Colors.red, () => unawaited(_hangUp())),
                    _roundBtn(Icons.call, Colors.green, () => unawaited(_answer())),
                  ],
                )
              else
                _roundBtn(Icons.call_end, Colors.red, () => unawaited(_hangUp())),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}
