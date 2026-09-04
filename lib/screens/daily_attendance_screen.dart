import '../services/event_selection_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../database/db_helper.dart';
import '../widgets/glass_container.dart';
import '../widgets/app_drawer.dart';
import '../services/connectivity_service.dart';

class DailyAttendanceScreen extends StatefulWidget {
  final int? initialCampaignId;
  const DailyAttendanceScreen({super.key, this.initialCampaignId});

  @override
  State<DailyAttendanceScreen> createState() => _DailyAttendanceScreenState();
}

class _DailyAttendanceScreenState extends State<DailyAttendanceScreen> {
  int _currentPage = 1;
  static const int _pageSize = 10;
  DateTime _selectedDate = DateTime.now();
  int? _selectedCampaignId;
  String _searchQuery = '';
  String _filterMode = 'all'; // all, journalier, unique
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedCampaignId = widget.initialCampaignId ?? EventSelectionService.instance.selectedCampaignId;
    _loadData();
    ConnectivityService.instance.syncTickNotifier.addListener(_onSyncTick);
  }

  void _onSyncTick() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    ConnectivityService.instance.syncTickNotifier.removeListener(_onSyncTick);
    super.dispose();
  }

  void _loadData() async {
    final dateStr = _selectedDate.toString().substring(0, 10);
    try {
      final list = await LocalDatabase.instance.getDailyAttendanceRecords(
        date: dateStr,
        campaignId: _selectedCampaignId,
        query: _searchQuery,
      );

      if (mounted) {
        setState(() {
          _records = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _records = [];
          _isLoading = false;
        });
      }
    }
  }

  void _recordDeparture(String badgeCode) async {
    final success = await LocalDatabase.instance.recordDailyDeparture(
      badgeCode: badgeCode,
      agentId: 1,
    );

    if (success) {
      _loadData();
      ConnectivityService.instance.triggerAutoSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Heure de départ pointée pour $badgeCode'),
              ],
            ),
            backgroundColor: AppColors.successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _selectedDate.toString().substring(0, 10);
    final isToday = dateStr == DateTime.now().toString().substring(0, 10);

    final filteredRecords = _records.where((r) {
      final isJour = r['mode_emargement'] == 'journalier';
      if (_filterMode == 'journalier') return isJour;
      if (_filterMode == 'unique') return !isJour;
      return true;
    }).toList();

    final totalScans = _records.length;
    final totalJournaliers = _records.where((r) => r['mode_emargement'] == 'journalier').length;
    final totalUniques = totalScans - totalJournaliers;

    return Scaffold(
      drawer: const AppDrawer(currentRoute: 'daily_attendance'),
      appBar: AppBar(
        title: Text(
          'Émargements du Jour',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded, color: AppColors.primaryOrange),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2025),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = picked;
                  _isLoading = true;
                });
                _loadData();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Date & KPI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_available_rounded, color: AppColors.successGreen, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isToday ? 'Aujourd\'hui ($dateStr)' : dateStr,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ],
                    ),
                    Text(
                      '$totalScans scan(s)',
                      style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w900, fontSize: 13.5),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 3 KPI Pills
                Row(
                  children: [
                    _buildKpiPill('Total', totalScans, AppColors.accentBlueLight, 'all'),
                    const SizedBox(width: 8),
                    _buildKpiPill('Journaliers', totalJournaliers, AppColors.accentPurpleLight, 'journalier'),
                    const SizedBox(width: 8),
                    _buildKpiPill('Pass Unique', totalUniques, AppColors.successGreen, 'unique'),
                  ],
                ),
              ],
            ),
          ),

          // BANDEAU INDICATIF ÉVÉNEMENT ACTIF
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _selectedCampaignId != null ? AppColors.accentPurple.withOpacity(0.18) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedCampaignId != null ? AppColors.accentPurpleLight.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedCampaignId != null ? Icons.event_available_rounded : Icons.all_inclusive_rounded,
                    color: _selectedCampaignId != null ? AppColors.accentPurpleLight : AppColors.primaryOrange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedCampaignId != null
                          ? '🎯 Filtré sur : ' + (EventSelectionService.instance.selectedCampaignTitle ?? 'Campagne #$_selectedCampaignId')
                          : '🌐 Émargements Globaux (Toutes campagnes)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _selectedCampaignId != null ? AppColors.accentPurpleLight : Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Champ de Recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher participant, badge...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                filled: true,
                fillColor: AppColors.surfaceCard,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (val) {
                _searchQuery = val.trim();
                _loadData();
              },
            ),
          ),

          // Liste des Émargements
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
                : filteredRecords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_busy_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 10),
                            Text(
                              'Aucun émargement pour le $dateStr',
                              style: TextStyle(color: Colors.white.withOpacity(0.4)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        physics: const BouncingScrollPhysics(),
                        itemCount: filteredRecords.length,
                        itemBuilder: (context, index) {
                          final r = filteredRecords[index];
                          final isJour = r['mode_emargement'] == 'journalier';
                          final nom = r['nom_complet'] ?? 'Participant';
                          final badge = r['numero_badge'] ?? 'MKR';
                          final pass = r['type_pass'] ?? 'Standard';
                          final heureArr = r['heure_arrivee'] ?? (r['scanned_at'] != null ? r['scanned_at'].toString().substring(11, 16) : '--:--');
                          final heureDep = r['heure_depart'] as String?;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: GlassContainer(
                              padding: const EdgeInsets.all(12),
                              borderRadius: 14,
                              borderColor: isJour ? AppColors.accentPurple.withOpacity(0.3) : AppColors.borderSubtle,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isJour ? AppColors.accentPurple.withOpacity(0.18) : AppColors.successGreen.withOpacity(0.18),
                                          border: Border.all(color: isJour ? AppColors.accentPurple : AppColors.successGreen, width: 1.5),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            isJour ? Icons.calendar_today_rounded : Icons.check_rounded,
                                            size: 18,
                                            color: isJour ? AppColors.accentPurpleLight : AppColors.successGreen,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nom,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.white),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    badge,
                                                    style: const TextStyle(color: AppColors.primaryOrange, fontFamily: 'monospace', fontSize: 10.5, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(pass, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isJour ? AppColors.accentPurple.withOpacity(0.2) : AppColors.accentBlue.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isJour ? '📅 Multi-Jours' : '🎫 Pass Unique',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: isJour ? AppColors.accentPurpleLight : AppColors.accentBlueLight,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(color: Colors.white12, height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.login_rounded, color: AppColors.successGreen, size: 14),
                                          const SizedBox(width: 4),
                                          Text('Arrivée : $heureArr', style: const TextStyle(color: AppColors.successGreen, fontSize: 11.5, fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 12),
                                          if (heureDep != null) ...[
                                            const Icon(Icons.logout_rounded, color: AppColors.warningAmber, size: 14),
                                            const SizedBox(width: 4),
                                            Text('Départ : $heureDep', style: const TextStyle(color: AppColors.warningAmber, fontSize: 11.5, fontWeight: FontWeight.bold)),
                                          ] else ...[
                                            const Text('● En séance', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                          ],
                                        ],
                                      ),
                                      if (isJour && heureDep == null && isToday)
                                        InkWell(
                                          onTap: () => _recordDeparture(badge),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppColors.warningAmber.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppColors.warningAmber, width: 1),
                                            ),
                                            child: const Text('Pointer Départ', style: TextStyle(color: AppColors.warningAmber, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Barre de Pagination
          if (!_isLoading && filteredRecords.length > _pageSize)
            _buildPaginationBar(
              currentPage: _currentPage,
              totalPages: (filteredRecords.length / _pageSize).ceil(),
              totalItems: filteredRecords.length,
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

  Widget _buildKpiPill(String label, int count, Color color, String mode) {
    final isSelected = _filterMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? color : Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              Text(count.toString(), style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13)),
              Text(label, style: TextStyle(fontSize: 9.5, color: Colors.white.withOpacity(0.7))),
            ],
          ),
        ),
      ),
    );
  }
}
