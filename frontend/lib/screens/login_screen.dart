import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_logo.dart';

enum _LoginStep { phone, otp, pinUnlock, pinCreate }

class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback? onBack;
  final VoidCallback? onHelp;
  final VoidCallback? onTerms;
  const LoginScreen({
    super.key,
    required this.onSuccess,
    this.onBack,
    this.onHelp,
    this.onTerms,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pseudoCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  _LoginStep _step = _LoginStep.phone;
  bool _isNew = false;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    await auth.loadPinState();
    if (!mounted) return;
    setState(() {
      if (auth.needsPinSetup && auth.isAuthenticated) {
        _step = _LoginStep.pinCreate;
      } else if (auth.hasLocalPin) {
        _step = _LoginStep.pinUnlock;
      }
      _bootstrapped = true;
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _pseudoCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.1),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      prefixIcon: Icon(icon, color: Colors.white54),
    );
  }

  String _maskedPhone(String? phone) {
    if (phone == null || phone.length < 4) return '';
    return '•••• ${phone.substring(phone.length - 4)}';
  }

  Future<void> _sendCode() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestCode(_phoneCtrl.text.trim());
    if (ok && mounted) {
      final code = auth.devCode;
      if (code != null && code.isNotEmpty) {
        _codeCtrl.text = code;
      }
      setState(() => _step = _LoginStep.otp);
    }
  }

  Future<void> _verify() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyCode(
      _codeCtrl.text.trim(),
      pseudo: _isNew ? _pseudoCtrl.text.trim() : null,
    );
    if (ok && mounted) {
      _pinCtrl.clear();
      _pinConfirmCtrl.clear();
      setState(() => _step = _LoginStep.pinCreate);
    }
  }

  Future<void> _unlockPin() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.unlockWithPin(_pinCtrl.text.trim());
    if (ok && mounted) widget.onSuccess();
  }

  Future<void> _savePin() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.setLocalPin(
      _pinCtrl.text.trim(),
      confirm: _pinConfirmCtrl.text.trim(),
    );
    if (ok && mounted) widget.onSuccess();
  }

  Future<void> _forgotPin() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestForgotPinCode();
    if (ok && mounted) {
      final code = auth.devCode;
      if (code != null && code.isNotEmpty) {
        _codeCtrl.text = code;
      }
      setState(() => _step = _LoginStep.otp);
      return;
    }
    if (mounted && auth.pinPhone == null && auth.phone == null) {
      setState(() => _step = _LoginStep.phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Scaffold(
      backgroundColor: AppColors.bleuFonce,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            if (widget.onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final hPad = constraints.maxWidth < 360 ? 20.0 : 32.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 24 + viewInsets.bottom),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - viewInsets.bottom).clamp(0.0, double.infinity),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AppLogo(size: 96),
                          const SizedBox(height: 20),
                          const Text(
                            'SafeAlert',
                            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                          const SizedBox(height: 32),
                          if (!_bootstrapped)
                            const SizedBox(
                              height: 28,
                              width: 28,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                            )
                          else if (_step == _LoginStep.phone)
                            ..._phoneFields(auth)
                          else if (_step == _LoginStep.otp)
                            ..._otpFields(auth)
                          else if (_step == _LoginStep.pinUnlock)
                            ..._pinUnlockFields(auth)
                          else
                            ..._pinCreateFields(auth),
                          if (auth.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              auth.error!,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.rouge, fontSize: 12),
                            ),
                          ],
                          if (widget.onHelp != null || widget.onTerms != null) ...[
                            const SizedBox(height: 20),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                if (widget.onHelp != null)
                                  TextButton(
                                    onPressed: widget.onHelp,
                                    child: const Text(
                                      'Manuel',
                                      style: TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ),
                                if (widget.onTerms != null)
                                  TextButton(
                                    onPressed: widget.onTerms,
                                    child: const Text(
                                      'CGU',
                                      style: TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    switch (_step) {
      case _LoginStep.phone:
        return 'Connectez-vous avec votre numéro';
      case _LoginStep.otp:
        return 'Saisissez le code reçu par SMS';
      case _LoginStep.pinUnlock:
        return 'Entrez votre code PIN pour ouvrir l\'application';
      case _LoginStep.pinCreate:
        return 'Créez un code PIN (4 à 6 chiffres). Plus de SMS à chaque connexion.';
    }
  }

  List<Widget> _phoneFields(AuthProvider auth) {
    return [
      Semantics(
        label: 'Numéro de téléphone',
        textField: true,
        child: TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: _fieldDecoration(hint: '+243 XX XXX XXXX', icon: Icons.phone),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: Semantics(
          button: true,
          label: 'Envoyer le code de connexion',
          child: ElevatedButton(
            onPressed: auth.loading ? null : _sendCode,
            child: auth.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Envoyer le code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _otpFields(AuthProvider auth) {
    return [
      if (auth.devCode != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.5)),
          ),
          child: Text(
            'Code de test : ${auth.devCode}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _codeCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
        decoration: _fieldDecoration(hint: 'Code à 6 chiffres', icon: Icons.lock),
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Checkbox(
            value: _isNew,
            onChanged: (v) => setState(() => _isNew = v ?? false),
            fillColor: WidgetStateProperty.resolveWith((_) => Colors.white54),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isNew = !_isNew),
              child: const Text('Nouveau compte', style: TextStyle(color: Colors.white60, fontSize: 12)),
            ),
          ),
        ],
      ),
      if (_isNew) ...[
        TextField(
          controller: _pseudoCtrl,
          decoration: InputDecoration(
            hintText: 'Choisissez un pseudo',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: auth.loading ? null : _verify,
          child: auth.loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Vérifier', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  List<Widget> _pinUnlockFields(AuthProvider auth) {
    final masked = _maskedPhone(auth.pinPhone ?? auth.phone ?? auth.user?['phone'] as String?);
    return [
      if (masked.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Numéro $masked',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      TextField(
        controller: _pinCtrl,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 6,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
        decoration: _fieldDecoration(hint: 'Code PIN', icon: Icons.pin),
        style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 4),
        onSubmitted: (_) {
          if (!auth.loading) _unlockPin();
        },
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: auth.loading ? null : _unlockPin,
          child: auth.loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Déverrouiller', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: auth.loading ? null : _forgotPin,
        child: const Text(
          'Code PIN oublié',
          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ];
  }

  List<Widget> _pinCreateFields(AuthProvider auth) {
    return [
      TextField(
        controller: _pinCtrl,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 6,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
        decoration: _fieldDecoration(hint: 'PIN (6 chiffres recommandés)', icon: Icons.pin),
        style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 4),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pinConfirmCtrl,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 6,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
        decoration: _fieldDecoration(hint: 'Confirmez le code PIN', icon: Icons.lock_outline),
        style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 4),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: auth.loading ? null : _savePin,
          child: auth.loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enregistrer le PIN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }
}
