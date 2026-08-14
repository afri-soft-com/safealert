import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback? onBack;
  const LoginScreen({super.key, required this.onSuccess, this.onBack});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pseudoCtrl = TextEditingController();
  bool _codeSent = false;
  bool _isNew = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _pseudoCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestCode(_phoneCtrl.text.trim());
    if (ok && mounted) {
      // Show whenever API returns devCode (local DEV or temporary prod ALLOW_DEV_OTP)
      final code = auth.devCode;
      if (code != null && code.isNotEmpty) {
        _codeCtrl.text = code;
      }
      setState(() => _codeSent = true);
    }
  }

  Future<void> _verify() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyCode(
      _codeCtrl.text.trim(),
      pseudo: _isNew ? _pseudoCtrl.text.trim() : null,
    );
    if (ok && mounted) widget.onSuccess();
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
                constraints: BoxConstraints(minHeight: constraints.maxHeight - viewInsets.bottom),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                const AppLogo(size: 96),
                const SizedBox(height: 20),
                const Text('SafeAlert', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Connectez-vous avec votre numéro', style: TextStyle(color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 32),
                if (!_codeSent) ...[
                  Semantics(
                    label: 'Numéro de téléphone',
                    textField: true,
                    child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '+243 XX XXX XXXX',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.phone, color: Colors.white54),
                    ),
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
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Envoyer le code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    ),
                  ),
                ] else ...[
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
                    decoration: InputDecoration(
                      hintText: 'Code à 6 chiffres',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white54),
                    ),
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
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Vérifier', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
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
}
