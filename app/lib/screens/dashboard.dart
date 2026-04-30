import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/task_manager.dart';
import '../theme/mars_theme.dart';
import '../widgets/audit_terminal.dart';
import 'csv_importer_and_health.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
        child: Column(
          children: [
            _buildFuturisticHeader(context),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Consumer<AppState>(
                      builder: (context, state, _) {
                        return _buildGlassmorphicMonitor(state);
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildGlassmorphicOperations(context),
                    const SizedBox(height: 24),
                    const SizedBox(
                      height: 200,
                      child: AuditTerminal(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuturisticHeader(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final connected = state.deviceStatus.contains('متصل') || state.deviceStatus.contains('المصادقة') || state.deviceStatus.contains('بنجاح');
        return _HoverGlassCard(
          glowColor: connected ? const Color(0xFF34D399) : MarsTheme.error,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MarsTheme.cyanNeon.withOpacity(0.5),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.security, color: MarsTheme.cyanNeon, size: 24),
              ),
              const SizedBox(width: 16),
              Text('MAHFADHA PRO', style: GoogleFonts.orbitron(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2,
              )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (connected ? const Color(0xFF34D399) : MarsTheme.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (connected ? const Color(0xFF34D399) : MarsTheme.error).withOpacity(0.5),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.fiber_manual_record, size: 10,
                    color: connected ? const Color(0xFF34D399) : MarsTheme.error),
                  const SizedBox(width: 8),
                  Text(state.deviceStatus, style: GoogleFonts.cairo(
                    color: connected ? const Color(0xFF34D399) : MarsTheme.error,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  )),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlassmorphicMonitor(AppState state) {
    return _HoverGlassCard(
      glowColor: const Color(0xFFD4AF37),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: Color(0xFFD4AF37), size: 22),
              const SizedBox(width: 10),
              Text('نظام المراقبة الحيوي', style: GoogleFonts.cairo(
                color: const Color(0xFFD4AF37), fontSize: 18, fontWeight: FontWeight.bold,
              )),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNeonGauge('الحرارة', state.temperature, 80.0, '°C', Icons.thermostat, const Color(0xFF00FFFF)),
              _buildNeonGauge('المساحة', 100.0 - state.storageUsed, 100.0, '%', Icons.storage, const Color(0xFFD4AF37)),
              _buildNeonGauge('الاستقرار', state.systemLoad, 100.0, '%', Icons.memory, const Color(0xFFB57EDC), invert: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNeonGauge(String label, double value, double maxValue, String unit, IconData icon, Color neonColor, {bool invert = false}) {
    Color gaugeColor = neonColor;
    if (invert && value > 80) gaugeColor = MarsTheme.error;
    
    final percentage = (value / maxValue).clamp(0.0, 1.0);

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: gaugeColor.withOpacity(0.2), blurRadius: 20, spreadRadius: 5),
                ],
              ),
              child: CircularProgressIndicator(
                value: percentage,
                strokeWidth: 8,
                backgroundColor: gaugeColor.withOpacity(0.1),
                color: gaugeColor,
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                Text('${value.toStringAsFixed(1)}$unit', style: GoogleFonts.firaCode(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold,
                )),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(label, style: GoogleFonts.cairo(
          color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600,
        )),
      ],
    );
  }

  Widget _buildGlassmorphicOperations(BuildContext context) {
    return _HoverGlassCard(
      glowColor: MarsTheme.cyanNeon,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('العمليات المركزية', style: GoogleFonts.cairo(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth >= 800 ? 4 : 3,
                childAspectRatio: 1.5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _NeonButton(label: 'مزامنة الوقت', icon: Icons.sync, color: const Color(0xFF00FFFF), onTap: () => TaskManager().sendHardwareCommand({'cmd': 'sync_time', 'time': DateTime.now().millisecondsSinceEpoch ~/ 1000})),
                  _NeonButton(label: 'الخزنة', icon: Icons.shield, color: const Color(0xFFD4AF37), onTap: () => context.read<AppState>().setCurrentPage(SidebarPage.accounts)),
                  _NeonButton(label: 'تعديل البيانات', icon: Icons.edit_note, color: const Color(0xFF34D399), onTap: () => context.read<AppState>().setCurrentPage(SidebarPage.settings)),
                  _NeonButton(label: 'استيراد', icon: Icons.upload_file, color: const Color(0xFFB57EDC), onTap: () => _openCsvImporter(context)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _openCsvImporter(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const CsvImporterWidget(),
        ),
      ),
    );
  }
}

class _HoverGlassCard extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final EdgeInsets padding;

  const _HoverGlassCard({
    required this.child,
    required this.glowColor,
    required this.padding,
  });

  @override
  State<_HoverGlassCard> createState() => _HoverGlassCardState();
}

class _HoverGlassCardState extends State<_HoverGlassCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: _isHovered ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isHovered ? widget.glowColor.withOpacity(0.4) : widget.glowColor.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            if (_isHovered)
              BoxShadow(
                color: widget.glowColor.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 2,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _NeonButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _NeonButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<_NeonButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _isHovered ? widget.color.withOpacity(0.1) : widget.color.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? widget.color.withOpacity(0.6) : widget.color.withOpacity(0.2),
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: widget.color.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: widget.color, size: _isHovered ? 32 : 28),
              const SizedBox(height: 12),
              Text(widget.label, style: GoogleFonts.cairo(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
