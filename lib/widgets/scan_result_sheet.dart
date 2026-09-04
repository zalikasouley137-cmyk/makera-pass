import 'package:flutter/material.dart';
import '../models/attendee_model.dart';
import '../utils/sound_haptic_helper.dart';
import '../database/db_helper.dart';
import '../services/connectivity_service.dart';
import 'glass_container.dart';

class ScanResultModal extends StatefulWidget {
  final ScanResultType resultType;
  final Attendee? attendee;
  final String rawBadgeCode;
  final bool wrongCampaign;
  final int agentId;
  final VoidCallback onNextScan;
  final VoidCallback? onStatusChanged;

  const ScanResultModal({
    super.key,
    required this.resultType,
    this.attendee,
    required this.rawBadgeCode,
    this.wrongCampaign = false,
    this.agentId = 1,
    required this.onNextScan,
    this.onStatusChanged,
  });

  @override
  State<ScanResultModal> createState() => _ScanResultModalState();
}

class _ScanResultModalState extends State<ScanResultModal> {
  late ScanResultType _currentType;

  @override
  void initState() {
    super.initState();
    _currentType = widget.resultType;
  }

  // Modale pour Bannir
  void _openBanDialog() {
    String selectedReason = 'Comportement Inapproprié';
    String selectedDuration = 'forever';
    final customReasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
          ),
          title: const Row(
            children: [
              Icon(Icons.gavel_rounded, color: Colors.redAccent, size: 22),
              SizedBox(width: 8),
              Text('Bannir ce participant', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Participant : ${widget.attendee?.nomComplet ?? widget.rawBadgeCode}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),

                const Text('MOTIF DU BANNISSEMENT', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white54, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Comportement Inapproprié', child: Text('Comportement Inapproprié')),
                    DropdownMenuItem(value: 'Fraude de Billet / Usurpation', child: Text('Fraude de Billet / Usurpation')),
                    DropdownMenuItem(value: 'Trouble à l\'Ordre Public', child: Text('Trouble à l\'Ordre Public')),
                    DropdownMenuItem(value: 'Refus d\'Obtempérer Sécurité', child: Text('Refus d\'Obtempérer Sécurité')),
                    DropdownMenuItem(value: 'Autre motif', child: Text('Autre motif personnalisé')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedReason = val);
                  },
                ),

                if (selectedReason == 'Autre motif') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customReasonController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Précisez la raison...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.3),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                const Text('DURÉE DU BANNISSEMENT', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white54, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedDuration,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'forever', child: Text('🔴 Pour Toujours (Définitif)')),
                    DropdownMenuItem(value: '1h', child: Text('⏱️ 1 Heure (Temporaire)')),
                    DropdownMenuItem(value: '24h', child: Text('📅 24 Heures (Pour la journée)')),
                    DropdownMenuItem(value: 'event', child: Text('🎯 Jusqu\'à la fin de l\'événement')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedDuration = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                final finalReason = selectedReason == 'Autre motif' && customReasonController.text.trim().isNotEmpty
                    ? customReasonController.text.trim()
                    : selectedReason;

                String? expiresAt;
                final now = DateTime.now();
                if (selectedDuration == '1h') {
                  expiresAt = now.add(const Duration(hours: 1)).toString().substring(0, 19);
                } else if (selectedDuration == '24h') {
                  expiresAt = now.add(const Duration(hours: 24)).toString().substring(0, 19);
                } else if (selectedDuration == 'event') {
                  expiresAt = now.add(const Duration(days: 3)).toString().substring(0, 19);
                }

                Navigator.pop(ctx);

                final badge = widget.attendee?.numeroBadge ?? widget.rawBadgeCode;
                await LocalDatabase.instance.banAttendee(
                  badgeCode: badge,
                  reason: finalReason,
                  expiresAt: expiresAt,
                  agentId: widget.agentId,
                );

                if (mounted) {
                  setState(() {
                    _currentType = ScanResultType.banned;
                    if (widget.attendee != null) {
                      widget.attendee!.isBanned = 1;
                      widget.attendee!.banReason = finalReason;
                      widget.attendee!.banExpiresAt = expiresAt;
                    }
                  });
                  SoundHapticHelper.triggerBanned();
                  ConnectivityService.instance.triggerAutoSync();
                }

                if (widget.onStatusChanged != null) widget.onStatusChanged!();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Confirmer le Bannissement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Débannir / Changer le statut vers Valide
  void _openUnbanDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.greenAccent.withOpacity(0.4)),
        ),
        title: const Row(
          children: [
            Icon(Icons.lock_open_rounded, color: Colors.greenAccent, size: 22),
            SizedBox(width: 8),
            Text('Lever le Bannissement', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Voulez-vous réhabiliter le participant ${widget.attendee?.nomComplet ?? widget.rawBadgeCode} ? Il pourra à nouveau accéder à l\'événement.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final badge = widget.attendee?.numeroBadge ?? widget.rawBadgeCode;

              await LocalDatabase.instance.unbanAttendee(
                badgeCode: badge,
                agentId: widget.agentId,
                reason: 'Levée manuelle par agent ${widget.agentId}',
              );

              if (mounted) {
                setState(() {
                  _currentType = ScanResultType.valid;
                  if (widget.attendee != null) {
                    widget.attendee!.isBanned = 0;
                    widget.attendee!.statutCheckin = 'non_scanne';
                    widget.attendee!.banReason = null;
                    widget.attendee!.banExpiresAt = null;
                  }
                });
                SoundHapticHelper.triggerSuccess();
                ConnectivityService.instance.triggerAutoSync();
              }

              if (widget.onStatusChanged != null) widget.onStatusChanged!();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            child: const Text('Débannir & Réactiver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color accentColor;
    IconData iconData;
    String statusTitle;
    String statusSubtitle;

    switch (_currentType) {
      case ScanResultType.valid:
        accentColor = const Color(0xFF10B981); // Vert
        iconData = Icons.check_circle_rounded;
        statusTitle = 'PRÉSENCE DU JOUR VALIDÉE';
        statusSubtitle = 'Émargement enregistré à ${DateTime.now().toString().substring(11, 16)}';
        break;
      case ScanResultType.alreadyUsed:
        accentColor = const Color(0xFFF59E0B); // Orange
        iconData = Icons.schedule_rounded;
        statusTitle = 'DÉJÀ POINTÉ AUJOURD\'HUI';
        statusSubtitle = 'Arrivée enregistrée à : ${widget.attendee?.scannedAt != null && widget.attendee!.scannedAt!.length >= 16 ? widget.attendee!.scannedAt!.substring(11, 16) : 'Aujourd\'hui'}';
        break;
      case ScanResultType.banned:
        accentColor = const Color(0xFFEF4444); // Rouge
        iconData = Icons.block_rounded;
        statusTitle = 'PARTICIPANT BANNI';
        final reason = widget.attendee?.banReason ?? 'Banni par la sécurité';
        final exp = widget.attendee?.banExpiresAt != null ? 'Échéance: ${widget.attendee!.banExpiresAt}' : 'Bannissement Définitif';
        statusSubtitle = 'Motif : $reason\n($exp)';
        break;
      case ScanResultType.invalid:
        accentColor = const Color(0xFFEF4444); // Rouge
        iconData = Icons.cancel_rounded;
        statusTitle = 'BADGE INCONNU';
        statusSubtitle = 'Ce QR Code n\'appartient à aucun événement assigné.';
        break;
    }

    final campTitre = widget.attendee?.campaignTitre.isNotEmpty == true 
        ? widget.attendee!.campaignTitre 
        : 'Événement Assigné';

    final photoUrl = widget.attendee?.resolvedPhotoUrl;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: accentColor.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.35),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Badge Événement Associé
          if (widget.attendee != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF28123).withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF28123).withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_available_rounded, color: Color(0xFFF28123), size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      campTitre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Status Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withOpacity(0.15),
              border: Border.all(color: accentColor, width: 2.5),
            ),
            child: Icon(iconData, color: accentColor, size: 38),
          ),

          const SizedBox(height: 10),

          Text(
            statusTitle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            statusSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),

          const SizedBox(height: 16),

          // Attendee Identity Card WITH PHOTO DISPLAY
          if (widget.attendee != null)
            GlassContainer(
              padding: const EdgeInsets.all(14),
              borderRadius: 16,
              borderColor: accentColor.withOpacity(0.25),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withOpacity(0.2),
                      border: Border.all(color: accentColor, width: 2),
                      boxShadow: [
                        BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 8),
                      ],
                    ),
                    child: ClipOval(
                      child: photoUrl != null
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  widget.attendee!.nomComplet.isNotEmpty
                                      ? widget.attendee!.nomComplet.substring(0, 1).toUpperCase()
                                      : 'P',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: accentColor),
                                ),
                              ),
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                widget.attendee!.nomComplet.isNotEmpty
                                    ? widget.attendee!.nomComplet.substring(0, 1).toUpperCase()
                                    : 'P',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: accentColor),
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.attendee!.nomComplet,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (widget.attendee!.organisation.isNotEmpty)
                          Text(
                            widget.attendee!.organisation,
                            style: const TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.attendee!.typePass.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.attendee!.numeroBadge,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            GlassContainer(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Code : ${widget.rawBadgeCode}',
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white70),
              ),
            ),

          const SizedBox(height: 14),

          // ACTIONS DE CHANGEMENT DE STATUT (BANNIR / DÉBANNIR)
          if (widget.attendee != null) ...[
            if (_currentType == ScanResultType.banned)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _openUnbanDialog,
                    icon: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'LEVER LE BANNISSEMENT (DÉBANNIR)',
                      style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openBanDialog,
                    icon: const Icon(Icons.gavel_rounded, color: Colors.redAccent, size: 16),
                    label: const Text(
                      'BANNIR CE PARTICIPANT',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
          ],

          // Pointer l'Heure de Départ (Mode Journalier)
          if (_currentType == ScanResultType.alreadyUsed && widget.attendee != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await LocalDatabase.instance.recordDailyDeparture(
                      badgeCode: widget.attendee!.numeroBadge,
                      agentId: widget.agentId,
                    );
                    ConnectivityService.instance.triggerAutoSync();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Heure de départ pointée avec succès.'), backgroundColor: Colors.blue),
                    );
                    widget.onNextScan();
                  },
                  icon: const Icon(Icons.exit_to_app_rounded, color: Colors.lightBlueAccent, size: 18),
                  label: const Text('POINTER L\'HEURE DE DÉPART', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.lightBlueAccent.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),

          // Next Scan Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: widget.onNextScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 6,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.black87),
                  SizedBox(width: 8),
                  Text(
                    'SCANNER LE SUIVANT',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
