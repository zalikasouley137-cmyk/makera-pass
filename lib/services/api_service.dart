import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/attendee_model.dart';
import '../database/db_helper.dart';

class ApiService {

  // 3. Forcer la synchronisation complète (Envoi des actions + Récupération de l'état complet du serveur)
  static Future<Map<String, dynamic>> forceFullSync() async {
    final db = LocalDatabase.instance;
    final agentRows = await (await db.database).query('agent_session', limit: 1);
    if (agentRows.isEmpty) {
      return {'success': false, 'message': 'Aucune session agent active.'};
    }

    final agent = agentRows.first;
    final agentId = agent['id'] as int? ?? 1;
    final codeAgent = agent['code_agent'] as String? ?? 'AGT-2026';

    // 1. Envoyer les actions locales
    try {
      await syncPendingScans(agentId);
    } catch (_) {}

    // 2. Re-télécharger l'annuaire complet des participants depuis l'API
    final url = Uri.parse('$baseUrl/agent_auth.php');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code_agent': codeAgent.trim().toUpperCase(),
          'pin_code': '1234',
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          List<Attendee> attendeeList = [];
          if (data['attendees'] != null) {
            for (var item in data['attendees']) {
              attendeeList.add(Attendee.fromJson(item));
            }
          }

          // Mise à jour de SQLite
          await db.cacheAttendees(attendeeList);

          final bannedCount = attendeeList.where((a) => a.isBanned == 1).length;
          final scannedCount = attendeeList.where((a) => a.statutCheckin == 'scanne').length;

          return {
            'success': true,
            'total_attendees': attendeeList.length,
            'banned_count': bannedCount,
            'scanned_count': scannedCount,
            'message': '${attendeeList.length} participants reçus ($bannedCount banni${bannedCount > 1 ? 's' : ''}, $scannedCount scanné${scannedCount > 1 ? 's' : ''}).',
          };
        }
      }
      return {'success': false, 'message': 'Réponse inattendue du serveur.'};
    } catch (e) {
      return {'success': false, 'message': 'Erreur réseau : $e'};
    }
  }

  static const String defaultBaseUrl = 'https://gayya-niger.ne/makera_event/api';
  static String baseUrl = defaultBaseUrl;

  static String sanitizeUrl(String rawUrl) {
    String clean = rawUrl.trim();
    if (clean.isEmpty) return defaultBaseUrl;
    // Fix typos like tps:// or http:/
    if (clean.startsWith('tps://')) {
      clean = 'https://${clean.substring(6)}';
    } else if (clean.startsWith('tp://')) {
      clean = 'http://${clean.substring(5)}';
    } else if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  static Future<void> initBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('server_base_url');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        baseUrl = sanitizeUrl(savedUrl);
      }
    } catch (_) {}
  }

  static Future<void> saveBaseUrl(String url) async {
    baseUrl = sanitizeUrl(url);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_base_url', baseUrl);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> testConnection(String urlToCheck) async {
    final cleanUrl = sanitizeUrl(urlToCheck);
    try {
      final uri = Uri.parse('$cleanUrl/agent_auth.php');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 500) {
        return {
          'success': true,
          'url': cleanUrl,
          'code': response.statusCode,
          'message': 'Serveur en ligne et opérationnel ! (Code ${response.statusCode})',
        };
      } else {
        return {
          'success': false,
          'url': cleanUrl,
          'code': response.statusCode,
          'message': 'Le serveur a répondu avec le statut HTTP ${response.statusCode}.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'url': cleanUrl,
        'message': 'Impossible d\'atteindre le serveur ($e). Vérifiez l\'URL et le réseau.',
      };
    }
  }

  // 1. Authentification & Téléchargement Initial
  static Future<Map<String, dynamic>> loginAndSync({
    required String codeAgent,
    required String pinCode,
    String? customBaseUrl,
  }) async {
    if (customBaseUrl != null && customBaseUrl.trim().isNotEmpty) {
      await saveBaseUrl(customBaseUrl.trim());
    }

    final activeUrl = baseUrl;
    final url = Uri.parse('$activeUrl/agent_auth.php');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code_agent': codeAgent.trim().toUpperCase(),
          'pin_code': pinCode.trim(),
        }),
      ).timeout(const Duration(seconds: 14));

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Le serveur a renvoyé une réponse vide (Code HTTP ${response.statusCode}).',
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final List campList = data['campaigns'] is List ? data['campaigns'] : [];
        if (campList.isEmpty) {
          return {
            'success': false,
            'message': '⚠️ Aucun événement assigné :\n\nVous n\'avez actuellement aucun événement assigné à votre compte agent. Veuillez contacter l\'administrateur.',
          };
        }

        final db = LocalDatabase.instance;
        await db.clearAll();

        final agentMap = data['agent'];
        final dbRaw = await db.database;
        await dbRaw.delete('agent_session');
        await dbRaw.insert('agent_session', {
          'id': agentMap['id'],
          'code_agent': agentMap['code_agent'],
          'pin_code': pinCode.trim(),
          'nom_complet': agentMap['nom_complet'],
          'telephone': agentMap['telephone'],
          'email': agentMap['email'],
          'photo_url': agentMap['photo_url'],
          'role_agent': agentMap['role_agent'],
          'zone_affectation': agentMap['zone_affectation'],
          'total_scans': agentMap['total_scans'] ?? 0,
          'is_logged_in': 1,
        });

        if (data['campaigns'] != null && data['campaigns'] is List) {
          for (var c in data['campaigns']) {
            await dbRaw.insert('campaign_info', {
              'id': c['id'],
              'titre': c['titre'] ?? '',
              'categorie': c['categorie'] ?? '',
              'lieu': (c['lieu_nom'] ?? '') + ' ' + (c['lieu_ville'] ?? ''),
              'date_debut': c['date_debut'] ?? '',
              'date_fin': c['date_fin'] ?? '',
              'type_acces': c['type_acces'] ?? '',
              'statut': c['statut'] ?? '',
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        List<Attendee> attendeeList = [];
        if (data['attendees'] != null) {
          for (var item in data['attendees']) {
            attendeeList.add(Attendee.fromJson(item));
          }
        }
        await db.cacheAttendees(attendeeList);

        return {
          'success': true,
          'message': data['message'],
          'agent': agentMap,
          'total_campaigns': data['total_campaigns'] ?? 1,
          'total_attendees': data['total_attendees'] ?? attendeeList.length,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Erreur de connexion (Code HTTP ${response.statusCode})',
        };
      }
    } catch (e) {
      // --- MODE HORS-LIGNE AUTOMATIQUE (OFFLINE FALLBACK) ---
      // Si pas d'Internet mais que l'agent a déjà des données dans SQLite
      try {
        final db = LocalDatabase.instance;
        final dbRaw = await db.database;
        final localAgentRows = await dbRaw.query(
          'agent_session',
          where: 'UPPER(code_agent) = ?',
          whereArgs: [codeAgent.trim().toUpperCase()],
          limit: 1,
        );

        if (localAgentRows.isNotEmpty) {
          final localCampaigns = await dbRaw.query('campaign_info');
          if (localCampaigns.isEmpty) {
            return {
              'success': false,
              'message': '⚠️ Aucun événement en mémoire locale :\n\nAucun événement n\'est enregistré sur ce téléphone. Une première connexion avec Internet est obligatoire.',
            };
          }
          final agent = localAgentRows.first;
          final storedPin = agent['pin_code']?.toString();
          if (storedPin != null && storedPin.isNotEmpty && storedPin != pinCode.trim()) {
            return {
              'success': false,
              'message': 'Code PIN incorrect pour l\'agent ${agent['nom_complet']}.',
            };
          }

          await dbRaw.update('agent_session', {'is_logged_in': 1});

          final localAttendees = await dbRaw.query('local_attendees');

          return {
            'success': true,
            'offline_mode': true,
            'message': '⚡ Connexion Hors-Ligne réussie !\n\n'
                '${localAttendees.length} participant(s) chargé(s) depuis la mémoire locale du téléphone.',
            'agent': agent,
            'total_campaigns': localCampaigns.length,
            'total_attendees': localAttendees.length,
          };
        }
      } catch (_) {}

      return {
        'success': false,
        'message': 'Impossible de joindre le serveur à l\'adresse : $activeUrl.\n\n'
            'ℹ️ Lors de la toute première installation, une connexion Internet (Wi-Fi ou 4G) est obligatoire une seule fois pour télécharger la base de données.',
      };
    }
  }

  // 2. Synchronisation des Actions (Scans, Bannissements, Débannissements, Annulations)
  static Future<Map<String, dynamic>> syncPendingScans(int agentId) async {
    final db = LocalDatabase.instance;
    final pendingActions = await db.getPendingActions();

    final url = Uri.parse('$baseUrl/sync_scans.php');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'agent_id': agentId,
          'actions': pendingActions,
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Réponse vide du serveur'};
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        List<int> actionIds = pendingActions.map((e) => e['id'] as int).toList();
        await db.clearSyncedActions(actionIds);

        // MISE À JOUR BIDIRECTIONNELLE : APPLIQUER LES DERNIERS ÉTATS DU SERVEUR
        if (data['attendees'] != null && data['attendees'] is List) {
          List<Attendee> serverList = [];
          for (var item in data['attendees']) {
            serverList.add(Attendee.fromJson(item));
          }
          await db.syncServerAttendeesRoster(serverList);
        }

        return {
          'success': true,
          'synced_count': data['synced_count'] ?? pendingActions.length,
          'banned_count': data['banned_count'] ?? 0,
          'unbanned_count': data['unbanned_count'] ?? 0,
          'conflict_count': data['conflict_count'] ?? 0,
          'total_attendees': data['total_attendees'] ?? 0,
          'message': data['message'] ?? 'Synchronisation bidirectionnelle réussie.',
        };
      } else {
        return {'success': false, 'message': data['message'] ?? 'Erreur serveur (Code ${response.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Échec de synchronisation (Pas de réseau) : $e'};
    }
  }
}
