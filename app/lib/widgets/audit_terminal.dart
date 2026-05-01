import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/mars_theme.dart';

class AuditTerminal extends StatefulWidget {
  const AuditTerminal({super.key});

  @override
  State<AuditTerminal> createState() => _AuditTerminalState();
}

class _AuditTerminalState extends State<AuditTerminal> {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        // Auto-scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        return MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03), // Glassmorphism Fix
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MarsTheme.cyanNeon.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: MarsTheme.cyanNeon.withOpacity(0.1),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: MarsTheme.cyanNeon.withOpacity(0.1),
                        border: Border(bottom: BorderSide(color: MarsTheme.cyanNeon.withOpacity(0.3))),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.terminal, color: MarsTheme.cyanNeon, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'سجل التدقيق الحي',
                            style: GoogleFonts.cairo(
                              color: MarsTheme.cyanNeon,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: MarsTheme.success,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: MarsTheme.success, blurRadius: 5)
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Logs
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: state.auditLogs.length,
                          itemBuilder: (context, index) {
                            final log = state.auditLogs[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '> $log',
                                style: GoogleFonts.firaCode(
                                  color: const Color(0xFF00FF00), // Hacker Green
                                  fontSize: 12,
                                ),
                                textDirection: TextDirection.ltr,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
