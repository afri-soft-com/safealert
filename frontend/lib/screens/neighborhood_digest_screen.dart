import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/location_format.dart';
import '../widgets/app_feedback.dart';
import '../widgets/status_bar.dart';
import '../widgets/top_bar.dart';

/// Écran dédié au résumé quotidien « Veille quartier » (tap notification).
class NeighborhoodDigestScreen extends StatefulWidget {
  final String quartier;
  final VoidCallback onBack;
  final void Function(String screen)? onNavigate;
  final Map<String, String>? notificationData;

  const NeighborhoodDigestScreen({
    super.key,
    required this.quartier,
    required this.onBack,
    this.onNavigate,
    this.notificationData,
  });

  @override
  State<NeighborhoodDigestScreen> createState() => _NeighborhoodDigestScreenState();
}

class _NeighborhoodDigestScreenState extends State<NeighborhoodDigestScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _digest;

  String get _quartier {
    final fromNotif = (widget.notificationData?['quartier'] ?? '').trim();
    if (fromNotif.isNotEmpty) return fromNotif;
    return widget.quartier.trim();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = _quartier;
    if (q.length < 2) {
      setState(() {
        _loading = false;
        _error = 'Quartier manquant dans la notification.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get(
        '/neighborhood/digest?quartier=${Uri.encodeQueryComponent(q)}&hours=24',
      );
      if (!mounted) return;
      setState(() {
        _digest = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      showAppSnackBar(
        context,
        e,
        isError: true,
        fallback: 'Impossible de charger le résumé du quartier.',
      );
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'sos':
        return 'SOS';
      case 'sos_discret':
        return 'SOS discret';
      case 'agression':
        return 'Agression';
      case 'vol':
        return 'Vol';
      case 'suspect':
        return 'Suspect';
      case 'incendie':
        return 'Incendie';
      case 'accident':
        return 'Accident';
      default:
        return type?.isNotEmpty == true ? type! : 'Incident';
    }
  }

  String _severityLabel(String? s) {
    switch (s) {
      case 'alert':
        return 'Alerte';
      case 'warning':
        return 'Attention';
      case 'info':
        return 'Info';
      default:
        return s ?? 'Info';
    }
  }

  Color _severityColor(String? s) {
    switch (s) {
      case 'alert':
        return AppColors.rouge;
      case 'warning':
        return AppColors.orange;
      default:
        return AppColors.bleu;
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
      return 'il y a ${diff.inDays} j';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _digest?['summary'] as Map<String, dynamic>?;
    final total = (summary?['total'] as num?)?.toInt() ??
        int.tryParse(widget.notificationData?['total'] ?? '') ??
        0;
    final sos = (summary?['sos'] as num?)?.toInt() ??
        int.tryParse(widget.notificationData?['sos'] ?? '') ??
        0;
    final warnings = (summary?['warnings'] as num?)?.toInt() ?? 0;
    final info = (summary?['info'] as num?)?.toInt() ?? 0;
    final byType = (summary?['by_type'] as List?) ?? const [];
    final incidents = (_digest?['incidents'] as List?) ?? const [];
    final hours = (_digest?['window_hours'] as num?)?.toInt() ?? 24;

    return Scaffold(
      body: Column(
        children: [
          const StatusBar(),
          TopBar(title: 'Résumé quartier', onBackTap: widget.onBack),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          _quartier.isEmpty ? 'Quartier' : _quartier,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.bleuFonce,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Activité des dernières $hours heures',
                          style: const TextStyle(fontSize: 12, color: AppColors.gris),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Affichage partiel (données notification). Tirez pour réessayer.',
                            style: TextStyle(fontSize: 11, color: AppColors.orange),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _statCard('Total', '$total', AppColors.bleuFonce),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statCard('SOS', '$sos', AppColors.rouge),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statCard('Attention', '$warnings', AppColors.orange),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _statCard('Info', '$info', AppColors.vert),
                            ),
                          ],
                        ),
                        if (byType.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const Text(
                            'Par type',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.bleuFonce,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final raw in byType)
                                if (raw is Map)
                                  Chip(
                                    label: Text(
                                      '${_typeLabel(raw['type']?.toString())} · ${raw['count']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor: const Color(0xFFF3F5F7),
                                  ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Incidents récents',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.bleuFonce,
                                ),
                              ),
                            ),
                            if (widget.onNavigate != null)
                              TextButton(
                                onPressed: () => widget.onNavigate!('map'),
                                child: const Text('Voir la carte'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (incidents.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              total == 0
                                  ? 'Aucun incident signalé dans ce quartier sur $hours h.'
                                  : 'Liste détaillée indisponible pour le moment.',
                              style: const TextStyle(fontSize: 12, color: AppColors.gris),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ...incidents.whereType<Map>().map((inc) {
                            final type = inc['incident_type']?.toString();
                            final severity = inc['severity']?.toString();
                            final desc = (inc['description'] as String?)?.trim();
                            final place = LocationFormat.displayLine(
                              zoneName: inc['zone_name'] as String?,
                              lat: LocationFormat.parseCoord(inc['lat']),
                              lng: LocationFormat.parseCoord(inc['lng']),
                            );
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.blanc,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFEEEEEE)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: _severityColor(severity),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _typeLabel(type),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.bleuFonce,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _severityLabel(severity),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _severityColor(severity),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (desc != null && desc.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(desc, style: const TextStyle(fontSize: 12)),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    place.isNotEmpty ? place : 'Lieu non précisé',
                                    style: const TextStyle(fontSize: 11, color: AppColors.gris),
                                  ),
                                  Text(
                                    _timeAgo(inc['created_at']?.toString()),
                                    style: const TextStyle(fontSize: 11, color: AppColors.gris),
                                  ),
                                ],
                              ),
                            );
                          }),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: widget.onBack,
                          child: const Text('Retour'),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.gris),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
