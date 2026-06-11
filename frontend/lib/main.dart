import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'providers/auth_provider.dart';
import 'providers/incident_provider.dart';
import 'providers/contacts_provider.dart';
import 'providers/annuaire_provider.dart';
import 'providers/leader_provider.dart';
import 'providers/groups_provider.dart';
import 'providers/history_provider.dart';
import 'providers/admin_provider.dart';
import 'screens/splash_screen.dart';
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
import 'screens/calculator_screen.dart';
import 'screens/help_manual_screen.dart';
import 'services/volume_sos_service.dart';
import 'services/fcm_service.dart';

/// Onglets principaux de la barre de navigation inférieure.
const kMainTabScreens = {'home', 'map', 'contacts', 'annuaire', 'dashboard'};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FCMService().initialize();
  runApp(const SafeAlertApp());
}

class SafeAlertApp extends StatelessWidget {
  const SafeAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..checkAuth()),
        ChangeNotifierProvider(create: (_) => IncidentProvider()),
        ChangeNotifierProvider(create: (_) => ContactsProvider()),
        ChangeNotifierProvider(create: (_) => AnnuaireProvider()),
        ChangeNotifierProvider(create: (_) => LeaderProvider()),
        ChangeNotifierProvider(create: (_) => GroupsProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
      ],
      child: MaterialApp(
        title: 'SafeAlert',
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final List<String> _navStack = ['splash'];
  bool _discreetLocked = false;
  bool _discreetChecked = false;

  String get _currentScreen => _navStack.last;

  bool get _canShowBackButton => _navStack.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkDiscreetMode();
      if (!mounted) return;
      VolumeSOSService.init(() {
        if (mounted && context.read<AuthProvider>().isAuthenticated) {
          context.read<IncidentProvider>().triggerSOS(0, 0, type: 'sos_discret');
        }
      });
    });
  }

  Future<void> _checkDiscreetMode() async {
    await context.read<AuthProvider>().checkAuth();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final sessionUnlocked = prefs.getBool('discreet_unlocked_session') ?? false;
    final localDiscreet = prefs.getBool('discreet_mode_local') ?? false;
    if (mounted) {
      setState(() {
        _discreetLocked = (localDiscreet || context.read<AuthProvider>().isDiscreetMode) && !sessionUnlocked;
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
      return CalculatorScreen(onUnlock: _unlockDiscreet);
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
            _navigate('home');
          },
          onBack: _navStack.length > 1 ? _goBack : () {
            setState(() {
              _navStack..clear()..add('splash');
            });
          },
        );
      case 'calculator':
        screen = CalculatorScreen(onUnlock: _unlockDiscreet);
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
        screen = HeatmapScreen(onNavigate: _navigate, onBack: _onBack);
      case 'safety':
        screen = SafetyScreen(onNavigate: _navigate, onBack: _onBack);
      case 'groups':
        screen = GroupsScreen(onNavigate: _navigate, onBack: _onBack);
      case 'leader':
        screen = LeaderScreen(onNavigate: _navigate, onBack: _onBack);
      case 'help':
        screen = HelpManualScreen(onBack: _goBack);
      case 'settings':
        screen = SettingsScreen(
          onBack: _goBack,
          onPrivacy: () => _navigate('privacy'),
          onHelp: () => _navigate('help'),
          onAdmin: auth.user?['role'] == 'platform_admin' ? () => _navigate('admin') : null,
          onLogout: () {
            auth.logout();
            setState(() {
              _navStack..clear()..add('login');
            });
          },
        );
      case 'privacy':
        screen = PrivacyScreen(onBack: _goBack);
      case 'dashboard':
        screen = DashboardScreen(onNavigate: _navigate, onBack: _onBack);
      case 'history':
        screen = HistoryScreen(onNavigate: _navigate, onBack: _onBack);
      case 'admin':
        screen = AdminScreen(onNavigate: _navigate, onBack: _onBack);
      default:
        screen = HomeScreen(onNavigate: _navigate);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(_currentScreen), child: screen),
      ),
    );
  }
}
