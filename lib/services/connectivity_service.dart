import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._internal();
  ConnectivityService._internal() {
    _init();
  }

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isAutoSyncingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> syncTickNotifier = ValueNotifier<int>(0);
  Timer? _timer;
  bool _isChecking = false;

  void _init() {
    checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => checkConnection());
  }

  // Vérification de connexion réelle par HTTP Ping
  Future<bool> checkConnection() async {
    if (_isChecking) return isOnlineNotifier.value;
    _isChecking = true;

    bool currentlyOnline = false;

    try {
      final pingUrl = Uri.parse('${ApiService.baseUrl}/ping.php');
      final res = await http.get(pingUrl).timeout(const Duration(seconds: 3));
      currentlyOnline = (res.statusCode == 200);
    } catch (_) {
      try {
        final googleUrl = Uri.parse('https://www.google.com');
        final res = await http.get(googleUrl).timeout(const Duration(seconds: 2));
        currentlyOnline = (res.statusCode == 200);
      } catch (_) {
        currentlyOnline = false;
      }
    }

    _isChecking = false;

    if (isOnlineNotifier.value != currentlyOnline) {
      isOnlineNotifier.value = currentlyOnline;
    }

    // SI EN LIGNE -> EXÉCUTER L'AUTO-SYNCHRONISATION
    if (currentlyOnline) {
      triggerAutoSync();
    }

    return currentlyOnline;
  }

  // Moteur d'Auto-Synchronisation Temps Réel (Push & Pull Continu)
  Future<void> triggerAutoSync() async {
    if (isAutoSyncingNotifier.value) return;

    try {
      isAutoSyncingNotifier.value = true;
      final res = await ApiService.forceFullSync();
      if (res['success'] == true) {
        syncTickNotifier.value++;
      }
    } catch (_) {
    } finally {
      isAutoSyncingNotifier.value = false;
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}

class ConnectivityVoyant extends StatelessWidget {
  final bool mini;
  const ConnectivityVoyant({super.key, this.mini = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnlineNotifier,
      builder: (context, isOnline, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.instance.isAutoSyncingNotifier,
          builder: (context, isSyncing, _) {
            final color = isOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
            final text = isSyncing
                ? 'SYNCHRO...'
                : (isOnline ? 'EN LIGNE' : 'HORS-LIGNE');
            final subtext = isSyncing
                ? 'Envoi au Cloud...'
                : (isOnline ? 'Auto-Sync Actif' : 'Mode Local');

            if (mini) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSyncing)
                      const SizedBox(
                        width: 9,
                        height: 9,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.greenAccent),
                      )
                    else
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                      ),
                    const SizedBox(width: 5),
                    Text(
                      text,
                      style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ],
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSyncing)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.greenAccent),
                    )
                  else
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(color: color.withOpacity(0.6), blurRadius: 6, spreadRadius: 1),
                        ],
                      ),
                    ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text,
                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                      Text(
                        subtext,
                        style: TextStyle(color: color.withOpacity(0.8), fontSize: 8.5, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
