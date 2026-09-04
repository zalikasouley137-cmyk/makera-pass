import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/api_service.dart';
import '../widgets/glass_container.dart';

class SyncHistoryScreen extends StatefulWidget {
  final int agentId;
  const SyncHistoryScreen({super.key, required this.agentId});

  @override
  State<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends State<SyncHistoryScreen> {
  List<Map<String, dynamic>> _pendingActions = [];
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  void _loadPending() async {
    final list = await LocalDatabase.instance.getPendingActions();
    if (mounted) {
      setState(() => _pendingActions = list);
    }
  }

  void _triggerSync() async {
    setState(() => _isSyncing = true);
    final res = await ApiService.syncPendingScans(widget.agentId);
    setState(() => _isSyncing = false);

    if (res['success'] == true) {
      _loadPending();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(res['message'] ?? 'Synchronisation réussie !')),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Échec de synchronisation'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _pendingActions.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF070B14),
        elevation: 0,
        title: const Text('Journal & Synchronisation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sync Status Hero Card
            GlassContainer(
              padding: const EdgeInsets.all(20),
              borderRadius: 20,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ACTIONS EN ATTENTE DE SERVEUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.8)),
                          const SizedBox(height: 6),
                          Text(
                            '$pendingCount modification${pendingCount > 1 ? 's' : ''}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFF28123)),
                          ),
                        ],
                      ),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pendingCount > 0 ? const Color(0xFFF28123).withOpacity(0.18) : Colors.greenAccent.withOpacity(0.18),
                          border: Border.all(color: pendingCount > 0 ? const Color(0xFFF28123) : Colors.greenAccent, width: 2),
                        ),
                        child: Icon(
                          pendingCount > 0 ? Icons.cloud_upload_outlined : Icons.cloud_done_rounded,
                          color: pendingCount > 0 ? const Color(0xFFF28123) : Colors.greenAccent,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: (_isSyncing || pendingCount == 0) ? null : _triggerSync,
                      icon: _isSyncing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.sync_rounded, color: Colors.white, size: 20),
                      label: Text(
                        _isSyncing ? 'Synchronisation en cours...' : (pendingCount > 0 ? 'Synchroniser ($pendingCount) Maintenant' : 'Toutes les actions synchronisées'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'TRAÇABILITÉ DES MODIFICATIONS (ANTI-CONFLIT)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white54, letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: _pendingActions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_done_rounded, color: Colors.greenAccent.withOpacity(0.7), size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Toutes les modifications sont synchronisées avec le serveur central.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: _pendingActions.length,
                      itemBuilder: (context, index) {
                        final item = _pendingActions[index];
                        final code = item['numero_badge'] ?? '';
                        final time = item['timestamp'] ?? '';
                        final actionType = item['action_type'] ?? 'scan';
                        final reason = item['reason'];

                        Color tagColor = Colors.green;
                        String tagText = 'SCAN';
                        IconData tagIcon = Icons.qr_code_2_rounded;

                        if (actionType == 'ban') {
                          tagColor = Colors.redAccent;
                          tagText = 'BANNISSEMENT';
                          tagIcon = Icons.gavel_rounded;
                        } else if (actionType == 'unban') {
                          tagColor = Colors.lightBlueAccent;
                          tagText = 'DÉBANNISSEMENT';
                          tagIcon = Icons.lock_open_rounded;
                        } else if (actionType == 'cancel_scan') {
                          tagColor = Colors.orangeAccent;
                          tagText = 'ANNULATION SCAN';
                          tagIcon = Icons.undo_rounded;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: GlassContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            borderRadius: 12,
                            child: Row(
                              children: [
                                Icon(tagIcon, color: tagColor, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.white, fontSize: 13)),
                                      Text(
                                        reason != null ? '$reason • $time' : time,
                                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: tagColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: tagColor.withOpacity(0.3)),
                                  ),
                                  child: Text(tagText, style: TextStyle(color: tagColor, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
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
}
