import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/event_selection_service.dart';
import '../database/db_helper.dart';
import '../widgets/glass_container.dart';
import '../widgets/app_drawer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  List<Map<String, dynamic>> _localCampaigns = [];
  bool _isLoadingCampaigns = true;
  bool _isTestingConnection = false;
  Map<String, dynamic>? _testResult;

  @override
  void initState() {
    super.initState();
    _urlController.text = ApiService.baseUrl;
    _loadCampaigns();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _loadCampaigns() async {
    setState(() => _isLoadingCampaigns = true);
    final list = await LocalDatabase.instance.getCampaignsWithStats();
    if (mounted) {
      setState(() {
        _localCampaigns = list;
        _isLoadingCampaigns = false;
      });
    }
  }

  void _saveUrl() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isNotEmpty) {
      final cleanUrl = ApiService.sanitizeUrl(rawUrl);
      _urlController.text = cleanUrl;
      await ApiService.saveBaseUrl(cleanUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('URL enregistrée : $cleanUrl')),
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

  void _testConnection() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) return;

    setState(() {
      _isTestingConnection = true;
      _testResult = null;
    });

    final res = await ApiService.testConnection(rawUrl);
    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _testResult = res;
        if (res['url'] != null) {
          _urlController.text = res['url'];
        }
      });
    }
  }

  void _restoreDefaultUrl() {
    setState(() {
      _urlController.text = ApiService.defaultBaseUrl;
      _testResult = null;
    });
  }

  void _confirmDeleteCampaign(Map<String, dynamic> campaign) {
    final cId = campaign['id'] as int;
    final titre = campaign['titre'] ?? 'Événement';
    final totalAttendees = campaign['attendees_count'] ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.dangerRed, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Supprimer la campagne',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Voulez-vous supprimer définitivement la campagne « $titre » ?\n\n'
          '⚠️ Cette action supprimera les $totalAttendees participant(s) et les émargements locaux associés de la mémoire de ce téléphone.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalDatabase.instance.deleteCampaignAndData(cId);
              if (EventSelectionService.instance.selectedCampaignId == cId) {
                await EventSelectionService.instance.setSelectedCampaign(campaignId: null);
              }
              _loadCampaigns();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Campagne « $titre » et ses données supprimées.'),
                    backgroundColor: AppColors.dangerRed,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCampaignId = EventSelectionService.instance.selectedCampaignId;

    return Scaffold(
      drawer: const AppDrawer(currentRoute: 'settings'),
      appBar: AppBar(
        title: Text(
          'Paramètres & Données',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. SECTION GESTION DES CAMPAGNES LOCALES
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'GESTION DES CAMPAGNES LOCALES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white60,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  '${_localCampaigns.length} événement(s)',
                  style: const TextStyle(
                    color: AppColors.primaryOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_isLoadingCampaigns)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.primaryOrange),
                ),
              )
            else if (_localCampaigns.isEmpty)
              GlassContainer(
                padding: const EdgeInsets.all(16),
                borderRadius: 16,
                child: const Center(
                  child: Text(
                    'Aucune campagne enregistrée dans la mémoire locale.',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _localCampaigns.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, idx) {
                  final c = _localCampaigns[idx];
                  final cId = c['id'] as int;
                  final isSelected = selectedCampaignId == cId;
                  final cStatut = (c['statut'] ?? 'en_cours').toString().toLowerCase();
                  final isEnded = cStatut == 'terminee' || cStatut == 'cloturee';

                  return GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    borderRadius: 16,
                    borderColor: isSelected ? AppColors.primaryOrange.withOpacity(0.5) : Colors.white10,
                    borderWidth: isSelected ? 1.5 : 1.0,
                    child: Row(
                      children: [
                        // Icône d'événement
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isEnded
                                ? AppColors.dangerRed.withOpacity(0.15)
                                : AppColors.primaryOrange.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              isEnded ? Icons.lock_clock_rounded : Icons.event_available_rounded,
                              color: isEnded ? AppColors.dangerRedLight : AppColors.primaryOrange,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Titre & Sous-titre responsive (sans aucun overflow)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c['titre'] ?? 'Événement',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryOrange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppColors.primaryOrange.withOpacity(0.4),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: AppColors.primaryOrange,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  // Badge Statut
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isEnded
                                          ? AppColors.dangerRed.withOpacity(0.18)
                                          : AppColors.successGreen.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      isEnded ? 'TERMINÉE' : 'EN COURS',
                                      style: TextStyle(
                                        color: isEnded ? AppColors.dangerRedLight : AppColors.successGreen,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Chiffres clés (Inscrits / Scannés) avec TextOverflow anti-débordement
                                  Expanded(
                                    child: Text(
                                      '${c['attendees_count']} inscrit(s) • ${c['scanned_count']} scanné(s)',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
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

                        const SizedBox(width: 8),

                        // Bouton Supprimer compact & sécurisé
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _confirmDeleteCampaign(c),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.dangerRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.dangerRed.withOpacity(0.2),
                                  width: 0.8,
                                ),
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.dangerRedLight,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 24),

            // 2. CONFIGURATION SERVEUR
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SERVEUR & SYNCHRONISATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white60,
                    letterSpacing: 0.8,
                  ),
                ),
                GestureDetector(
                  onTap: _restoreDefaultUrl,
                  child: const Text(
                    'Par défaut',
                    style: TextStyle(
                      color: AppColors.primaryOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            GlassContainer(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'URL de l\'API Serveur',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surfaceCardLight,
                      prefixIcon: const Icon(Icons.link_rounded, color: AppColors.primaryOrange, size: 20),
                      suffixIcon: _urlController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                              onPressed: () {
                                setState(() {
                                  _urlController.clear();
                                  _testResult = null;
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      hintText: 'https://votre-serveur.com/api',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    ),
                  ),

                  // Résultat du Test de connexion en direct
                  if (_testResult != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _testResult!['success'] == true
                            ? AppColors.successGreen.withOpacity(0.15)
                            : AppColors.dangerRed.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _testResult!['success'] == true
                              ? AppColors.successGreen.withOpacity(0.4)
                              : AppColors.dangerRed.withOpacity(0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _testResult!['success'] == true
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            color: _testResult!['success'] == true
                                ? AppColors.successGreen
                                : AppColors.dangerRedLight,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testResult!['message'] ?? '',
                              style: TextStyle(
                                color: _testResult!['success'] == true
                                    ? AppColors.successGreen
                                    : AppColors.dangerRedLight,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Ligne des boutons d'actions : Tester & Enregistrer
                  Row(
                    children: [
                      // Bouton TESTER
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isTestingConnection ? null : _testConnection,
                          icon: _isTestingConnection
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                )
                              : const Icon(Icons.wifi_tethering_rounded, size: 16, color: Colors.white70),
                          label: Text(
                            _isTestingConnection ? 'Test...' : 'Tester',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Bouton ENREGISTRER
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _saveUrl,
                          icon: const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                          label: const Text(
                            'Enregistrer l\'URL',
                            style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryOrange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 3. INFORMATIONS SYSTÈME
            const Text(
              'INFORMATIONS DE L\'APPLICATION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white60,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            GlassContainer(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              child: Column(
                children: [
                  _buildInfoRow(Icons.layers_rounded, 'Version APK', 'v2.5 Pro (Multi-Events)'),
                  const Divider(color: Colors.white12, height: 16),
                  _buildInfoRow(Icons.storage_rounded, 'Moteur Local', 'SQLite Offline Engine v7'),
                  const Divider(color: Colors.white12, height: 16),
                  _buildInfoRow(Icons.verified_user_rounded, 'Plateforme', 'Makera Pass Enterprise'),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}
