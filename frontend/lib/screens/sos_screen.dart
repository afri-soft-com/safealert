import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../providers/incident_provider.dart';
import '../providers/checkin_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/groups_provider.dart';
import '../services/share_helper.dart';
import '../services/location_service.dart';
import '../services/app_config_service.dart';
import '../services/api_service.dart';
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
  String? _shareUrl;
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

  static const _queuedStepLabels = [
    'GPS localisé (appareil)',
    'Contacts — en attente réseau',
    'Communauté — en attente réseau',
    'Transmission — en attente réseau',
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
    // Allow retry while queued/failed; block only during in-flight or success.
    if (_sending || (_completed && !_queued)) return;
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
    if (_sending) return;
    if (_completed && !_queued) return;
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
        // Not a successful delivery — do not show ENVOYÉ / all green steps.
        _completed = false;
        _step = 1; // GPS only (local). Contacts / communauté encore en attente.
        _statusMsg = result['message']?.toString() ??
            'Alerte enregistrée hors ligne — pas encore envoyée aux contacts.';
        _sosLat = qLat;
        _sosLng = qLng;
        _zoneName = result['zone_name']?.toString();
        _positionApprox = true;
      });
      // Retry flush when connectivity may return.
      unawaited(context.read<IncidentProvider>().flushPendingSos());
      return;
    }

    final note = result['positionNote']?.toString();
    final incident = result['incident'] as Map<String, dynamic>?;
    _incidentId = incident?['id']?.toString();
    _shareUrl = result['share_url']?.toString();
    final approx = note != null && note.isNotEmpty;

    final notification = result['notification'] is Map
        ? Map<String, dynamic>.from(result['notification'] as Map)
        : null;
    final groupSos = notification?['groupSos'];
    final contactsN = (notification?['contactsNotified'] as num?)?.toInt() ?? 0;
    final contactsPush = (notification?['contactsPush'] as num?)?.toInt() ?? 0;
    final contactsSms = (notification?['contactsSms'] as num?)?.toInt() ?? 0;
    String? contactHint;
    if (contactsN == 0) {
      contactHint =
          'Aucun contact de confiance enregistré. Ajoutez des contacts (Paramètres) pour les alerter par push/SMS.';
    } else {
      contactHint =
          'Contacts : $contactsN · Push : $contactsPush · SMS : $contactsSms.';
      if (contactsPush == 0 && contactsSms == 0) {
        contactHint =
            '$contactHint Aucune notification délivrée — le contact doit avoir SafeAlert (même numéro) ou un SMS actif.';
      }
    }
    String? groupHint;
    if (groupSos is Map) {
      final g = (groupSos['groupsNotified'] as num?)?.toInt() ?? 0;
      final a = (groupSos['alertsCreated'] as num?)?.toInt() ?? 0;
      final m = (groupSos['membersNotified'] as num?)?.toInt() ?? 0;
      final others = (groupSos['otherMembers'] as num?)?.toInt() ?? 0;
      final disabled = groupSos['disabled'] == true;
      final alone = groupSos['alone'] == true || (g > 0 && others == 0);
      final errored = groupSos['error'] == true;
      if (errored) {
        groupHint =
            'SOS envoyé, mais la notification des groupes a échoué. Vérifiez l\'onglet Alertes du groupe.';
      } else if (disabled) {
        groupHint =
            'Notification des groupes désactivée dans vos réglages (sos_notify_groups).';
      } else if (g == 0) {
        groupHint =
            'Aucun groupe de voisins lié — rejoignez un groupe (code ou QR) pour les alerter.';
      } else if (alone) {
        groupHint =
            'Alerte publiée dans $g groupe(s) ($a dans Alertes). Vous êtes seul dans le groupe — invitez un autre membre pour push/SMS.';
      } else {
        groupHint =
            'Groupes : $g · Alertes : $a · Autres membres : $others · Contactés (push/SMS) : $m.\nOuvrez Groupe → onglet Alertes pour vérifier.';
      }
      // Refresh local Alertes feed so the sender sees the SOS immediately.
      unawaited(context.read<GroupsProvider>().refreshAllAlerts());
    }

    setState(() {
      final parts = <String>[
        if (note != null && note.isNotEmpty) note,
        if (contactHint != null) contactHint,
        if (groupHint != null) groupHint,
      ];
      if (parts.isNotEmpty) _statusMsg = parts.join('\n');
      _zoneName = incident?['zone_name']?.toString();
      _sosLat = (incident?['lat'] as num?)?.toDouble() ?? (result['lat'] as num?)?.toDouble();
      _sosLng = (incident?['lng'] as num?)?.toDouble() ?? (result['lng'] as num?)?.toDouble();
      _positionApprox = approx;
    });

    if (groupHint != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Groupes de voisins', style: TextStyle(fontSize: 16)),
            content: Text(groupHint!, style: const TextStyle(fontSize: 13, height: 1.35)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    }

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
          _offerSosAudio();
        }
      }
    });
  }

  Future<void> _offerSosAudio() async {
    if (!mounted || _incidentId == null) return;
    if (!AppConfigService().sosAudioEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    final consented = prefs.getBool('sos_audio_consent') == true;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clip audio SOS'),
        content: const Text(
          'Joindre un court enregistrement audio à cette alerte ? '
          'Rétention 7 jours. Vous pouvez refuser.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!consented) {
      await prefs.setBool('sos_audio_consent', true);
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['m4a', 'aac', 'mp3', 'wav', 'ogg', '3gp'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fichier trop volumineux (max 2 Mo)')),
          );
        }
        return;
      }
      final ext = path.split('.').last.toLowerCase();
      final mime = switch (ext) {
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg',
        '3gp' => 'audio/3gpp',
        _ => 'audio/mp4',
      };
      final b64 = base64Encode(bytes);
      await ApiService().post('/sos/$_incidentId/evidence', {
        'consent_evidence': true,
        'evidence': [
          {'media_type': 'audio', 'data_url': 'data:$mime;base64,$b64'},
        ],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio joint à l\'alerte')),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e, isError: true, fallback: 'Envoi audio impossible');
      }
    }
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
    var text = ShareHelper.sosMessage(
      lat: lat,
      lng: lng,
      pseudo: pseudo,
      zoneName: zone,
      approximate: approx,
    );
    if (_shareUrl != null && _shareUrl!.isNotEmpty) {
      text = '$text\nSuivi live : $_shareUrl';
    }
    return text;
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
                  // Warn / error banners ONLY — never for successful delivery notes.
                  if (_failed || _queued)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _failed
                            ? const Color(0xFFFDECEC)
                            : const Color(0xFFFFF6E8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _failed
                              ? AppColors.rouge.withValues(alpha: 0.35)
                              : AppColors.orange.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _failed
                                ? Icons.error_outline_rounded
                                : Icons.wifi_off_rounded,
                            size: 20,
                            color: _failed ? AppColors.rouge : AppColors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusMsg ??
                                  (_queued
                                      ? 'Alerte enregistrée sur l\'appareil — pas encore transmise. Réessayez ou ouvrez Paramètres → Envois en attente.'
                                      : 'L\'alerte n\'a pas pu être envoyée. Réessayez.'),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: _failed
                                    ? AppColors.rougeDark
                                    : const Color(0xFF7A4F00),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_completed && !_queued && !_failed && !_sending)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.grisClair,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Maintenez le bouton rouge ~1,5 s pour envoyer. '
                        'GPS recommandé. Les contacts et groupes reçoivent push + SMS.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.gris,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: _failed
                        ? 'Réessayer d\'envoyer l\'alerte SOS'
                        : _queued
                            ? 'Alerte SOS en attente hors ligne'
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
                              color: AppColors.rouge,
                              backgroundColor: AppColors.rouge.withValues(alpha: 0.18),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 160, height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _queued
                                  ? AppColors.orange
                                  : _step > 0
                                      ? AppColors.rougeDark
                                      : AppColors.rouge,
                              boxShadow: [
                                BoxShadow(
                                  color: (_queued ? AppColors.orange : AppColors.rouge)
                                      .withValues(alpha: _step > 0 ? 0.2 : 0.15),
                                  blurRadius: _step > 0 ? 32 : 12,
                                  spreadRadius: _step > 0 ? 16 : 0,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _failed
                                    ? '📶\nRÉESSAYER'
                                    : _queued
                                        ? '📶\nEN ATTENTE'
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
                  const SizedBox(height: 28),
                  ...List.generate(_steps.length, (i) {
                    final s = _steps[i];
                    // Queued offline: only GPS is local; do not claim contacts/community notified.
                    final done = _queued ? (i == 0 && _step > 0) : _step > i;
                    final pending = _queued && i > 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: done
                            ? s.color.withValues(alpha: 0.1)
                            : pending
                                ? const Color(0xFFFFF8F0)
                                : const Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: done
                              ? s.color.withValues(alpha: 0.45)
                              : pending
                                  ? AppColors.orange.withValues(alpha: 0.35)
                                  : const Color(0xFFE8ECEF),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            done ? '✅' : pending ? '⏳' : s.icon,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _queued ? _queuedStepLabels[i] : s.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: done
                                    ? s.color
                                    : pending
                                        ? AppColors.orange
                                        : AppColors.gris,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_statusMsg != null && !_failed && !_queued) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12, top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.vertClair,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.vert.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 20,
                            color: AppColors.vert,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusMsg!,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: AppColors.vert,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_queued) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final n = await context
                              .read<IncidentProvider>()
                              .flushPendingSos();
                          if (!mounted) return;
                          if (n > 0) {
                            setState(() {
                              _queued = false;
                              _completed = true;
                              _step = 4;
                              _statusMsg =
                                  'Alerte envoyée après reconnexion ($n).';
                            });
                            showAppSnackBar(
                              context,
                              'SOS transmis après reconnexion',
                            );
                          } else {
                            showAppSnackBar(
                              context,
                              'Serveur encore injoignable — réessayez dans 20 s',
                              isError: true,
                            );
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                        label: const Text(
                          'Réessayer l\'envoi maintenant',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                  if ((_completed || _queued) && !_cancelling) ...[
                    if (_sosLat != null && _sosLng != null) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 14, bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _queued
                              ? const Color(0xFFFFF8F0)
                              : AppColors.rougeLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _queued
                                ? AppColors.orange.withValues(alpha: 0.4)
                                : AppColors.rouge.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _queued
                                  ? 'Position enregistrée (envoi en attente)'
                                  : 'Lieu partagé avec vos contacts',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _queued
                                    ? AppColors.orange
                                    : AppColors.rouge,
                              ),
                            ),
                            const SizedBox(height: 6),
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
