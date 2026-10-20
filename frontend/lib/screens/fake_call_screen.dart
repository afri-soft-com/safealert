import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Timer? _ring;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _ring = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _ring?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _answer() {
    _ring?.cancel();
    setState(() => _answered = true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds += 1);
    });
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
              ],
              const Spacer(),
              if (!_answered)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundBtn(Icons.call_end, Colors.red, widget.onEnd),
                    _roundBtn(Icons.call, Colors.green, _answer),
                  ],
                )
              else
                _roundBtn(Icons.call_end, Colors.red, widget.onEnd),
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
