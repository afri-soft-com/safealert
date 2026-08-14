import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/duress_pin_service.dart';

/// Code démo pour déverrouiller l'app en mode camouflage : 1234=
const kDiscreetUnlockCode = '1234=';

class CalculatorScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  /// Called when the duress PIN is entered (silent SOS, no unlock).
  final VoidCallback? onDuress;
  const CalculatorScreen({super.key, required this.onUnlock, this.onDuress});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _display = '0';
  String _operand1 = '';
  String _operator = '';
  bool _fresh = true;

  void _input(String value) {
    setState(() {
      if (value == 'C') {
        _display = '0';
        _operand1 = '';
        _operator = '';
        _fresh = true;
        return;
      }
      if (value == '=') {
        _tryUnlockOrDuress();
        _compute();
        return;
      }
      if ('+-×÷'.contains(value)) {
        _operand1 = _display;
        _operator = value;
        _fresh = true;
        return;
      }
      if (_fresh) {
        _display = value == '.' ? '0.' : value;
        _fresh = false;
      } else {
        if (value == '.' && _display.contains('.')) return;
        _display += value;
      }
    });
  }

  Future<void> _tryUnlockOrDuress() async {
    final digits = _display.replaceAll(RegExp(r'\D'), '');
    if (await DuressPinService().matches(digits)) {
      widget.onDuress?.call();
      return;
    }
    if (_display == '1234' || '$_operand1$_operator$_display' == kDiscreetUnlockCode) {
      SharedPreferences.getInstance().then((p) => p.setBool('discreet_unlocked_session', true));
      widget.onUnlock();
    }
  }

  void _compute() {
    if (_operand1.isEmpty || _operator.isEmpty) return;
    final a = double.tryParse(_operand1);
    final b = double.tryParse(_display);
    if (a == null || b == null) return;
    double result;
    switch (_operator) {
      case '+':
        result = a + b;
        break;
      case '-':
        result = a - b;
        break;
      case '×':
        result = a * b;
        break;
      case '÷':
        result = b == 0 ? double.nan : a / b;
        break;
      default:
        return;
    }
    _display = result == result.roundToDouble()
        ? result.toInt().toString()
        : result.toStringAsFixed(6).replaceAll(RegExp(r'\.?0+$'), '');
    _operand1 = '';
    _operator = '';
    _fresh = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Semantics(
          label: 'Calculatrice',
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onLongPress: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Déverrouillage SafeAlert : $kDiscreetUnlockCode'),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  },
                  child: Container(
                    alignment: Alignment.bottomRight,
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _display,
                      style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w300),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      _row(['C', '±', '%', '÷']),
                      _row(['7', '8', '9', '×']),
                      _row(['4', '5', '6', '-']),
                      _row(['1', '2', '3', '+']),
                      Expanded(child: _bottomRow()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomRow() {
    return Row(
      children: [
        Expanded(flex: 2, child: _key('0', wide: true)),
        Expanded(child: _key('.')),
        Expanded(child: _key('=')),
      ],
    );
  }

  Widget _row(List<String> keys) {
    return Expanded(
      child: Row(
        children: keys.map((k) => Expanded(child: _key(k))).toList(),
      ),
    );
  }

  Widget _key(String label, {bool wide = false}) {
    final isOp = '+-×÷='.contains(label);
    final isUtil = 'C±%'.contains(label);
    final bg = isOp
        ? const Color(0xFFFF9500)
        : (isUtil ? const Color(0xFF505050) : const Color(0xFF333333));
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Semantics(
        button: true,
        label: 'Touche $label',
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(wide ? 36 : 999),
          child: InkWell(
            borderRadius: BorderRadius.circular(wide ? 36 : 999),
            onTap: () => _input(label),
            child: Center(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 24)),
            ),
          ),
        ),
      ),
    );
  }
}
