import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'api_service.dart';

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Fallback store URLs when the API omits platform-specific fields.
const _kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.safealert.safealert';
/// ASC / App Store numeric id for com.kakiranya.safealert (override via APP_STORE_URL_IOS).
const _kAppStoreUrl = 'https://apps.apple.com/app/id6824983610';

const _kDismissPrefsKey = 'safealert_soft_update_dismissed_version';

/// In-app updates: backend version (soft banner) + Google Play (Android release).
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
  bool _forceDialogShown = false;
  bool _flexibleDownloadStarted = false;
  bool _restartPromptShown = false;

  String? _storeUrl;
  String? _iosStoreUrl;
  String? _latestVersion;
  String? _currentVersion;
  int? _currentBuild;
  int? _latestBuild;
  bool _updateAvailable = false;
  bool _forceUpdate = false;
  bool _dismissedForCurrentLatest = false;

  bool get updateAvailable => _updateAvailable;
  bool get forceUpdate => _forceUpdate;
  String? get latestVersion => _latestVersion;
  String? get currentVersion => _currentVersion;
  int? get currentBuild => _currentBuild;
  int? get latestBuild => _latestBuild;
  bool get dismissedForCurrentLatest => _dismissedForCurrentLatest;

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
    check(context, force: true);
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    detach();
  }

  Future<void> dismissSoftBanner() async {
    final latest = _latestVersion;
    if (latest == null || latest.isEmpty) return;
    _dismissedForCurrentLatest = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDismissPrefsKey, latest);
    } catch (_) {}
    _onStateChanged?.call();
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
      // Backend first — Play In-App Update can hang on some devices and used to
      // block the soft banner entirely.
      await _checkBackendVersion(context);
      if (!context.mounted) return;
      await _checkPlayInAppUpdate(context).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('AppUpdateService: Play check timed out');
        },
      );
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

      // Surface soft banner even when Play handles the download (backend
      // version env can lag behind the store listing).
      if (!_updateAvailable) {
        _updateAvailable = true;
        _latestVersion ??= 'nouvelle';
        _dismissedForCurrentLatest = false;
        _onStateChanged?.call();
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

  Future<void> _loadDismissState(String latest) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedForCurrentLatest = prefs.getString(_kDismissPrefsKey) == latest;
    } catch (_) {
      _dismissedForCurrentLatest = false;
    }
  }

  Future<void> _checkBackendVersion(BuildContext context) async {
    Map<String, dynamic>? data;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      data = await _api.get('/app/version?t=$stamp');
    } catch (e) {
      debugPrint('AppUpdateService: /app/version failed ($e)');
      try {
        data = await _api.get('/app/config');
      } catch (e2) {
        debugPrint('AppUpdateService: /app/config fallback failed ($e2)');
        return;
      }
    }

    final latest = (data['latestVersion'] as String?)?.trim() ?? '';
    final min = (data['minVersion'] as String?)?.trim() ?? '';
    final store = (data['storeUrl'] as String?)?.trim();
    final iosStore = (data['iosStoreUrl'] as String?)?.trim();
    final forceFlag = data['forceUpdate'] == true;
    final latestBuildRaw = data['latestBuild'];
    final latestBuild = latestBuildRaw is int
        ? latestBuildRaw
        : int.tryParse('$latestBuildRaw');

    if (store != null && store.isNotEmpty) _storeUrl = store;
    if (iosStore != null && iosStore.isNotEmpty) _iosStoreUrl = iosStore;

    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    final build = int.tryParse(info.buildNumber) ?? 0;
    _currentVersion = current;
    _currentBuild = build;
    _latestBuild = latestBuild;

    final belowMin = min.isNotEmpty && compareVersions(current, min) < 0;
    final belowLatestVersion =
        latest.isNotEmpty && compareVersions(current, latest) < 0;
    final belowLatestBuild =
        latestBuild != null && latestBuild > 0 && build > 0 && build < latestBuild;
    final belowLatest = belowLatestVersion || belowLatestBuild;

    // Installed >= API latest: only clear if Play also did not flag an update.
    if (!belowMin && !belowLatest) {
      if (!_flexibleDownloadStarted &&
          (_updateAvailable || _latestVersion != null || _forceUpdate)) {
        // Keep banner if Play already reported an available store update.
        if (_latestVersion == 'nouvelle') {
          _onStateChanged?.call();
          return;
        }
        _updateAvailable = false;
        _forceUpdate = false;
        _latestVersion = null;
        _latestBuild = null;
        _dismissedForCurrentLatest = false;
        _onStateChanged?.call();
      }
      return;
    }

    // Prefer a label that differs when only the build number moved
    // (avoids "1.0.51 → 1.0.51" which looks broken).
    String? displayLatest;
    String? displayCurrent = current;
    if (belowLatestVersion && latest.isNotEmpty) {
      displayLatest = latest;
    } else if (belowLatestBuild) {
      final ver = latest.isNotEmpty ? latest : current;
      final remoteBuild = latestBuild ?? 0;
      displayLatest = '$ver ($remoteBuild)';
      displayCurrent = '$current ($build)';
    } else if (latest.isNotEmpty) {
      displayLatest = latest;
    } else if (latestBuild != null) {
      displayLatest = 'build $latestBuild';
    }
    _currentVersion = displayCurrent;
    if (displayLatest != null) {
      await _loadDismissState(displayLatest);
    }

    _latestVersion = displayLatest;
    _forceUpdate = forceFlag || belowMin;
    _updateAvailable = true;
    // Force updates ignore soft dismiss.
    if (_forceUpdate) _dismissedForCurrentLatest = false;
    _onStateChanged?.call();

    if (!context.mounted) return;

    if (_forceUpdate) {
      await _showForceDialog(context);
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
        final info = await InAppUpdate.checkForUpdate().timeout(
          const Duration(seconds: 8),
        );
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

    final preferred = _isIOS
        ? (_iosStoreUrl ?? _storeUrl ?? _kAppStoreUrl)
        : (_storeUrl ?? _kPlayStoreUrl);
    final url = Uri.parse(preferred);
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
  final String? currentVersion;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  const AppUpdateBanner({
    super.key,
    this.latestVersion,
    this.currentVersion,
    required this.onUpdate,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final fromTo = (currentVersion != null &&
            currentVersion!.isNotEmpty &&
            latestVersion != null &&
            latestVersion!.isNotEmpty)
        ? 'Vous avez $currentVersion → $latestVersion disponible.'
        : (latestVersion != null && latestVersion!.isNotEmpty
            ? 'SafeAlert $latestVersion est prête. Mettez à jour quand vous voulez.'
            : 'Une version plus récente est prête. Mettez à jour quand vous voulez.');

    return Material(
      elevation: 2,
      color: AppColors.tealDeep,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10 + topInset, 8, 12),
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
                  const SizedBox(height: 2),
                  Text(
                    fromTo,
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
    );
  }
}
