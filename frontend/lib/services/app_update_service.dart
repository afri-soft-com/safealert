import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'api_service.dart';

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// In-app updates: Google Play (Android release) + backend version fallback.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();
  factory AppUpdateService() => instance;

  static const Duration pollInterval = Duration(minutes: 5);
  static const Duration minCheckGap = Duration(seconds: 45);

  final ApiService _api = ApiService();

  Timer? _pollTimer;
  DateTime? _lastCheckAt;
  bool _checking = false;
  bool _bannerVisible = false;
  bool _forceDialogShown = false;
  bool _flexibleDownloadStarted = false;
  bool _restartPromptShown = false;

  String? _storeUrl;
  String? _latestVersion;
  bool _updateAvailable = false;
  bool _forceUpdate = false;

  bool get updateAvailable => _updateAvailable;
  bool get forceUpdate => _forceUpdate;
  String? get latestVersion => _latestVersion;

  VoidCallback? _onStateChanged;

  void attach(VoidCallback onStateChanged) {
    _onStateChanged = onStateChanged;
  }

  void detach() {
    _onStateChanged = null;
  }

  void startPolling(BuildContext context) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (context.mounted) check(context);
    });
    check(context);
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    detach();
  }

  Future<void> check(BuildContext context, {bool force = false}) async {
    if (_checking) return;
    if (!force &&
        _lastCheckAt != null &&
        DateTime.now().difference(_lastCheckAt!) < minCheckGap) {
      return;
    }
    _checking = true;
    _lastCheckAt = DateTime.now();

    try {
      await _checkPlayInAppUpdate(context);
      if (!context.mounted) return;
      await _checkBackendVersion(context);
    } catch (e) {
      debugPrint('AppUpdateService: check failed ($e)');
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkPlayInAppUpdate(BuildContext context) async {
    if (!_isAndroid) return;

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }

      // Prefer flexible UX; fall back to immediate if only that is allowed.
      if (info.flexibleUpdateAllowed && !_flexibleDownloadStarted) {
        _flexibleDownloadStarted = true;
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success && context.mounted) {
          await _promptRestartAfterFlexible(context);
        }
        return;
      }

      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      // Expected on debug / sideload / non-Play installs.
      debugPrint('AppUpdateService: Play in-app update unavailable ($e)');
    }
  }

  Future<void> _promptRestartAfterFlexible(BuildContext context) async {
    if (_restartPromptShown || !context.mounted) return;
    _restartPromptShown = true;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: const Text(
          'Mise à jour prête. Redémarrez pour l’appliquer.',
          style: TextStyle(fontSize: 13),
        ),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'Redémarrer',
          textColor: Colors.white,
          onPressed: () async {
            try {
              await InAppUpdate.completeFlexibleUpdate();
            } catch (e) {
              debugPrint('AppUpdateService: completeFlexibleUpdate failed ($e)');
            }
          },
        ),
      ),
    );
  }

  Future<void> _checkBackendVersion(BuildContext context) async {
    Map<String, dynamic> data;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      data = await _api.get('/app/version?t=$stamp');
    } catch (_) {
      return;
    }

    final latest = (data['latestVersion'] as String?)?.trim() ?? '';
    final min = (data['minVersion'] as String?)?.trim() ?? '';
    final store = (data['storeUrl'] as String?)?.trim();
    final forceFlag = data['forceUpdate'] == true;

    if (store != null && store.isNotEmpty) _storeUrl = store;

    final info = await PackageInfo.fromPlatform();
    final current = info.version;

    final belowMin = min.isNotEmpty && compareVersions(current, min) < 0;
    final belowLatest =
        latest.isNotEmpty && compareVersions(current, latest) < 0;

    // Installed >= latest: hide immediately (ignore stale force flag / cache).
    if (!belowMin && !belowLatest) {
      if (_updateAvailable || _latestVersion != null || _forceUpdate) {
        _updateAvailable = false;
        _forceUpdate = false;
        _latestVersion = null;
        _bannerVisible = false;
        _onStateChanged?.call();
      }
      return;
    }

    _latestVersion = latest.isNotEmpty ? latest : null;
    _forceUpdate = forceFlag || belowMin;
    _updateAvailable = true;
    _onStateChanged?.call();

    if (!context.mounted) return;

    if (_forceUpdate) {
      await _showForceDialog(context);
    } else if (!_bannerVisible) {
      // Soft prompt handled by AppShell banner; also show a one-shot snack once.
      _bannerVisible = true;
    }
  }

  Future<void> _showForceDialog(BuildContext context) async {
    if (_forceDialogShown || !context.mounted) return;
    _forceDialogShown = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Mise à jour requise'),
          content: const Text(
            'Une nouvelle version de SafeAlert est nécessaire pour continuer. '
            'Mettez à jour l’application pour rester protégé.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => openStoreOrUpdate(ctx),
              child: const Text('Mettre à jour'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> openStoreOrUpdate(BuildContext context) async {
    // Try Play flexible/immediate first on Android.
    if (_isAndroid) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable) {
          if (info.immediateUpdateAllowed || _forceUpdate) {
            await InAppUpdate.performImmediateUpdate();
            return;
          }
          if (info.flexibleUpdateAllowed) {
            final result = await InAppUpdate.startFlexibleUpdate();
            if (result == AppUpdateResult.success && context.mounted) {
              await InAppUpdate.completeFlexibleUpdate();
            }
            return;
          }
        }
      } catch (_) {
        // Fall through to store URL.
      }
    }

    final url = Uri.parse(
      _storeUrl ??
          'https://play.google.com/store/apps/details?id=com.safealert.safealert',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// Returns negative if [a] < [b], 0 if equal, positive if [a] > [b].
  static int compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split(RegExp(r'[.+-]')).map((e) => int.tryParse(e) ?? 0).toList();
    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

/// Soft non-blocking banner: « Nouvelle version disponible ».
class AppUpdateBanner extends StatelessWidget {
  final String? latestVersion;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  const AppUpdateBanner({
    super.key,
    this.latestVersion,
    required this.onUpdate,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.tealDeep,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Nouvelle version disponible',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      latestVersion != null && latestVersion!.isNotEmpty
                          ? 'SafeAlert $latestVersion est prête. Mettez à jour quand vous voulez.'
                          : 'Une version plus récente est prête. Mettez à jour quand vous voulez.',
                      style: const TextStyle(
                        color: Color(0xFFB8E0D2),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onUpdate,
                child: const Text(
                  'Mettre à jour',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Plus tard',
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
