import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../database/db_helper.dart';
import '../widgets/glass_container.dart';
import '../widgets/app_drawer.dart';

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  int _currentPage = 1;
  static const int _pageSize = 15;
  List<Map<String, dynamic>> _logs = [];
  String _filterType = 'ALL';
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() async {
    final list = await LocalDatabase.instance.getAuditLogs(
      filterType: _filterType,
      query: _searchQuery,
    );
    if (mounted) {
      setState(() {
        _logs = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(currentRoute: 'audit'),
      appBar: AppBar(
        title: Text(
          'Journal d\'Audit & Sécurité',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryOrange),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadLogs();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Barre de Filtres Rapides
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildFilterChip('ALL', 'Tous (${_logs.length})'),
                  const SizedBox(width: 8),
                  _buildFilterChip('SCAN_OK', '🟢 Scans Valides'),
                  const SizedBox(width: 8),
                  _buildFilterChip('BAN', '⛔ Bannissements'),
                  const SizedBox(width: 8),
                  _buildFilterChip('CANCEL_SCAN', '↩️ Annulations'),
                ],
              ),
            ),
          ),

          // Liste des Logs
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
                : _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 10),
                            Text('Aucune activité enregistrée.', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        physics: const BouncingScrollPhysics(),
                        itemCount: ((_currentPage - 1) * _pageSize + _pageSize > _logs.length)
                            ? (_logs.length - (_currentPage - 1) * _pageSize)
                            : _pageSize,
                        itemBuilder: (context, index) {
                          final realIndex = (_currentPage - 1) * _pageSize + index;
                          final log = _logs[realIndex];
                          final eventType = log['event_type'] ?? 'SCAN';
                          final title = log['title'] ?? 'Action Agent';
                          final details = log['details'] ?? '';
                          final timestamp = log['timestamp'] ?? '';
                          final badge = log['badge_code'] ?? '';

                          Color iconColor = AppColors.accentBlue;
                          IconData iconData = Icons.info_outline;

                          if (eventType.contains('SCAN_OK')) {
                            iconColor = AppColors.successGreen;
                            iconData = Icons.check_circle_rounded;
                          } else if (eventType.contains('BAN')) {
                            iconColor = AppColors.dangerRed;
                            iconData = Icons.block_rounded;
                          } else if (eventType.contains('CANCEL')) {
                            iconColor = AppColors.warningAmber;
                            iconData = Icons.undo_rounded;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: GlassContainer(
                              padding: const EdgeInsets.all(12),
                              borderRadius: 14,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: iconColor.withOpacity(0.15),
                                    ),
                                    child: Icon(iconData, color: iconColor, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                                            ),
                                            Text(
                                              timestamp.length >= 16 ? timestamp.substring(11, 16) : '',
                                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        if (badge.isNotEmpty)
                                          Text(
                                            'Badge : $badge',
                                            style: const TextStyle(color: AppColors.primaryOrange, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                        if (details.isNotEmpty)
                                          Text(
                                            details,
                                            style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11.5),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Barre de Pagination
          if (!_isLoading && _logs.length > _pageSize)
            _buildPaginationBar(
              currentPage: _currentPage,
              totalPages: (_logs.length / _pageSize).ceil(),
              totalItems: _logs.length,
              onPageChanged: (p) => setState(() => _currentPage = p),
            ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar({
    required int currentPage,
    required int totalPages,
    required int totalItems,
    required Function(int) onPageChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: currentPage > 1 ? AppColors.surfaceCardLight : Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Icon(Icons.chevron_left_rounded, color: currentPage > 1 ? Colors.white : Colors.white24, size: 18),
                  const SizedBox(width: 4),
                  Text('Précédent', style: TextStyle(color: currentPage > 1 ? Colors.white : Colors.white24, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Text(
            'Page $currentPage / $totalPages ($totalItems)',
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          InkWell(
            onTap: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: currentPage < totalPages ? AppColors.surfaceCardLight : Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Text('Suivant', style: TextStyle(color: currentPage < totalPages ? Colors.white : Colors.white24, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: currentPage < totalPages ? Colors.white : Colors.white24, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String type, String label) {
    final isSelected = _filterType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterType = type;
          _isLoading = true;
        });
        _loadLogs();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryOrange : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AppColors.primaryOrange : AppColors.borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}
