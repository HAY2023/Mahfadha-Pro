import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/mars_theme.dart';
import 'setup_wizard.dart';
import 'dashboard.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class ConnectionGateScreen extends StatefulWidget {
  const ConnectionGateScreen({super.key});

  @override
  State<ConnectionGateScreen> createState() => _ConnectionGateScreenState();
}

class _ConnectionGateScreenState extends State<ConnectionGateScreen> {
  bool _isSearching = true;

  @override
  void initState() {
    super.initState();
    _simulateHardwareHandshake();
  }

  // محاكاة الاتصال بالجهاز المادي عبر USB
  void _simulateHardwareHandshake() async {
    await Future.delayed(const Duration(seconds: 4));
    
    if (mounted) {
      setState(() {
        _isSearching = false;
      });
      
      // الانتقال بعد نجاح الاتصال
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home'); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // خلفية مريخية متدرجة
          Container(
            decoration: const BoxDecoration(
              gradient: MarsTheme.marsRadial,
            ),
          ),
          // التأثير الزجاجي (Glassmorphism)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(40),
                  decoration: MarsTheme.gateGlassCard(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isSearching ? Icons.shield_moon_outlined : Icons.check_circle_outline,
                        size: 80,
                        color: _isSearching ? Colors.white54 : MarsTheme.cyanNeon,
                      ),
                      const SizedBox(height: 30),
                      Text(
                        _isSearching ? "جاري البحث عن الدرع السيبراني..." : "تم الاتصال بنجاح",
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (_isSearching)
                        const CircularProgressIndicator(
                          color: MarsTheme.cyanNeon,
                          strokeWidth: 2,
                        ),
                      if (!_isSearching)
                        Text(
                          "أهلاً بك في محفظة برو - القبو السيبراني المطلق",
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
