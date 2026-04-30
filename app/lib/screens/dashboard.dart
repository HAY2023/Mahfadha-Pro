import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/task_manager.dart';
import '../theme/mars_theme.dart';
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
        final connected = state.deviceStatus.contains('متصل') || state.deviceStatus.contains('المصادقة');
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00FFFF).withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00FFFF).withOpacity(0.05), blurRadius: 20),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFFF).withOpacity(0.5),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.security, color: Color(0xFF00FFFF), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Text('CIPHER VAULT PRO', style: GoogleFonts.orbitron(
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassmorphicMonitor(AppState state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0x2A152033), Color(0x1A0D1117)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20),
            ],
          ),
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
        ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF00FFFF).withOpacity(0.15)),
          ),
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
                      _buildNeonButton('مزامنة الوقت', Icons.sync, const Color(0xFF00FFFF), () => TaskManager().sendHardwareCommand({
                        'cmd': 'sync_time', 'time': DateTime.now().millisecondsSinceEpoch ~/ 1000
                      })),
                      _buildNeonButton('الخزنة', Icons.shield, const Color(0xFFD4AF37), () => context.read<AppState>().setCurrentPage(SidebarPage.accounts)),
                      _buildNeonButton('تعديل البيانات', Icons.edit_note, const Color(0xFF34D399), () => context.read<AppState>().setCurrentPage(SidebarPage.settings)),
                      _buildNeonButton('استيراد', Icons.upload_file, const Color(0xFFB57EDC), () => _openCsvImporter(context)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
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

  Widget _buildNeonButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.1), blurRadius: 15),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(label, style: GoogleFonts.cairo(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }
}
