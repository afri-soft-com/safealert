import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../providers/incident_provider.dart';
import '../providers/checkin_provider.dart';
import '../providers/auth_provider.dart';
import '../services/share_helper.dart';
import '../services/location_service.dart';
import '../services/app_config_service.dart';
import '../utils/location_format.dart';

class SOSScreen extends StatefulWidget {
  final VoidCallback onBack;
  const SOSScreen({super.key, required this.onBack});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  int _step = 0;
  bool _completed = false;
  bool _failed = false;
  bool _sending = false;
  bool _cancelling = false;
  bool _checkingIn = false;
  bool _queued = false;
  bool _positionApprox = false;
  String? _incidentId;
  String? _statusMsg;
  String? _zoneName;
  double? _sosLat;
  double? _sosLng;
  Map<String, dynamic>? _dispatch;
  Timer? _progressTimer;
  Timer? _liveTimer;
  Timer? _dispatchTimer;
  Timer? _holdTimer;
  double _holdProgress = 0;
  bool _holding = false;
  static const _holdDuration = Duration(milliseconds: 1500);
  static const _steps = [
    _StepData('📍', 'GPS localisé', AppColors.vert),
    _StepData('📲', 'Contacts alertés', AppColors.vert),
    _StepData('📡', 'Communauté notifiée', AppColors.vert),
    _StepData('🚨', 'Alerte transmise !', AppColors.rouge),
  ];

  @override
  void initState() {
    super.initState();
    AppConfigService().refresh();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _liveTimer?.cancel();
    _dispatchTimer?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (_sending || _completed) return;
    _holdTimer?.cancel();
    setState(() {
      _holding = true;
      _holdProgress = 0;
    });
    const tick = Duration(milliseconds: 50);
    var elapsed = 0;
    _holdTimer = Timer.periodic(tick, (t) {
      elapsed += tick.inMilliseconds;
      final p = (elapsed / _holdDuration.inMilliseconds).clamp(0.0, 1.0);
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _holdProgress = p);
      if (p >= 1) {
        t.cancel();
        setState(() {
          _holding = false;
          _holdProgress = 0;
        });
        _sendSOS();
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _holding = false;
      _holdProgress = 0;
    });
  }

  void _startLiveStatus() {
    _liveTimer?.cancel();
    if (_incidentId == null) return;
    _liveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _incidentId == null) return;
      context.read<IncidentProvider>().publishLiveStatus(_incidentId!);
    });
    context.read<IncidentProvider>().publishLiveStatus(_incidentId!);
  }

  Future<void> _sendSOS() async {
    if (_completed || _sending) return;
    if (!AppConfigService().canSendSos) {
      setState(() {
        _failed = true;
        _statusMsg = AppConfigService().maintenanceBanner.isNotEmpty
            ? AppConfigService().maintenanceBanner
            : 'Alertes temporairement indisponibles. Consultez l\'annuaire d\'urgence.';
      });
      return;
    }

    _progressTimer?.cancel();
    setState(() {
      _step = 0;
      _failed = false;
      _completed = false;
      _sending = true;
      _queued = false;
      _statusMsg = null;
      _incidentId = null;
      _dispatch = null;
      _zoneName = null;
      _sosLat = null;
      _sosLng = null;
      _positionApprox = false;
    });

    final result = await context.read<IncidentProvider>().triggerSOS(
      0, 0, type: 'sos',
    );

    if (!mounted) return;
    if (result == null) {
      setState(() {
        _failed = true;
        _sending = false;
      });
      return;
    }

    if (result['blocked'] == true) {
      setState(() {
        _failed = true;
        _sending = false;
        _statusMsg = result['message']?.toString();
      });
      return;
    }

    if (result['queued'] == true) {
      final qLat = (result['lat'] as num?)?.toDouble();
      final qLng = (result['lng'] as num?)?.toDouble();
      setState(() {
        _queued = true;
        _failed = false;
        _sending = false;
        _completed = true;
        _step = 4;
        _statusMsg = result['message']?.toString();
        _sosLat = qLat;
        _sosLng = qLng;
        _zoneName = result['zone_name']?.toString();
        _positionApprox = true;
      });
      return;
    }

    final note = result['positionNote']?.toString();
    final incident = result['incident'] as Map<String, dynamic>?;
    _incidentId = incident?['id'] as String?;
    final approx = note != null && note.isNotEmpty;

    setState(() {
      if (note != null && note.isNotEmpty) {
        _statusMsg = note;
      }
      _zoneName = incident?['zone_name']?.toString();
      _sosLat = (incident?['lat'] as num?)?.toDouble() ?? (result['lat'] as num?)?.toDouble();
      _sosLng = (incident?['lng'] as num?)?.toDouble() ?? (result['lng'] as num?)?.toDouble();
      _positionApprox = approx;
    });

    int i = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      i++;
      if (mounted) setState(() => _step = i);
      if (i >= 4) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _completed = true;
            _sending = false;
          });
          _startLiveStatus();
          _pollDispatch();
        }
      }
    });
  }

  void _pollDispatch() {
    _dispatchTimer?.cancel();
    if (_incidentId == null) return;
    Future<void> tick() async {
      if (!mounted || _incidentId == null) return;
      final d = await context.read<IncidentProvider>().fetchCitizenDispatch(_incidentId!);
      if (mounted && d != null) setState(() => _dispatch = d);
    }
    tick();
    _dispatchTimer = Timer.periodic(const Duration(seconds: 20), (_) => tick());
  }

  Future<String> _buildShareText() async {
    final pseudo = context.read<AuthProvider>().user?['pseudo']?.toString();
    var lat = _sosLat;
    var lng = _sosLng;
    var zone = _zoneName;
    var approx = _positionApprox;
    if (lat == null || lng == null) {
      final pos = await LocationService().getPositionForSos();
      lat = pos?.latitude ?? 0.0;
      lng = pos?.longitude ?? 0.0;
      approx = true;
    }
    return ShareHelper.sosMessage(
      lat: lat,
      lng: lng,
      pseudo: pseudo,
      zoneName: zone,
      approximate: approx,
    );
  }

  Future<void> _shareSos() async {
    final text = await _buildShareText();
    await ShareHelper.shareText(text);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sending && !_failed && !_completed;
    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          Container(
            width: double.infinity,
            color: AppColors.rouge,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Retour',
                  child: GestureDetector(
                    onTap: widget.onBack,
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ALERTE D\'URGENCE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2)),
                      SizedBox(height: 4),
                      Text('Bouton SOS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: _completed ? AppColors.rougeLight : Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                children: [
                  if (_failed || (_queued == true) || (_statusMsg != null && _statusMsg!.isNotEmpty))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        border: Border.all(color: AppColors.orange),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _statusMsg ??
                            (_queued == true
                                ? '📶 Alerte enregistrée hors ligne — elle sera envoyée dès que le réseau revient. Voir « Envois en attente » dans Paramètres.'
                                : '📶 Pas de connexion — L\'alerte n\'a pas pu être envoyée. Réessayez dès que le réseau est disponible.'),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF7A4F00)),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.grisClair,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Maintenez le bouton environ 2 secondes pour envoyer. '
                      'Pour une meilleure localisation, activez le GPS. '
                      'Gardez une batterie suffisante pendant l\'alerte.',
                      style: TextStyle(fontSize: 11, color: AppColors.gris),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    button: true,
                    label: _failed
                        ? 'Réessayer d\'envoyer l\'alerte SOS'
                        : _completed
                            ? 'Alerte SOS envoyée'
                            : 'Maintenir pour envoyer une alerte SOS',
                    child: GestureDetector(
                      onTapDown: busy ? null : (_) => _startHold(),
                      onTapUp: busy ? null : (_) => _cancelHold(),
                      onTapCancel: busy ? null : _cancelHold,
                      // Discrete paths (volume/shake) remain elsewhere; audible mode uses hold
                      onLongPress: busy ? null : _sendSOS,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 168,
                            height: 168,
                            child: CircularProgressIndicator(
                              value: _holding ? _holdProgress : 0,
                              strokeWidth: 6,
                              color: Colors.white,
                              backgroundColor: AppColors.rouge.withValues(alpha: 0.25),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 160, height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _step > 0 ? AppColors.rougeDark : AppColors.rouge,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.rouge.withValues(alpha: _step > 0 ? 0.2 : 0.15),
                                  blurRadius: _step > 0 ? 32 : 12,
                                  spreadRadius: _step > 0 ? 16 : 0,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _failed
                                    ? '📶\nRÉESSAYER'
                                    : _holding
                                        ? '⏳\nMaintenir...'
                                        : _step == 0
                                            ? '🆘\nMAINTENIR'
                                            : _completed
                                                ? '✅\nENVOYÉ !'
                                                : '⏳\nEnvoi...',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...List.generate(_steps.length, (i) {
                    final s = _steps[i];
                    final done = _step > i;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: done ? s.color.withValues(alpha: 0.1) : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: done ? s.color : const Color(0xFFEEEEEE)),
                      ),
                      child: Row(
                        children: [
                          Text(done ? '✅' : s.icon, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(s.label, style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: done ? s.color : AppColors.gris,
                            ), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_statusMsg != null && !_failed && !_queued) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.vertClair,
                        border: Border.all(color: AppColors.vert),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_statusMsg!, style: const TextStyle(fontSize: 12, color: AppColors.vert)),
                    ),
                  ],
                  if (_completed && !_cancelling) ...[
                    if (_sosLat != null && _sosLng != null) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.rougeLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.rouge),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Lieu partagé avec vos contacts',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.rouge),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              LocationFormat.displayLine(
                                zoneName: _zoneName,
                                lat: _sosLat,
                                lng: _sosLng,
                                approximate: _positionApprox,
                              ),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bleuFonce),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_dispatch != null && _dispatch!['agent_pseudo'] != null) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bleuFonce.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.bleuFonce),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dispatch!['message']?.toString() ?? 'Aide en route',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.bleuFonce,
                              ),
                            ),
                            if (_dispatch!['assignment_eta'] != null)
                              Text(
                                'Arrivée estimée : ${_dispatch!['assignment_eta']}',
                                style: const TextStyle(fontSize: 11, color: AppColors.gris),
                              ),
                          ],
                        ),
                      ),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _shareSos,
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('Partager', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final text = await _buildShareText();
                              await ShareHelper.shareWhatsApp(text);
                            },
                            icon: const Icon(Icons.chat, size: 16),
                            label: const Text('WhatsApp', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.vert,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _checkingIn
                            ? null
                            : () async {
                                setState(() => _checkingIn = true);
                                final checkIn = context.read<CheckInProvider>();
                                final ok = await checkIn.imSafe(incidentId: _incidentId);
                                _liveTimer?.cancel();
                                if (mounted) {
                                  setState(() {
                                    _checkingIn = false;
                                    if (ok) {
                                      _statusMsg = AppLocalizations.of(context).checkInSent;
                                      _completed = false;
                                      _step = 0;
                                      _incidentId = null;
                                    }
                                  });
                                  if (!ok) {
                                    showAppSnackBar(
                                      context,
                                      checkIn.error ??
                                          'Envoi impossible. Vérifiez votre connexion.',
                                      isError: true,
                                      fallback: 'Envoi impossible. Vérifiez votre connexion.',
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.vert,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _checkingIn
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.verified_user, size: 18),
                        label: Text(AppLocalizations.of(context).imSafe,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          setState(() => _cancelling = true);
                          try {
                            final ok = await context.read<IncidentProvider>().cancelSOS();
                            _liveTimer?.cancel();
                            if (mounted) {
                              setState(() {
                                _cancelling = false;
                                _step = 0;
                                _completed = false;
                                _incidentId = null;
                                _statusMsg = ok
                                    ? AppLocalizations.of(context).falseAlarm
                                    : 'Annulation impossible';
                              });
                            }
                          } catch (_) {
                            if (mounted) setState(() => _cancelling = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _cancelling
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cancel, size: 18),
                        label: Text(_cancelling ? 'Annulation...' : 'Fausse alerte — annuler',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.grisClair,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MODE DISCRET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.bleuFonce)),
                        SizedBox(height: 6),
                        Text('Pour déclencher sans afficher l\'app :', style: TextStyle(fontSize: 11, color: AppColors.gris)),
                        SizedBox(height: 4),
                        Text('• 3× Volume ↓  ·  Secouer le téléphone  ·  Raccourci SOS',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.rouge)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: widget.onBack,
                    child: const Text('← Retour à l\'accueil', style: TextStyle(color: AppColors.gris, fontSize: 12)),
                  ),
                ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepData {
  final String icon;
  final String label;
  final Color color;
  const _StepData(this.icon, this.label, this.color);
}
