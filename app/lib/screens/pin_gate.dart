import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/mars_theme.dart';

class PinGateScreen extends StatefulWidget {
  const PinGateScreen({super.key});

  @override
  State<PinGateScreen> createState() => _PinGateScreenState();
}

class _PinGateScreenState extends State<PinGateScreen> {
  String _savedPin = '';
  String _enteredPin = '';
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _checkSavedPin();
  }

  Future<void> _checkSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString('app_pin');
    if (!mounted) return;

    if (pin == null || pin.isEmpty) {
      setState(() {
        _isCreating = true;
        _isLoading = false;
      });
    } else {
      setState(() {
        _savedPin = pin;
        _isCreating = false;
        _isLoading = false;
      });
    }
  }

  void _onKey(String key) async {
    if (key == '⌫') {
      if (_enteredPin.isNotEmpty) {
        setState(() {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        });
      }
      return;
    }

    if (_enteredPin.length < 6) {
      setState(() {
        _enteredPin += key;
      });

      if (_enteredPin.length == 6) {
        if (_isCreating) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('app_pin', _enteredPin);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم حفظ رمز PIN بنجاح!'),
              backgroundColor: MarsTheme.success,
            ),
          );
          Navigator.pushReplacementNamed(context, '/dashboard');
        } else {
          if (_enteredPin == _savedPin) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          } else {
            setState(() {
              _enteredPin = '';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('رمز PIN غير صحيح. حاول مرة أخرى.'),
                backgroundColor: MarsTheme.error,
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: MarsTheme.cyanNeon));
    }

    return Container(
      color: Colors.transparent, // Glassmorphism fix
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(36),
            decoration: MarsTheme.gateGlassCard(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isCreating ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  color: MarsTheme.cyanNeon,
                  size: 48,
                ),
                const SizedBox(height: 20),
                Text(
                  _isCreating ? 'إنشاء رمز PIN (6 أرقام)' : 'أدخل رمز PIN',
                  style: GoogleFonts.cairo(
                    color: MarsTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isCreating
                      ? 'سيُستخدم هذا الرمز لحماية الدخول للتطبيق.'
                      : 'يرجى إدخال رمز PIN للمتابعة.',
                  style: GoogleFonts.cairo(
                    color: MarsTheme.textSecondary,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < _enteredPin.length;
                    return Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? MarsTheme.cyanNeon : Colors.transparent,
                        border: Border.all(
                          color: filled ? MarsTheme.cyanNeon : MarsTheme.textMuted,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                _buildNumpad(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        for (var row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '⌫']])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((key) {
                if (key.isEmpty) return const SizedBox(width: 70, height: 60);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Material(
                    color: Colors.transparent, // Glassmorphism Fix
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _onKey(key),
                      child: Container(
                        width: 70,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05), // Glassmorphism Fix
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Center(
                          child: Text(
                            key,
                            style: GoogleFonts.inter(
                              color: key == '⌫' ? MarsTheme.error : MarsTheme.textPrimary,
                              fontSize: key == '⌫' ? 24 : 26,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
