import '../services/event_selection_service.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../database/db_helper.dart';
import '../screens/home_hub_screen.dart';
import '../screens/scanner_hud_screen.dart';
import '../screens/attendees_list_screen.dart';
import '../screens/daily_attendance_screen.dart';
import '../screens/audit_logs_screen.dart';
import '../screens/sync_history_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/login_screen.dart';

class AppDrawer extends StatefulWidget {
  final String currentRoute;
  const AppDrawer({super.key, required this.currentRoute});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Map<String, dynamic>? _agent;
  Map<String, int> _stats = {'pending_sync': 0, 'total_logs': 0};

  @override
  void initState() {
    super.initState();
    _loadDrawerData();
  }

  void _loadDrawerData() async {
    final db = await LocalDatabase.instance.database;
    final agentRows = await db.query('agent_session');
    final stats = await LocalDatabase.instance.getLocalStats();

    if (mounted) {
      setState(() {
        if (agentRows.isNotEmpty) _agent = agentRows.first;
        _stats = stats;
      });
    }
  }

  void _logout() async {
    final db = LocalDatabase.instance;
    await db.logAudit(
      eventType: 'LOGOUT',
      title: 'Fermeture de Session Agent',
      details: 'Déconnexion manuelle',
      agentId: _agent?['id'] ?? 1,
    );
    await db.logoutAgent();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final agentName = _agent?['nom_complet'] ?? 'Agent Makera';
    final codeAgent = _agent?['code_agent'] ?? 'AGT-2026';
    final zone = _agent?['zone_affectation'] ?? 'Porte Principale';

    return Drawer(
      backgroundColor: AppColors.bgDark,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryOrange.withOpacity(0.2),
                      border: Border.all(color: AppColors.primaryOrange, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        agentName.isNotEmpty ? agentName.substring(0, 1).toUpperCase() : 'A',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryOrange, fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          codeAgent,
                          style: const TextStyle(color: AppColors.primaryOrange, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        Text(
                          zone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: EventSelectionService.instance.selectedCampaignId != null
                                ? AppColors.accentBlue.withOpacity(0.2)
                                : AppColors.primaryOrange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            EventSelectionService.instance.selectedCampaignId != null
                                ? '🎯 ' + (EventSelectionService.instance.selectedCampaignTitle ?? 'Événement Ciblé')
                                : '🌐 Mode Multi-Événements',
                            style: TextStyle(
                              color: EventSelectionService.instance.selectedCampaignId != null
                                  ? AppColors.accentBlueLight
                                  : AppColors.primaryOrange,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Navigation Items
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                children: [
                  _buildDrawerItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Tableau de Bord / Hub',
                    route: 'hub',
                    onTap: () {
                      Navigator.pop(context);
                      if (widget.currentRoute != 'hub') {
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeHubScreen()));
                      }
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Scanner de Billets',
                    route: 'scanner',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScannerHudScreen(
                            doorName: zone,
                            agentId: _agent?['id'] ?? 1,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.people_alt_rounded,
                    title: 'Liste des Inscrits',
                    route: 'attendees',
                    onTap: () {
                      Navigator.pop(context);
                      if (widget.currentRoute != 'attendees') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendeesListScreen()));
                      }
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.calendar_today_rounded,
                    title: 'Émargements du Jour',
                    route: 'daily_attendance',
                    badgeColor: AppColors.accentPurple,
                    onTap: () {
                      Navigator.pop(context);
                      if (widget.currentRoute != 'daily_attendance') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const DailyAttendanceScreen()));
                      }
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.history_edu_rounded,
                    title: 'Journal d\'Audit & Activités',
                    route: 'audit',
                    badge: '${_stats['total_logs'] ?? 0}',
                    badgeColor: AppColors.accentBlue,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditLogsScreen()));
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.cloud_sync_rounded,
                    title: 'Synchronisation Cloud',
                    route: 'sync',
                    badge: '${_stats['pending_sync'] ?? 0}',
                    badgeColor: AppColors.primaryOrange,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => SyncHistoryScreen(agentId: _agent?['id'] ?? 1)));
                    },
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  _buildDrawerItem(
                    icon: Icons.settings_rounded,
                    title: 'Paramètres & Diagnostic',
                    route: 'settings',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    },
                  ),
                ],
              ),
            ),

            // Footer (Déconnexion)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.logout_rounded, color: AppColors.dangerRedLight),
                title: const Text('Déconnexion', style: TextStyle(color: AppColors.dangerRedLight, fontWeight: FontWeight.bold, fontSize: 13.5)),
                onTap: _logout,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required String route,
    String? badge,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    final isActive = widget.currentRoute == route;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primaryOrange.withOpacity(0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isActive ? Border.all(color: AppColors.primaryOrange.withOpacity(0.4), width: 1) : null,
      ),
      child: ListTile(
        onTap: onTap,
        dense: true,
        leading: Icon(icon, color: isActive ? AppColors.primaryOrange : Colors.white70, size: 20),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
        trailing: badge != null && badge != '0'
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor ?? AppColors.primaryOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              )
            : null,
      ),
    );
  }
}
