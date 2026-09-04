import '../services/event_selection_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/attendee_model.dart';
import '../database/db_helper.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/app_drawer.dart';

class AttendeesListScreen extends StatefulWidget {
  final int? initialCampaignId;
  const AttendeesListScreen({super.key, this.initialCampaignId});

  @override
  State<AttendeesListScreen> createState() => _AttendeesListScreenState();
}

class _AttendeesListScreenState extends State<AttendeesListScreen> {
  int _currentPage = 1;
  static const int _pageSize = 10;
  List<Attendee> _attendees = [];
  int? _selectedCampaignId;
  String _statusFilter = 'all';
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedCampaignId = widget.initialCampaignId ?? EventSelectionService.instance.selectedCampaignId;
    _loadCampaignsAndData();
  }

  void _loadCampaignsAndData() async {
    final list = await LocalDatabase.instance.getAttendees(
      campaignId: _selectedCampaignId,
      query: _searchQuery,
      statusFilter: _statusFilter,
    );

    if (mounted) {
      setState(() {
        _attendees = list;
        _isLoading = false;
      });
    }
  }

  void _refreshList() async {
    final list = await LocalDatabase.instance.getAttendees(
      campaignId: _selectedCampaignId,
      query: _searchQuery,
      statusFilter: _statusFilter,
    );
    if (mounted) {
      setState(() => _attendees = list);
    }
  }

  void _showAttendeeActionModal(Attendee a) {
    final isBanned = a.isBanned == 1;
    final isScanned = a.statutCheckin == 'scanne';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isBanned ? AppColors.dangerRed.withOpacity(0.2) : (isScanned ? AppColors.successGreen.withOpacity(0.2) : AppColors.primaryOrange.withOpacity(0.2)),
                  ),
                  child: Center(
                    child: Icon(
                      isBanned ? Icons.block : (isScanned ? Icons.check_circle_rounded : Icons.person_rounded),
                      color: isBanned ? AppColors.dangerRed : (isScanned ? AppColors.successGreen : AppColors.primaryOrange),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.nomComplet,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${a.numeroBadge} • ${a.typePass}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (isBanned)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppColors.successGreen.withOpacity(0.12),
                leading: const Icon(Icons.lock_open_rounded, color: AppColors.successGreen),
                title: const Text('Lever le Bannissement (Débannir)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text('Restaure le droit d\'accès de ce participant', style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await LocalDatabase.instance.unbanAttendee(
                    badgeCode: a.numeroBadge,
                    agentId: 1,
                    reason: 'Levée manuelle par agent',
                  );
                  _refreshList();
                  ConnectivityService.instance.triggerAutoSync();
                },
              ),

            if (!isBanned && isScanned)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppColors.warningAmber.withOpacity(0.12),
                leading: const Icon(Icons.undo_rounded, color: AppColors.warningAmber),
                title: const Text('Annuler le Scan / Remettre en attente', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text('Réinitialise le badge à l\'état non-scanné', style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await LocalDatabase.instance.cancelScan(
                    badgeCode: a.numeroBadge,
                    agentId: 1,
                  );
                  _refreshList();
                  ConnectivityService.instance.triggerAutoSync();
                },
              ),

            const SizedBox(height: 10),

            if (!isBanned)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppColors.dangerRed.withOpacity(0.12),
                leading: const Icon(Icons.block_flipped, color: AppColors.dangerRed),
                title: const Text('Bannir ce Participant', style: TextStyle(color: AppColors.dangerRedLight, fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text('Bloque immédiatement l\'accès aux portes', style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showBanDialog(a);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showBanDialog(Attendee a) {
    final reasonController = TextEditingController(text: 'Comportement suspect');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Bannir ${a.nomComplet}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Motif du bannissement',
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                filled: true,
                fillColor: AppColors.surfaceCardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await LocalDatabase.instance.banAttendee(
                badgeCode: a.numeroBadge,
                reason: reasonController.text.trim(),
                agentId: 1,
              );
              _refreshList();
              ConnectivityService.instance.triggerAutoSync();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
            child: const Text('Bannir Immédiatement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),

          // Barre de Pagination
          if (!_isLoading && _attendees.length > _pageSize)
            _buildPaginationBar(
              currentPage: _currentPage,
              totalPages: (_attendees.length / _pageSize).ceil(),
              totalItems: _attendees.length,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(currentRoute: 'attendees'),
      appBar: AppBar(
        title: Text(
          'Annuaire des Participants',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryOrange),
            onPressed: _loadCampaignsAndData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barre de Recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher par nom, badge, email...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                filled: true,
                fillColor: AppColors.surfaceCard,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (val) {
                _searchQuery = val.trim();
                _refreshList();
              },
            ),
          ),

          // BANDEAU INDICATIF ÉVÉNEMENT ACTIF
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _selectedCampaignId != null ? AppColors.accentBlue.withOpacity(0.18) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedCampaignId != null ? AppColors.accentBlueLight.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedCampaignId != null ? Icons.filter_alt_rounded : Icons.all_inclusive_rounded,
                    color: _selectedCampaignId != null ? AppColors.accentBlueLight : AppColors.primaryOrange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedCampaignId != null
                          ? '🎯 Événement ciblé : ' + (EventSelectionService.instance.selectedCampaignTitle ?? 'Campagne #$_selectedCampaignId')
                          : '🌐 Mode Global (Tous les événements)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _selectedCampaignId != null ? AppColors.accentBlueLight : Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_selectedCampaignId != null)
                    InkWell(
                      onTap: () async {
                        await EventSelectionService.instance.setSelectedCampaign(campaignId: null);
                        setState(() => _selectedCampaignId = null);
                        _refreshList();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Tout voir', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Filtres par statut (Pilules)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildStatusTab('all', 'Tous (${_attendees.length})'),
                  const SizedBox(width: 8),
                  _buildStatusTab('non_scanne', '⏳ En attente'),
                  const SizedBox(width: 8),
                  _buildStatusTab('scanne', '✓ Validés'),
                  const SizedBox(width: 8),
                  _buildStatusTab('banni', '🚫 Bannis'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Liste des Participants avec Pagination
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
                : _attendees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_off_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 10),
                            Text('Aucun participant trouvé.', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        physics: const BouncingScrollPhysics(),
                        itemCount: ((_currentPage - 1) * _pageSize + _pageSize > _attendees.length)
                            ? (_attendees.length - (_currentPage - 1) * _pageSize)
                            : _pageSize,
                        itemBuilder: (context, index) {
                          final realIndex = (_currentPage - 1) * _pageSize + index;
                          final a = _attendees[realIndex];
                          final isBanned = a.isBanned == 1;
                          final isScanned = a.statutCheckin == 'scanne';
                          final photoUrl = a.resolvedPhotoUrl;

                          Color borderCol = AppColors.borderSubtle;
                          if (isBanned) borderCol = AppColors.dangerRed.withOpacity(0.5);
                          if (isScanned) borderCol = AppColors.successGreen.withOpacity(0.4);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () => _showAttendeeActionModal(a),
                              child: GlassContainer(
                                padding: const EdgeInsets.all(12),
                                borderRadius: 14,
                                borderColor: borderCol,
                                child: Row(
                                  children: [
                                    // Avatar avec badge coche verte si scanné
                                    Stack(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppColors.surfaceCardLight,
                                          ),
                                          child: ClipOval(
                                            child: photoUrl != null
                                                ? Image.network(
                                                    photoUrl,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Center(
                                                      child: Text(
                                                        a.nomComplet.isNotEmpty ? a.nomComplet.substring(0, 1).toUpperCase() : 'P',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                                      ),
                                                    ),
                                                  )
                                                : Center(
                                                    child: Text(
                                                      a.nomComplet.isNotEmpty ? a.nomComplet.substring(0, 1).toUpperCase() : 'P',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        if (isScanned)
                                          Positioned(
                                            bottom: -1,
                                            right: -1,
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: AppColors.successGreen,
                                                border: Border.all(color: Colors.white, width: 1.5),
                                              ),
                                              child: const Center(
                                                child: Text('✓', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  a.nomComplet,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13.5,
                                                    color: isBanned ? AppColors.dangerRedLight : Colors.white,
                                                    decoration: isBanned ? TextDecoration.lineThrough : null,
                                                  ),
                                                ),
                                              ),
                                              if (isBanned)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.dangerRed.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text('BANNI', style: TextStyle(color: AppColors.dangerRedLight, fontSize: 9.5, fontWeight: FontWeight.w900)),
                                                )
                                              else if (isScanned)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.successGreen.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '✓ ${a.scannedAt != null && a.scannedAt!.length >= 16 ? a.scannedAt!.substring(11, 16) : "Scanné"}',
                                                    style: const TextStyle(color: AppColors.successGreenLight, fontSize: 9.5, fontWeight: FontWeight.w900),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.08),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  a.numeroBadge,
                                                  style: const TextStyle(color: AppColors.primaryOrange, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 10.5),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                a.typePass,
                                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTab(String status, String label) {
    final isSelected = _statusFilter == status;
    return GestureDetector(
      onTap: () {
        setState(() => _statusFilter = status);
        _refreshList();
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
