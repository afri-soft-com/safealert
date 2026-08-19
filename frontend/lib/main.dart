import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/incident_provider.dart';
import 'providers/contacts_provider.dart';
import 'providers/annuaire_provider.dart';
import 'providers/leader_provider.dart';
import 'providers/groups_provider.dart';
import 'providers/history_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/trip_provider.dart';
import 'providers/checkin_provider.dart';
import 'providers/safety_ping_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/offline_queue_screen.dart';
import 'screens/safety_ping_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/map_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/annuaire_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/leader_screen.dart';
import 'screens/groups_screen.dart';
import 'screens/safety_screen.dart';
import 'screens/heatmap_screen.dart';
import 'screens/history_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/premium_screen.dart';
import 'screens/calculator_screen.dart';
import 'screens/help_manual_screen.dart';
import 'screens/trip_screen.dart';
import 'screens/escort_map_screen.dart';
import 'screens/trust_zones_screen.dart';
import 'screens/neighborhood_screen.dart';
import 'services/volume_sos_service.dart';
import 'services/shake_sos_service.dart';
import 'services/fcm_service.dart';
import 'services/app_update_service.dart';
import 'services/app_config_service.dart';

/// Onglets principaux de la barre de navigation inférieure.
const kMainTabScreens = {'home', 'map', 'contacts', 'annuaire', 'dashboard'};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initCrashReporting();
  FCMService().initialize();
  runApp(const SafeAlertApp());
}

Future<void> _initCrashReporting() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  } catch (e) {
    debugPrint('Crashlytics init skipped: $e');
  }
}

class SafeAlertApp extends StatelessWidget {
  const SafeAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..checkAuth()),
        ChangeNotifierProvider(create: (_) => IncidentProvider()),
        ChangeNotifierProvider(create: (_) => ContactsProvider()),
        ChangeNotifierProvider(create: (_) => AnnuaireProvider()),
        ChangeNotifierProvider(create: (_) => LeaderProvider()),
        ChangeNotifierProvider(create: (_) => GroupsProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
        ChangeNotifierProvider(create: (_) => CheckInProvider()),
        ChangeNotifierProvider(create: (_) => SafetyPingProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProv, _) {
          return MaterialApp(
            title: 'SafeAlert',
            theme: AppTheme.light,
            debugShowCheckedModeBanner: false,
            locale: localeProv.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AppShell(),
          );
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final List<String> _navStack = ['splash'];
  bool _discreetLocked = false;
  bool _discreetChecked = false;
  bool _softUpdateDismissed = false;
  final QuickActions _quickActions = const QuickActions();
  final AppLinks _appLinks = AppLinks();
  final AppUpdateService _appUpdates = AppUpdateService();
  AuthProvider? _auth;

  String get _currentScreen => _navStack.last;

  bool get _canShowBackButton => _navStack.length > 1;

  void _triggerSilentSos() {
    if (!mounted) return;
    if (context.read<AuthProvider>().isAuthenticated) {
      context.read<IncidentProvider>().triggerSOS(0, 0, type: 'sos_discret');
      _navigate('sos');
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    // safealert://invite/CODE or https://.../invite/CODE
    // safealert://group/CODE
    final segments = uri.pathSegments;
    final host = uri.host;
    String? kind;
    String? code;
    if (uri.scheme == 'safealert') {
      kind = host.isNotEmpty ? host : (segments.isNotEmpty ? segments.first : null);
      code = segments.isNotEmpty ? segments.last : uri.path.replaceAll('/', '');
      if (kind == code && segments.length >= 2) {
        kind = segments[0];
        code = segments[1];
      }
    } else if (segments.isNotEmpty) {
      kind = segments[0];
      code = segments.length > 1 ? segments[1] : null;
    }
    if (code == null || code.isEmpty) return;
    code = code.toUpperCase();

    if (!auth.isAuthenticated) {
      _navigate('login');
      return;
    }

    if (kind == 'invite') {
      final ok = await context.read<ContactsProvider>().acceptInvite(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Cercle rejoint !' : 'Invitation invalide ou expirée')),
      );
      if (ok) _navigate('contacts');
    } else if (kind == 'group') {
      final ok = await context.read<GroupsProvider>().joinGroup(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Groupe rejoint !' : 'Code de groupe invalide')),
      );
      if (ok) _navigate('groups');
    }
  }

  void _initDeepLinks() {
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
    _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appUpdates.attach(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkDiscreetMode();
      if (!mounted) return;

      await AppConfigService().refresh(force: true);
      if (mounted) setState(() {});

      VolumeSOSService.init(_triggerSilentSos);
      ShakeSOSService.init(_triggerSilentSos);
      _initDeepLinks();
      _appUpdates.startPolling(context);

      _quickActions.initialize((shortcutType) {
        if (shortcutType == 'sos') _triggerSilentSos();
      });
      _quickActions.setShortcutItems(const [
        ShortcutItem(type: 'sos', localizedTitle: 'SOS SafeAlert', icon: 'ic_launcher'),
      ]);

      final auth = context.read<AuthProvider>();
      _auth = auth;
      auth.addListener(_onAuthChanged);
      if (auth.isAuthenticated) {
        await FCMService().uploadToken();
        if (!mounted) return;
        await context.read<IncidentProvider>().flushOfflineQueue();
        if (!mounted) return;
        await context.read<TripProvider>().fetchActive();
      }
    });
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.isAuthenticated) {
      context.read<TripProvider>().fetchActive();
    } else {
      context.read<TripProvider>().stopTracking();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _appUpdates.check(context);
      if (context.read<AuthProvider>().isAuthenticated) {
        context.read<TripProvider>().fetchActive();
      }
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    _appUpdates.dispose();
    ShakeSOSService.dispose();
    super.dispose();
  }

  Future<void> _checkDiscreetMode() async {
    await context.read<AuthProvider>().checkAuth();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    // One-time: clear stuck local camouflage from early tester builds (default must stay OFF).
    const migrationKey = 'discreet_default_off_v1';
    if (!(prefs.getBool(migrationKey) ?? false)) {
      await prefs.setBool('discreet_mode_local', false);
      await prefs.setBool(migrationKey, true);
    }

    final sessionUnlocked = prefs.getBool('discreet_unlocked_session') ?? false;
    // Default OFF for new installs (null → false).
    final localDiscreet = prefs.getBool('discreet_mode_local') ?? false;
    final profileDiscreet = context.read<AuthProvider>().isDiscreetMode;
    if (mounted) {
      setState(() {
        _discreetLocked = (localDiscreet || profileDiscreet) && !sessionUnlocked;
        _discreetChecked = true;
        if (_discreetLocked) _navStack..clear()..add('calculator');
      });
    }
  }

  void _unlockDiscreet() {
    setState(() {
      _discreetLocked = false;
      _navStack..clear()..add('splash');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camouflage déverrouillé. Pour le désactiver : Paramètres → Camouflage calculatrice. Code : 1234=',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    });
  }

  void _navigate(String screen) {
    final auth = context.read<AuthProvider>();
    if (auth.requiresAuth(screen)) {
      setState(() {
        if (_navStack.last != 'login') {
          _navStack.add('login');
        }
      });
      return;
    }
    if (!auth.canAccessScreen(screen)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accès réservé à un autre profil.', style: TextStyle(fontSize: 12)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      if (kMainTabScreens.contains(screen)) {
        _navStack..clear()..add(screen);
      } else if (_navStack.last != screen) {
        _navStack.add(screen);
      }
    });
  }

  void _goBack() {
    setState(() {
      if (_navStack.length > 1) {
        _navStack.removeLast();
        return;
      }
      final current = _navStack.last;
      if (kMainTabScreens.contains(current) && current != 'home') {
        _navStack..clear()..add('home');
      } else if (current == 'login') {
        _navStack..clear()..add('splash');
      } else if (current == 'home' || current == 'splash') {
        SystemNavigator.pop();
      } else {
        _navStack..clear()..add('home');
      }
    });
  }

  void _enterGuest() {
    context.read<AuthProvider>().enterGuestMode();
    setState(() {
      _navStack..clear()..add('map');
    });
  }

  VoidCallback? get _onBack => _canShowBackButton ? _goBack : null;

  @override
  Widget build(BuildContext context) {
    if (!_discreetChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_discreetLocked) {
      return CalculatorScreen(
        onUnlock: _unlockDiscreet,
        onDuress: _triggerSilentSos,
      );
    }

    final auth = context.watch<AuthProvider>();

    if (_currentScreen == 'splash' && auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _navStack.last == 'splash') {
          setState(() {
            _navStack..clear()..add('home');
          });
        }
      });
    }

    Widget screen;
    switch (_currentScreen) {
      case 'splash':
        screen = SplashScreen(
          onStart: () => _navigate(auth.isAuthenticated ? 'home' : 'login'),
          onGuest: _enterGuest,
        );
      case 'login':
        screen = LoginScreen(
          onSuccess: () {
            auth.exitGuestMode();
            FCMService().uploadToken();
            context.read<IncidentProvider>().flushOfflineQueue();
            _navigate('home');
          },
          onBack: _navStack.length > 1 ? _goBack : () {
            setState(() {
              _navStack..clear()..add('splash');
            });
          },
        );
      case 'calculator':
        screen = CalculatorScreen(
          onUnlock: _unlockDiscreet,
          onDuress: _triggerSilentSos,
        );
      case 'home':
        screen = HomeScreen(onNavigate: _navigate);
      case 'sos':
        screen = SOSScreen(onBack: _goBack);
      case 'map':
        screen = MapScreen(onNavigate: _navigate, isGuest: auth.isGuest, onBack: _onBack);
      case 'contacts':
        screen = ContactsScreen(onNavigate: _navigate, onBack: _onBack);
      case 'annuaire':
        screen = AnnuaireScreen(onNavigate: _navigate, onBack: _onBack);
      case 'heatmap':
        if (!AppConfigService().heatmapEnabled) {
          screen = HomeScreen(onNavigate: _navigate);
          break;
        }
        screen = HeatmapScreen(onNavigate: _navigate, onBack: _onBack);
      case 'safety':
        screen = SafetyScreen(onNavigate: _navigate, onBack: _onBack);
      case 'groups':
        screen = GroupsScreen(onNavigate: _navigate, onBack: _onBack);
      case 'leader':
        screen = LeaderScreen(onNavigate: _navigate, onBack: _onBack);
      case 'trip':
        screen = TripScreen(onBack: _goBack, onNavigate: _navigate);
      case 'escort_map':
        screen = EscortMapScreen(onBack: _goBack);
      case 'trust_zones':
        screen = TrustZonesScreen(onBack: _goBack);
      case 'neighborhood':
        screen = NeighborhoodScreen(onBack: _goBack);
      case 'offline_queue':
        screen = OfflineQueueScreen(onBack: _goBack);
      case 'safety_ping':
        screen = SafetyPingScreen(onBack: _goBack);
      case 'help':
        screen = HelpManualScreen(onBack: _goBack, role: auth.role);
      case 'settings':
        screen = SettingsScreen(
          onBack: _goBack,
          onPrivacy: () => _navigate('privacy'),
          onHelp: () => _navigate('help'),
          onNavigate: _navigate,
          onLeader: auth.canAccessOps ? () => _navigate('leader') : null,
          onAdmin: auth.canAccessAdmin ? () => _navigate('admin') : null,
          onLogout: () {
            auth.logout();
            setState(() {
              _navStack..clear()..add('login');
            });
          },
        );
      case 'privacy':
        screen = PrivacyScreen(onBack: _goBack);
      case 'premium':
        screen = PremiumScreen(onBack: _goBack);
      case 'dashboard':
        screen = DashboardScreen(onNavigate: _navigate, onBack: _onBack);
      case 'history':
        screen = HistoryScreen(onNavigate: _navigate, onBack: _onBack);
      case 'admin':
        screen = AdminScreen(onNavigate: _navigate, onBack: _onBack);
      default:
        screen = HomeScreen(onNavigate: _navigate);
    }

    final cfg = AppConfigService();
    final showMaintenance = cfg.maintenance || !cfg.sosEnabled;
    final showSoftBanner = _appUpdates.updateAvailable &&
        !_appUpdates.forceUpdate &&
        !_softUpdateDismissed &&
        !_discreetLocked &&
        _currentScreen != 'splash' &&
        _currentScreen != 'calculator';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Column(
        children: [
          if (showMaintenance)
            Material(
              color: const Color(0xFF7A4F00),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Text(
                    cfg.maintenanceBanner.isNotEmpty
                        ? cfg.maintenanceBanner
                        : 'Certaines fonctions sont temporairement limitées. L\'annuaire d\'urgence reste disponible.',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          if (showSoftBanner)
            AppUpdateBanner(
              latestVersion: _appUpdates.latestVersion,
              onUpdate: () => _appUpdates.openStoreOrUpdate(context),
              onDismiss: () => setState(() => _softUpdateDismissed = true),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(key: ValueKey(_currentScreen), child: screen),
            ),
          ),
        ],
      ),
    );
  }
}
