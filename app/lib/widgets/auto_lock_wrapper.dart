import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// مغلّف القفل التلقائي — يكتشف خمول المستخدم لمدة 3 دقائق
/// ثم يمسح الذاكرة وينتقل لبوابة الاتصال
class AutoLockWrapper extends StatefulWidget {
  final Widget child;
  final Duration timeout;

  const AutoLockWrapper({
    super.key,
    required this.child,
    this.timeout = const Duration(seconds: 180),
  });

  @override
  State<AutoLockWrapper> createState() => _AutoLockWrapperState();
}

class _AutoLockWrapperState extends State<AutoLockWrapper> {
  Timer? _inactivityTimer;
  Timer? _countdownTicker;
  int _remainingSeconds = 180;
  bool _showWarning = false;
  static const int _warningThreshold = 30;

  @override
  void initState() {
    super.initState();
    _resetTimer();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _countdownTicker?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  void _resetTimer() {
    _inactivityTimer?.cancel();
    _countdownTicker?.cancel();
    setState(() {
      _remainingSeconds = widget.timeout.inSeconds;
      _showWarning = false;
    });
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= _warningThreshold && _remainingSeconds > 0) {
          _showWarning = true;
        }
      });
    });
    _inactivityTimer = Timer(widget.timeout, _lockApp);
  }

  void _lockApp() {
    if (!mounted) return;
    _countdownTicker?.cancel();
    _inactivityTimer?.cancel();
    AppStateManager.clearRam(context);
    Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
  }

  bool _onKeyEvent(KeyEvent event) {
    _resetTimer();
    return false;
  }

  void _onInteraction() => _resetTimer();

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: (_) => _onInteraction(),
      onPointerDown: (_) => _onInteraction(),
      onPointerUp: (_) => _onInteraction(),
      onPointerHover: (_) => _onInteraction(),
      onPointerSignal: (_) => _onInteraction(),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          widget.child,
          if (_showWarning)
            Positioned(
              top: 0, left: 0, right: 0,
              child: _WarningBanner(
                seconds: _remainingSeconds,
                onDismiss: _resetTimer,
              ),
            ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final int seconds;
  final VoidCallback onDismiss;
  const _WarningBanner({required this.seconds, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            const Color(0xFFDC2626).withOpacity(0.9),
            const Color(0xFFB91C1C).withOpacity(0.95),
          ]),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withOpacity(0.3),
              blurRadius: 20, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          const Icon(Icons.lock_clock, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '⚠️ سيتم قفل القبو تلقائياً خلال $seconds ثانية',
              style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: onDismiss,
            icon: const Icon(Icons.touch_app, color: Colors.white, size: 18),
            label: const Text('أنا هنا',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ]),
      ),
    );
  }
}

/// مدير مسح الذاكرة العشوائية (RAM)
class AppStateManager {
  AppStateManager._();
  static void clearRam(BuildContext context) {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.fullReset();
      debugPrint('[🛡️ أمان] تم مسح الذاكرة العشوائية بالكامل.');
    } catch (e) {
      debugPrint('[🛡️ أمان] محاولة مسح الذاكرة: $e');
    }
  }
}
