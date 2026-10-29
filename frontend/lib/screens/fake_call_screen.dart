import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';

const _kDefaultCaller = 'Maman';

String _fakeCallPrefsKey(String? userId) =>
    userId != null && userId.isNotEmpty
        ? 'fake_call_caller_name_$userId'
        : 'fake_call_caller_name';

/// Faux appel entrant pour sortie discrète (aucune API).
/// Chaque compte peut définir le nom affiché (stocké localement).
class FakeCallScreen extends StatefulWidget {
  final VoidCallback onEnd;
  const FakeCallScreen({super.key, required this.onEnd});

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen> {
  final _nameCtrl = TextEditingController();
  bool _ready = false;
  bool _ringing = false;
  bool _answered = false;
  int _seconds = 0;
  Timer? _tick;
  bool _vibrating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadCallerName());
    });
  }

  @override
  void dispose() {
    unawaited(_stopVibration());
    _tick?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCallerName() async {
    final userId = context.read<AuthProvider>().user?['id']?.toString();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_fakeCallPrefsKey(userId))?.trim();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = (saved != null && saved.isNotEmpty) ? saved : _kDefaultCaller;
      _ready = true;
    });
  }

  Future<void> _saveCallerName(String name) async {
    final userId = context.read<AuthProvider>().user?['id']?.toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fakeCallPrefsKey(userId), name);
  }

  Future<void> _startCall() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquez un nom pour l\'appelant')),
      );
      return;
    }
    await _saveCallerName(name);
    if (!mounted) return;
    setState(() {
      _ringing = true;
      _answered = false;
      _seconds = 0;
    });
    unawaited(_startRingVibration());
  }

  Future<void> _startRingVibration() async {
    if (_vibrating) return;
    _vibrating = true;
    try {
      final has = await Vibration.hasVibrator();
      if (!has) {
        HapticFeedback.vibrate();
        return;
      }
      final custom = await Vibration.hasCustomVibrationsSupport();
      if (custom) {
        await Vibration.vibrate(
          pattern: [0, 700, 350, 700, 350],
          repeat: 0,
          intensities: [0, 255, 0, 200, 0],
        );
      } else {
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

  String get _callerName {
    final t = _nameCtrl.text.trim();
    return t.isNotEmpty ? t : _kDefaultCaller;
  }

  String get _duration {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A1A1A),
        body: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    if (!_ringing) return _buildSetup();
    return _buildCallUi();
  }

  Widget _buildSetup() {
    return Scaffold(
      backgroundColor: AppColors.blanc,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: widget.onEnd,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Faux appel',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bleuFonce,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choisissez le nom qui s’affiche comme appelant. '
                'Il est mémorisé pour votre compte sur cet appareil.',
                style: TextStyle(fontSize: 13, color: AppColors.gris, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Nom de l’appelant',
                  hintText: 'Ex. Papa, Marie, Bureau…',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) => unawaited(_startCall()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => unawaited(_startCall()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bleuFonce,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Lancer l’appel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallUi() {
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
                  _callerName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 36, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _callerName,
                textAlign: TextAlign.center,
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
