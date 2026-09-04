import '../services/event_selection_service.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../database/db_helper.dart';
import '../models/attendee_model.dart';
import '../utils/sound_haptic_helper.dart';
import '../widgets/scan_result_sheet.dart';
import 'scanner_hud_screen.dart';

class HomeHubScreen extends StatefulWidget {
  const HomeHubScreen({super.key});

  @override
  State<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends State<HomeHubScreen> {
  Map<String, dynamic>? _agent;
  List<Map<String, dynamic>> _campaigns = [];
  int? _selectedCampaignId; // null = Tout voir
  Map<String, int> _stats = {'total': 0, 'scanned': 0, 'remaining': 0, 'pending_sync': 0};
  bool _isLoading = true;
  bool _isManualSyncing = false;
  bool _isSearching = false;

  final TextEditingController _manualSearchController = TextEditingController();
  List<Attendee> _manualSearchResults = [];

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    ConnectivityService.instance.syncTickNotifier.addListener(_onAutoSyncTick);
  }

  void _onAutoSyncTick() {
    if (mounted) _loadLocalData();
  }

  @override
  void dispose() {
    ConnectivityService.instance.syncTickNotifier.removeListener(_onAutoSyncTick);
    _manualSearchController.dispose();
    super.dispose();
  }

  void _loadLocalData() async {
    await EventSelectionService.instance.init();
    final db = await LocalDatabase.instance.database;
    final agentRows = await db.query('agent_session');
    final campList = await LocalDatabase.instance.getAllCampaigns();
    _selectedCampaignId = EventSelectionService.instance.selectedCampaignId;
    final stats = await LocalDatabase.instance.getLocalStats(campaignId: _selectedCampaignId);

    if (mounted) {
      setState(() {
        if (agentRows.isNotEmpty) _agent = agentRows.first;
        _campaigns = campList;
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  void _onSelectCampaign(int? campId) async {
    setState(() => _selectedCampaignId = campId);
    String? cTitle;
    if (campId != null) {
      final found = _campaigns.firstWhere((c) => c['id'] == campId, orElse: () => {});
      cTitle = found['titre']?.toString();
    }
    await EventSelectionService.instance.setSelectedCampaign(
      campaignId: campId,
      campaignTitle: cTitle,
    );
    final stats = await LocalDatabase.instance.getLocalStats(campaignId: campId);
    if (mounted) {
      setState(() {
        _stats = stats;
      });
    }
  }

  void _onManualSearchChanged(String query) async {
    final q = query.trim();
    if (q.length >= 2) {
      final results = await LocalDatabase.instance.getAttendees(
        campaignId: _selectedCampaignId,
        query: q,
      );
      if (mounted) {
        setState(() {
          _manualSearchResults = results.take(3).toList();
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _manualSearchResults = [];
        });
      }
    }
  }

  Future<void> _handleManualValidate([String? directCode]) async {
    final query = (directCode ?? _manualSearchController.text).trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Veuillez entrer un code de billet, nom, téléphone ou email.'),
          backgroundColor: AppColors.warningAmber,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSearching = true);

    final zone = _agent?['zone_affectation'] ?? 'Porte Principale';
    final agentId = _agent?['id'] ?? 1;

    // 1. Essai direct de validation par code badge ou commande_ref
    final directRes = await LocalDatabase.instance.validateBadge(
      query,
      zone,
      agentId,
      activeCampaignId: _selectedCampaignId,
    );

    if (directRes['status'] != 'invalid') {
      setState(() => _isSearching = false);
      _processScanResult(directRes, query);
      _manualSearchController.clear();
      setState(() => _manualSearchResults = []);
      return;
    }

    // 2. Recherche par nom, téléphone ou email
    final matches = await LocalDatabase.instance.getAttendees(
      campaignId: _selectedCampaignId,
      query: query,
    );

    setState(() => _isSearching = false);

    if (matches.isEmpty) {
      SoundHapticHelper.triggerError();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Aucun billet ou participant trouvé.', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          backgroundColor: AppColors.dangerRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else if (matches.length == 1) {
      // 1 seul résultat trouvé -> Valider immédiatement !
      final target = matches.first;
      final res = await LocalDatabase.instance.validateBadge(
        target.numeroBadge,
        zone,
        agentId,
        activeCampaignId: _selectedCampaignId,
      );
      _processScanResult(res, target.numeroBadge);
      _manualSearchController.clear();
      setState(() => _manualSearchResults = []);
    } else {
      // Plusieurs résultats -> Ouvrir le sélecteur rapide
      _showMultipleMatchesSheet(matches, zone, agentId);
    }
  }

  void _processScanResult(Map<String, dynamic> res, String badgeCode) async {
    ScanResultType resultType;
    if (res['status'] == 'valid') {
      resultType = ScanResultType.valid;
      SoundHapticHelper.triggerSuccess();
      ConnectivityService.instance.triggerAutoSync();
    } else if (res['status'] == 'already_scanned') {
      resultType = ScanResultType.alreadyUsed;
      SoundHapticHelper.triggerWarning();
    } else if (res['status'] == 'banned') {
      resultType = ScanResultType.banned;
      SoundHapticHelper.triggerBanned();
    } else {
      resultType = ScanResultType.invalid;
      SoundHapticHelper.triggerError();
    }

    _loadLocalData();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScanResultModal(
        resultType: resultType,
        attendee: res['attendee'],
        rawBadgeCode: badgeCode,
        wrongCampaign: res['wrongCampaign'] == true,
        agentId: _agent?['id'] ?? 1,
        onNextScan: () => Navigator.pop(context),
        onStatusChanged: () => _loadLocalData(),
      ),
    );
    _loadLocalData();
  }

  void _showMultipleMatchesSheet(List<Attendee> matches, String zone, int agentId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Participants Correspondants',
                  style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${matches.length} trouvés',
                    style: const TextStyle(color: AppColors.primaryOrange, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: matches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final a = matches[idx];
                  final isScanned = a.statutCheckin == 'scanne';
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCardLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isScanned ? AppColors.successGreen.withOpacity(0.18) : AppColors.primaryOrange.withOpacity(0.18),
                          ),
                          child: Center(
                            child: Icon(
                              isScanned ? Icons.check_circle_outline_rounded : Icons.person_outline_rounded,
                              color: isScanned ? AppColors.successGreen : AppColors.primaryOrange,
                              size: 20,
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
                                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${a.typePass.toUpperCase()} • Code: ${a.numeroBadge}',
                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final res = await LocalDatabase.instance.validateBadge(
                              a.numeroBadge,
                              zone,
                              agentId,
                              activeCampaignId: _selectedCampaignId,
                            );
                            _processScanResult(res, a.numeroBadge);
                            _manualSearchController.clear();
                            setState(() => _manualSearchResults = []);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isScanned ? AppColors.surfaceElevated : AppColors.primaryOrange,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            isScanned ? 'Détails' : 'Valider',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleForceSync() async {
    setState(() => _isManualSyncing = true);
    final res = await ApiService.forceFullSync();
    setState(() => _isManualSyncing = false);

    _loadLocalData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              res['success'] == true ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                res['message'] ?? (res['success'] == true ? 'Synchronisation réussie !' : 'Erreur de synchronisation'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: res['success'] == true ? AppColors.successGreen : AppColors.dangerRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  


  String _formatDateRange(String? start, String? end) {
    if (start == null || start.isEmpty) return 'Date en attente';
    final s = start.length >= 10 ? start.substring(0, 10) : start;
    if (end == null || end.isEmpty || end == start) {
      return s;
    }
    final e = end.length >= 10 ? end.substring(0, 10) : end;
    return 'Du $s au $e';
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Déconnexion', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Voulez-vous fermer votre session ? Les scans non synchronisés restent sauvegardés dans la mémoire locale du téléphone.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await LocalDatabase.instance.logoutAgent();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
            child: const Text('Déconnecter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAgentProfileModal() {
    final agentName = _agent?['nom_complet'] ?? 'Agent Makera';
    final codeAgent = _agent?['code_agent'] ?? 'AGT-2026';
    final roleAgent = _agent?['role_agent'] ?? 'Contrôleur Terrain';
    final zone = _agent?['zone_affectation'] ?? 'Porte Principale';
    final phone = _agent?['telephone'] ?? 'Non renseigné';
    final totalScans = _agent?['total_scans'] ?? _stats['scanned'] ?? 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barre fine poignée supérieure
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // Grand Avatar avec statut vert
            Stack(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryOrange.withOpacity(0.18),
                    border: Border.all(color: AppColors.primaryOrange, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryOrange.withOpacity(0.35),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      agentName.isNotEmpty ? agentName.substring(0, 1).toUpperCase() : 'A',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryOrange,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.successGreen,
                      border: Border.all(color: AppColors.surfaceCard, width: 2.5),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Nom et Rôle
            Text(
              agentName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$roleAgent • $zone',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withOpacity(0.65),
              ),
            ),

            const SizedBox(height: 10),

            // Badge Capsule Code Agent
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint, color: AppColors.primaryOrange, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    codeAgent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryOrange,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Carte des détails d'affectation
            GlassContainer(
              padding: const EdgeInsets.all(14),
              borderRadius: 16,
              child: Column(
                children: [
                  _buildProfileDetailRow(Icons.meeting_room_outlined, 'Zone Affectée', zone),
                  const Divider(color: Colors.white12, height: 16),
                  _buildProfileDetailRow(Icons.phone_outlined, 'Téléphone', phone.toString()),
                  const Divider(color: Colors.white12, height: 16),
                  _buildProfileDetailRow(Icons.qr_code_2_rounded, 'Total Scans Effectués', '$totalScans scans'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Actions : Paramètres & Déconnexion
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                    icon: const Icon(Icons.tune_rounded, size: 18, color: Colors.white),
                    label: const Text('Paramètres', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceCardLight,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmLogout();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.dangerRedLight),
                    label: const Text('Déconnexion', style: TextStyle(color: AppColors.dangerRedLight, fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.dangerRed.withOpacity(0.15),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.dangerRed.withOpacity(0.3)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
      );
    }

    final agentName = _agent?['nom_complet'] ?? 'Agent Makera';
    final roleAgent = _agent?['role_agent'] ?? 'Contrôleur';
    final zone = _agent?['zone_affectation'] ?? 'Porte Principale';
    final totalInscrits = _stats['total'] ?? 0;
    final totalScannes = _stats['scanned'] ?? 0;
    final totalRestants = _stats['remaining'] ?? 0;
    final pendingSync = _stats['pending_sync'] ?? 0;
    final progressPct = totalInscrits > 0 ? (totalScannes / totalInscrits).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      drawer: const AppDrawer(currentRoute: 'hub'),
      body: SafeArea(
        child: Column(
          children: [
            // 1. TOP HEADER (Fluid Responsive Header - 0 Overflow Guarantee)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  // Menu Drawer Button
                  Builder(
                    builder: (ctx) => InkWell(
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: const Center(
                          child: Icon(Icons.menu_rounded, color: Colors.white, size: 21),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Sync Action Button
                  InkWell(
                    onTap: _isManualSyncing ? null : _handleForceSync,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Center(
                        child: _isManualSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryOrange,
                                ),
                              )
                            : Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.cloud_sync_rounded, color: AppColors.accentBlueLight, size: 20),
                                  if (pendingSync > 0)
                                    Positioned(
                                      top: -3,
                                      right: -3,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.dangerRed,
                                        ),
                                        child: Text(
                                          pendingSync > 9 ? '9+' : '$pendingSync',
                                          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Agent Profile Info (Expanded for 0 Overflow & High Legibility)
                  Expanded(
                    child: InkWell(
                      onTap: _showAgentProfileModal,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    agentName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '$roleAgent • $zone',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.white.withOpacity(0.65),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.successGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Avatar Badge
                            Stack(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primaryOrange.withOpacity(0.18),
                                    border: Border.all(color: AppColors.primaryOrange, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      agentName.isNotEmpty ? agentName.substring(0, 1).toUpperCase() : 'A',
                                      style: const TextStyle(
                                        color: AppColors.primaryOrange,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.successGreen,
                                      border: Border.all(color: AppColors.bgDark, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. MAIN SCROLLABLE DASHBOARD BODY
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SECTION : ÉVÉNEMENTS ASSIGNÉS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ÉVÉNEMENTS ASSIGNÉS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white60, letterSpacing: 0.8),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_campaigns.length} événement(s)',
                            style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Carrousel Horizontal Épuré (Cartes Vectorielles Pro)
                    SizedBox(
                      height: 122,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _campaigns.length + 1,
                        itemBuilder: (ctx, index) {
                          if (index == 0) {
                            final isSelected = _selectedCampaignId == null;
                            return GestureDetector(
                              onTap: () => _onSelectCampaign(null),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 170,
                                margin: const EdgeInsets.only(right: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primaryOrange.withOpacity(0.2) : AppColors.surfaceCard,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primaryOrange : AppColors.borderSubtle,
                                    width: isSelected ? 1.8 : 1,
                                  ),
                                  boxShadow: isSelected ? AppShadows.primaryGlow : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: isSelected ? AppColors.primaryOrange : Colors.white.withOpacity(0.08),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(Icons.layers_rounded, color: isSelected ? Colors.white : AppColors.primaryOrange, size: 16),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: isSelected ? AppColors.primaryOrange.withOpacity(0.3) : Colors.white.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'GLOBAL',
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : Colors.white60),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Tous les Événements',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Scanner tous les pass',
                                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10.5),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.check_circle_outline_rounded, size: 11, color: AppColors.successGreen),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_campaigns.length} actif(s)',
                                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          final c = _campaigns[index - 1];
                          final int? cIdInt = int.tryParse(c['id']?.toString() ?? '');
                          final isSelected = _selectedCampaignId != null && cIdInt != null && _selectedCampaignId == cIdInt;
                          final titre = c['titre'] ?? 'Événement';
                          final isJour = (c['mode_emargement'] ?? '') == 'journalier';
                          final dateStr = _formatDateRange(c['date_debut']?.toString(), c['date_fin']?.toString());

                          return GestureDetector(
                            onTap: () => _onSelectCampaign(c['id']),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 250,
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isJour ? AppColors.accentPurple.withOpacity(0.22) : AppColors.accentBlue.withOpacity(0.22))
                                    : AppColors.surfaceCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? (isJour ? AppColors.accentPurpleLight : AppColors.accentBlueLight)
                                      : AppColors.borderSubtle,
                                  width: isSelected ? 1.8 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: (isJour ? AppColors.accentPurple : AppColors.accentBlue).withOpacity(0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isJour ? AppColors.accentPurple.withOpacity(0.25) : AppColors.accentBlue.withOpacity(0.25),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isJour ? AppColors.accentPurpleLight.withOpacity(0.6) : AppColors.accentBlueLight.withOpacity(0.6),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isJour ? Icons.calendar_today_rounded : Icons.confirmation_number_outlined,
                                              size: 11,
                                              color: isJour ? AppColors.accentPurpleLight : AppColors.accentBlueLight,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isJour ? 'JOURNALIER' : 'PASS UNIQUE',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: isJour ? AppColors.accentPurpleLight : AppColors.accentBlueLight,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.successGreen,
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: const Text('ACTIF', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    titre,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      const Icon(Icons.event_outlined, color: AppColors.primaryOrange, size: 12),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          dateStr,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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

                    const SizedBox(height: 14),

                    // SECTION : CARTE STATISTIQUES UNIFIÉE (LIVE CONTROL HUB)
                    GlassContainer(
                      padding: const EdgeInsets.all(14),
                      borderRadius: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Entête de session
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryOrange.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.query_stats_rounded, size: 14, color: AppColors.primaryOrange),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'SESSION DE CONTRÔLE',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.white70, letterSpacing: 0.8),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.successGreen.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.successGreen.withOpacity(0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.successGreen,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${(progressPct * 100).toStringAsFixed(1)}%',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.successGreen),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Barre de progression
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progressPct,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.successGreen),
                              minHeight: 6,
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Grille 3 Compteurs KPI
                          Row(
                            children: [
                              _buildMetricItem(
                                icon: Icons.people_alt_outlined,
                                label: 'INSCRITS',
                                value: '$totalInscrits',
                                valueColor: Colors.white,
                              ),
                              _buildVerticalDivider(),
                              _buildMetricItem(
                                icon: Icons.check_circle_outline_rounded,
                                label: 'SCANNÉS',
                                value: '$totalScannes',
                                valueColor: AppColors.successGreen,
                              ),
                              _buildVerticalDivider(),
                              _buildMetricItem(
                                icon: Icons.hourglass_empty_rounded,
                                label: 'RESTANTS',
                                value: '$totalRestants',
                                valueColor: totalRestants > 0 ? AppColors.primaryOrange : Colors.white54,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // SECTION : STATION DE CONTRÔLE D'ACCÈS UNIFIÉE
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.qr_code_scanner_rounded, size: 14, color: AppColors.primaryOrange),
                            SizedBox(width: 6),
                            Text(
                              'CONTRÔLE & VALIDATION',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white60, letterSpacing: 0.8),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryOrange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primaryOrange.withOpacity(0.3)),
                          ),
                          child: const Text(
                            'Caméra • Code • Nom • Tél',
                            style: TextStyle(color: AppColors.primaryOrangeLight, fontSize: 9.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Grande Carte Unifiée de Contrôle
                    GlassContainer(
                      padding: const EdgeInsets.all(14),
                      borderRadius: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Bouton Action Principal : Scanner par Caméra
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ScannerHudScreen(
                                      doorName: zone,
                                      agentId: _agent?['id'] ?? 1,
                                      activeCampaignId: _selectedCampaignId,
                                    ),
                                  ),
                                );
                                _loadLocalData();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryOrange,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 4,
                                shadowColor: AppColors.primaryOrange.withOpacity(0.4),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'SCANNER PAR CAMÉRA',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Séparateur fin "OU SAISIE DIRECTE"
                          Row(
                            children: [
                              Expanded(child: Container(height: 1, color: Colors.white12)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  'OU RECHERCHE MANUELLE DIRECTE',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.4), letterSpacing: 0.6),
                                ),
                              ),
                              Expanded(child: Container(height: 1, color: Colors.white12)),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // 2. Barre de Recherche et Validation Rapide
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.search_rounded, color: AppColors.accentBlueLight, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _manualSearchController,
                                    onChanged: _onManualSearchChanged,
                                    onSubmitted: (_) => _handleManualValidate(),
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      hintText: 'Code billet, nom, tél, email...',
                                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                                if (_manualSearchController.text.isNotEmpty)
                                  InkWell(
                                    onTap: () {
                                      _manualSearchController.clear();
                                      setState(() => _manualSearchResults = []);
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(Icons.close_rounded, size: 16, color: Colors.white.withOpacity(0.5)),
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                ElevatedButton(
                                  onPressed: _isSearching ? null : () => _handleManualValidate(),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accentBlue,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  child: _isSearching
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text(
                                              'VALIDER',
                                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),

                          // Suggestions dynamiques si saisie
                          if (_manualSearchResults.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _manualSearchResults.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (ctx, i) {
                                final a = _manualSearchResults[i];
                                final isScanned = a.statutCheckin == 'scanne';
                                return InkWell(
                                  onTap: () => _handleManualValidate(a.numeroBadge),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isScanned ? Icons.check_circle_rounded : Icons.person_rounded,
                                          color: isScanned ? AppColors.successGreen : AppColors.primaryOrange,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${a.nomComplet} (${a.typePass.toUpperCase()})',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          a.numeroBadge,
                                          style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.white54, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white38),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // 3. BARRE D'ÉTAT TERMINAL ANCRÉE EN BAS (Élimine le vide et équilibre l'interface)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: ConnectivityService.instance.isOnlineNotifier,
                    builder: (ctx, isOnline, _) {
                      return Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isOnline ? AppColors.successGreen : AppColors.warningAmber,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOnline ? 'En ligne • Synchronisation auto' : 'Mode Local Hors-ligne',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOnline ? Colors.white70 : AppColors.warningAmber,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Row(
                    children: [
                      Icon(Icons.meeting_room_outlined, size: 13, color: Colors.white.withOpacity(0.4)),
                      const SizedBox(width: 4),
                      Text(
                        zone,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: Colors.white54),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white54, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white10,
    );
  }
}
