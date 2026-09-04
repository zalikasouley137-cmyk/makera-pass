import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/attendee_model.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('makera_agent_offline_v7.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. Table Session Agent
    await db.execute('''
      CREATE TABLE agent_session (
        id INTEGER PRIMARY KEY,
        code_agent TEXT NOT NULL,
        pin_code TEXT,
        nom_complet TEXT NOT NULL,
        telephone TEXT,
        email TEXT,
        photo_url TEXT,
        role_agent TEXT,
        zone_affectation TEXT,
        total_scans INTEGER DEFAULT 0,
        is_logged_in INTEGER DEFAULT 1
      )
    ''');

    // 2. Table Campagnes Multiples
    await db.execute('''
      CREATE TABLE campaign_info (
        id INTEGER PRIMARY KEY,
        titre TEXT NOT NULL,
        categorie TEXT,
        lieu TEXT,
        date_debut TEXT,
        date_fin TEXT,
        type_acces TEXT,
        statut TEXT,
        mode_emargement TEXT DEFAULT 'unique',
        heure_debut_journee TEXT DEFAULT '08:00:00',
        heure_fin_journee TEXT DEFAULT '18:00:00'
      )
    ''');

    // 6. Table Présences Journalières (Multi-Jours / Formation / Workshop)
    await db.execute('''
      CREATE TABLE local_daily_attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        campaign_id INTEGER NOT NULL,
        numero_badge TEXT NOT NULL,
        date_presence TEXT NOT NULL,
        scanned_at TEXT NOT NULL,
        heure_arrivee TEXT,
        heure_depart TEXT,
        door TEXT,
        agent_id INTEGER NOT NULL,
        is_synced INTEGER DEFAULT 0,
        UNIQUE(numero_badge, date_presence)
      )
    ''');

    // 3. Table Participants
    await db.execute('''
      CREATE TABLE local_attendees (
        id INTEGER PRIMARY KEY,
        campaign_id INTEGER NOT NULL,
        commande_ref TEXT,
        numero_badge TEXT UNIQUE NOT NULL,
        nom_complet TEXT NOT NULL,
        email TEXT,
        telephone TEXT,
        organisation TEXT,
        fonction TEXT,
        type_pass TEXT,
        photo_badge TEXT,
        campaign_titre TEXT,
        statut_checkin TEXT DEFAULT 'non_scanne',
        scanned_at TEXT,
        scanned_door TEXT,
        is_synced INTEGER DEFAULT 1,
        is_banned INTEGER DEFAULT 0,
        ban_reason TEXT,
        ban_expires_at TEXT,
        banned_at TEXT,
        last_modified_at TEXT
      )
    ''');

    // 4. Table File d'Actions Unifiée (Traçabilité & Sync)
    await db.execute('''
      CREATE TABLE action_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action_type TEXT NOT NULL,
        numero_badge TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        door TEXT,
        reason TEXT,
        expires_at TEXT,
        agent_id INTEGER NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // 5. Table Journal d'Audit & Historique des Actions de l'Agent (Complet)
    await db.execute('''
      CREATE TABLE agent_audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL, -- 'LOGIN', 'LOGOUT', 'SCAN_VALID', 'SCAN_DUPLICATE', 'SCAN_INVALID', 'BAN', 'UNBAN', 'CANCEL_SCAN', 'SYNC', 'SETTINGS'
        title TEXT NOT NULL,
        badge_code TEXT,
        participant_name TEXT,
        campaign_title TEXT,
        details TEXT,
        timestamp TEXT NOT NULL,
        agent_id INTEGER NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');
  }

  // --- GESTION DU JOURNAL D'AUDIT ---
  Future<void> logAudit({
    required String eventType,
    required String title,
    String? badgeCode,
    String? participantName,
    String? campaignTitle,
    String? details,
    int agentId = 1,
  }) async {
    final db = await instance.database;
    final nowIso = DateTime.now().toString().substring(0, 19);

    await db.insert('agent_audit_logs', {
      'event_type': eventType,
      'title': title,
      'badge_code': badgeCode,
      'participant_name': participantName,
      'campaign_title': campaignTitle,
      'details': details,
      'timestamp': nowIso,
      'agent_id': agentId,
      'is_synced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({String? filterType, String? query}) async {
    final db = await instance.database;
    String where = '1=1';
    List<dynamic> args = [];

    if (filterType != null && filterType.isNotEmpty && filterType != 'ALL') {
      where += ' AND event_type = ?';
      args.add(filterType);
    }

    if (query != null && query.isNotEmpty) {
      where += ' AND (title LIKE ? OR badge_code LIKE ? OR participant_name LIKE ? OR details LIKE ?)';
      final q = '%$query%';
      args.addAll([q, q, q, q]);
    }

    return await db.query('agent_audit_logs', where: where, whereArgs: args, orderBy: 'id DESC', limit: 200);
  }

  Future<void> clearAuditLogs() async {
    final db = await instance.database;
    await db.delete('agent_audit_logs');
  }

  // --- GESTION CAMPAGNES & PARTICIPANTS ---
  Future<List<Map<String, dynamic>>> getAllCampaigns() async {
    final db = await instance.database;
    return await db.query('campaign_info', orderBy: 'id DESC');
  }

  Future<void> cacheAttendees(List<Attendee> attendees) async {
    final db = await instance.database;
    final batch = db.batch();

    for (var a in attendees) {
      batch.insert(
        'local_attendees',
        a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // Validation d'un QR code / Badge
  Future<Map<String, dynamic>> validateBadge(
    String badgeCode,
    String door,
    int agentId, {
    int? activeCampaignId,
  }) async {
    final db = await instance.database;
    final cleanCode = badgeCode.trim().toUpperCase();

    final results = await db.query(
      'local_attendees',
      where: 'UPPER(numero_badge) = ? OR UPPER(commande_ref) = ?',
      whereArgs: [cleanCode, cleanCode],
      limit: 1,
    );

    if (results.isEmpty) {
      await logAudit(
        eventType: 'SCAN_INVALID',
        title: 'Badge Inconnu / Rejeté',
        badgeCode: cleanCode,
        details: 'QR Code non répertorié dans la base',
        agentId: agentId,
      );

      return {
        'status': 'invalid',
        'message': 'Billet introuvable dans vos événements assignés.',
        'attendee': null,
      };
    }

    final attendee = Attendee.fromMap(results.first);
    final nowIso = DateTime.now().toString().substring(0, 19);

    // 1. VÉRIFICATION DU BANNISSEMENT
    if (attendee.isBanned == 1) {
      bool isStillBanned = true;
      if (attendee.banExpiresAt != null && attendee.banExpiresAt!.isNotEmpty) {
        try {
          final expiry = DateTime.parse(attendee.banExpiresAt!);
          if (DateTime.now().isAfter(expiry)) {
            isStillBanned = false;
            await unbanAttendee(
              badgeCode: attendee.numeroBadge,
              agentId: agentId,
              reason: 'Échéance du bannissement atteinte (Automatique)',
            );
            attendee.isBanned = 0;
          }
        } catch (_) {}
      }

      if (isStillBanned) {
        await logAudit(
          eventType: 'SCAN_BANNED_BLOCK',
          title: 'Tentative d\'Accès Banni Bloquée',
          badgeCode: attendee.numeroBadge,
          participantName: attendee.nomComplet,
          campaignTitle: attendee.campaignTitre,
          details: 'Motif du ban : ${attendee.banReason ?? 'Sécurité'}',
          agentId: agentId,
        );

        return {
          'status': 'banned',
          'message': 'ACCÈS STRICTEMENT REFUSÉ : PARTICIPANT BANNI',
          'attendee': attendee,
        };
      }
    }

    bool isDifferentCampaign = (activeCampaignId != null && activeCampaignId > 0 && attendee.campaignId != activeCampaignId);

    if (attendee.statutCheckin == 'scanne') {
      await logAudit(
        eventType: 'SCAN_DUPLICATE',
        title: 'Billet Déjà Scanné (Double Entrée)',
        badgeCode: attendee.numeroBadge,
        participantName: attendee.nomComplet,
        campaignTitle: attendee.campaignTitre,
        details: 'Déjà scanné à ${attendee.scannedAt} (${attendee.scannedDoor})',
        agentId: agentId,
      );

      return {
        'status': 'already_scanned',
        'message': 'Billet déjà scanné !',
        'attendee': attendee,
        'wrongCampaign': isDifferentCampaign,
      };
    }

    // Mettre à jour localement comme SCANNÉ
    await db.update(
      'local_attendees',
      {
        'statut_checkin': 'scanne',
        'scanned_at': nowIso,
        'scanned_door': door,
        'is_synced': 0,
        'last_modified_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [attendee.id],
    );

    final todayDate = nowIso.substring(0, 10);
    final todayTime = nowIso.length >= 19 ? nowIso.substring(11, 19) : nowIso;
    await db.insert('local_daily_attendance', {
      'campaign_id': attendee.campaignId,
      'numero_badge': attendee.numeroBadge,
      'date_presence': todayDate,
      'scanned_at': nowIso,
      'door': door,
      'heure_arrivee': todayTime,
      'heure_depart': null,
      'agent_id': agentId,
      'is_synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Enregistrer dans la file unifiée
    await db.insert('action_sync_queue', {
      'action_type': 'scan',
      'numero_badge': attendee.numeroBadge,
      'timestamp': nowIso,
      'door': door,
      'reason': null,
      'expires_at': null,
      'agent_id': agentId,
    });

    await db.rawUpdate('UPDATE agent_session SET total_scans = total_scans + 1 WHERE id = ?', [agentId]);

    // Journal d'audit
    await logAudit(
      eventType: 'SCAN_VALID',
      title: 'Accès Validé (Check-in)',
      badgeCode: attendee.numeroBadge,
      participantName: attendee.nomComplet,
      campaignTitle: attendee.campaignTitre,
      details: 'Pass ${attendee.typePass} • Porte: $door',
      agentId: agentId,
    );

    attendee.statutCheckin = 'scanne';
    attendee.scannedAt = nowIso;
    attendee.scannedDoor = door;
    attendee.isSynced = 0;

    return {
      'status': 'valid',
      'message': 'Accès Validé avec Succès !',
      'attendee': attendee,
      'wrongCampaign': isDifferentCampaign,
    };
  }

  // BANNIR UN PARTICIPANT
  Future<bool> banAttendee({
    required String badgeCode,
    required String reason,
    String? expiresAt,
    required int agentId,
  }) async {
    final db = await instance.database;
    final cleanCode = badgeCode.trim().toUpperCase();
    final nowIso = DateTime.now().toString().substring(0, 19);

    final res = await db.update(
      'local_attendees',
      {
        'is_banned': 1,
        'statut_checkin': 'banni',
        'ban_reason': reason,
        'ban_expires_at': expiresAt,
        'banned_at': nowIso,
        'last_modified_at': nowIso,
        'is_synced': 0,
      },
      where: 'UPPER(numero_badge) = ? OR UPPER(commande_ref) = ?',
      whereArgs: [cleanCode, cleanCode],
    );

    if (res > 0) {
      await db.insert('action_sync_queue', {
        'action_type': 'ban',
        'numero_badge': cleanCode,
        'timestamp': nowIso,
        'door': null,
        'reason': reason,
        'expires_at': expiresAt,
        'agent_id': agentId,
      });

      await logAudit(
        eventType: 'BAN',
        title: 'Bannissement de Participant',
        badgeCode: cleanCode,
        details: 'Motif: $reason • Échéance: ${expiresAt ?? 'Définitif'}',
        agentId: agentId,
      );

      return true;
    }
    return false;
  }

  // DÉBANNIR UN PARTICIPANT
  Future<bool> unbanAttendee({
    required String badgeCode,
    required int agentId,
    String reason = 'Levée manuelle du bannissement',
  }) async {
    final db = await instance.database;
    final cleanCode = badgeCode.trim().toUpperCase();
    final nowIso = DateTime.now().toString().substring(0, 19);

    final res = await db.update(
      'local_attendees',
      {
        'is_banned': 0,
        'statut_checkin': 'non_scanne',
        'ban_reason': null,
        'ban_expires_at': null,
        'banned_at': null,
        'last_modified_at': nowIso,
        'is_synced': 0,
      },
      where: 'UPPER(numero_badge) = ? OR UPPER(commande_ref) = ?',
      whereArgs: [cleanCode, cleanCode],
    );

    if (res > 0) {
      await db.insert('action_sync_queue', {
        'action_type': 'unban',
        'numero_badge': cleanCode,
        'timestamp': nowIso,
        'door': null,
        'reason': reason,
        'expires_at': null,
        'agent_id': agentId,
      });

      await logAudit(
        eventType: 'UNBAN',
        title: 'Levée de Bannissement (Débannir)',
        badgeCode: cleanCode,
        details: reason,
        agentId: agentId,
      );

      return true;
    }
    return false;
  }

  // ANNULER UN SCAN
  Future<bool> cancelScan({
    required String badgeCode,
    required int agentId,
  }) async {
    final db = await instance.database;
    final cleanCode = badgeCode.trim().toUpperCase();
    final nowIso = DateTime.now().toString().substring(0, 19);

    final res = await db.update(
      'local_attendees',
      {
        'statut_checkin': 'non_scanne',
        'scanned_at': null,
        'scanned_door': null,
        'last_modified_at': nowIso,
        'is_synced': 0,
      },
      where: 'UPPER(numero_badge) = ? OR UPPER(commande_ref) = ?',
      whereArgs: [cleanCode, cleanCode],
    );

    if (res > 0) {
      await db.insert('action_sync_queue', {
        'action_type': 'cancel_scan',
        'numero_badge': cleanCode,
        'timestamp': nowIso,
        'door': null,
        'reason': 'Annulation manuelle',
        'expires_at': null,
        'agent_id': agentId,
      });

      await logAudit(
        eventType: 'CANCEL_SCAN',
        title: 'Annulation de Scan',
        badgeCode: cleanCode,
        details: 'Statut remis en attente',
        agentId: agentId,
      );

      return true;
    }
    return false;
  }

  Future<List<Attendee>> getAttendees({
    int? campaignId,
    String query = '',
    String statusFilter = 'all',
  }) async {
    final db = await instance.database;
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (campaignId != null && campaignId > 0) {
      whereClause += ' AND campaign_id = ?';
      whereArgs.add(campaignId);
    }

    if (statusFilter == 'banni') {
      whereClause += ' AND is_banned = 1';
    } else if (statusFilter != 'all') {
      whereClause += ' AND statut_checkin = ? AND is_banned = 0';
      whereArgs.add(statusFilter);
    }

    if (query.isNotEmpty) {
      whereClause += ' AND (nom_complet LIKE ? OR numero_badge LIKE ? OR telephone LIKE ? OR organisation LIKE ?)';
      final q = '%$query%';
      whereArgs.addAll([q, q, q, q]);
    }

    final results = await db.query(
      'local_attendees',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'nom_complet ASC',
    );

    return results.map((e) => Attendee.fromMap(e)).toList();
  }

  Future<Map<String, int>> getLocalStats({int? campaignId}) async {
    final db = await instance.database;
    
    String whereFilter = '';
    List<dynamic> args = [];
    if (campaignId != null && campaignId > 0) {
      whereFilter = ' WHERE campaign_id = ?';
      args.add(campaignId);
    }

    final total = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM local_attendees$whereFilter', args)) ?? 0;
    
    String whereScanned = (campaignId != null && campaignId > 0)
        ? " WHERE statut_checkin = 'scanne' AND is_banned = 0 AND campaign_id = ?"
        : " WHERE statut_checkin = 'scanne' AND is_banned = 0";
    final scanned = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM local_attendees$whereScanned', args)) ?? 0;

    String whereBanned = (campaignId != null && campaignId > 0)
        ? " WHERE is_banned = 1 AND campaign_id = ?"
        : " WHERE is_banned = 1";
    final banned = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM local_attendees$whereBanned', args)) ?? 0;

    final pendingActions = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM action_sync_queue')) ?? 0;
    final totalLogs = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM agent_audit_logs')) ?? 0;

    return {
      'total': total,
      'scanned': scanned,
      'banned': banned,
      'remaining': (total - scanned - banned) > 0 ? (total - scanned - banned) : 0,
      'pending_sync': pendingActions,
      'total_logs': totalLogs,
    };
  }

  Future<List<Attendee>> getRecentScans({int? campaignId, int limit = 4}) async {
    final db = await instance.database;
    String whereClause = "statut_checkin = 'scanne'";
    List<dynamic> args = [];
    if (campaignId != null && campaignId > 0) {
      whereClause += " AND campaign_id = ?";
      args.add(campaignId);
    }
    final results = await db.query(
      'local_attendees',
      where: whereClause,
      whereArgs: args,
      orderBy: 'scanned_at DESC, id DESC',
      limit: limit,
    );
    return results.map((e) => Attendee.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getPendingActions() async {
    final db = await instance.database;
    return await db.query('action_sync_queue', orderBy: 'id ASC');
  }

  Future<void> clearSyncedActions(List<int> actionIds) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var id in actionIds) {
      batch.delete('action_sync_queue', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  
  // Synchronisation descendante complète (Insertion des NOUVEAUX inscrits + Mise à jour des statuts et bannissements)
  Future<void> syncServerAttendeesRoster(List<Attendee> serverAttendees) async {
    if (serverAttendees.isEmpty) return;
    final db = await instance.database;

    // Récupérer les badges actuellement en attente d'envoi local pour ne pas les écraser
    final pendingActions = await getPendingActions();
    final pendingBadges = pendingActions.map((e) => (e['numero_badge'] as String? ?? '').toUpperCase()).toSet();

    final batch = db.batch();

    for (var a in serverAttendees) {
      // Si une action locale récente n'a pas encore été envoyée pour ce badge, on préserve l'état local
      if (pendingBadges.contains(a.numeroBadge.toUpperCase())) {
        continue;
      }

      batch.insert(
        'local_attendees',
        a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  
  // Enregistrer l'heure de départ d'un participant pour la journée
  Future<bool> recordDailyDeparture({
    required String badgeCode,
    required int agentId,
  }) async {
    final db = await instance.database;
    final cleanCode = badgeCode.trim().toUpperCase();
    final todayDate = DateTime.now().toString().substring(0, 10);
    final todayTime = DateTime.now().toString().substring(11, 19);
    final nowIso = DateTime.now().toString().substring(0, 19);

    final res = await db.update(
      'local_daily_attendance',
      {
        'heure_depart': todayTime,
        'is_synced': 0,
      },
      where: 'UPPER(numero_badge) = ? AND date_presence = ?',
      whereArgs: [cleanCode, todayDate],
    );

    if (res > 0) {
      await db.insert('action_sync_queue', {
        'action_type': 'daily_departure',
        'numero_badge': cleanCode,
        'timestamp': nowIso,
        'door': null,
        'reason': todayDate,
        'expires_at': todayTime,
        'agent_id': agentId,
      });

      await logAudit(
        eventType: 'DAILY_DEPARTURE',
        title: 'Heure de Départ Enregistrée',
        badgeCode: cleanCode,
        details: 'Départ à $todayTime (Jour $todayDate)',
        agentId: agentId,
      );
      return true;
    }
    return false;
  }

  
  // Récupérer la liste complète des émargements / scans du jour (Journalier + Pass Unique)
  Future<List<Map<String, dynamic>>> getDailyAttendanceRecords({
    String? date,
    int? campaignId,
    String? query,
  }) async {
    final db = await instance.database;
    final targetDate = date ?? DateTime.now().toString().substring(0, 10);

    // 1. Émargements journaliers
    String sqlDaily = '''
      SELECT d.id as attendance_id,
             d.campaign_id,
             d.numero_badge,
             d.date_presence,
             d.scanned_at,
             d.door as scanned_door,
             d.heure_arrivee,
             d.heure_depart,
             d.statut,
             a.id as attendee_id,
             a.nom_complet, 
             a.email, 
             a.telephone, 
             a.organisation, 
             a.fonction,
             a.type_pass, 
             a.photo_badge, 
             a.campaign_titre,
             COALESCE(c.mode_emargement, 'journalier') as mode_emargement
      FROM local_daily_attendance d
      LEFT JOIN local_attendees a ON UPPER(d.numero_badge) = UPPER(a.numero_badge)
      LEFT JOIN campaign_info c ON d.campaign_id = c.id
      WHERE d.date_presence = ?
    ''';
    List<dynamic> argsDaily = [targetDate];
    if (campaignId != null) {
      sqlDaily += ' AND d.campaign_id = ?';
      argsDaily.add(campaignId);
    }

    final dailyList = await db.rawQuery(sqlDaily, argsDaily);

    // 2. Scans des Pass uniques / Attendees scannés à cette date
    String sqlAttendees = '''
      SELECT NULL as attendance_id,
             a.campaign_id,
             a.numero_badge,
             substr(a.scanned_at, 1, 10) as date_presence,
             a.scanned_at,
             a.scanned_door,
             substr(a.scanned_at, 12, 8) as heure_arrivee,
             NULL as heure_depart,
             'present' as statut,
             a.id as attendee_id,
             a.nom_complet, 
             a.email, 
             a.telephone, 
             a.organisation, 
             a.fonction,
             a.type_pass, 
             a.photo_badge, 
             a.campaign_titre,
             COALESCE(c.mode_emargement, 'unique') as mode_emargement
      FROM local_attendees a
      LEFT JOIN campaign_info c ON a.campaign_id = c.id
      WHERE a.statut_checkin = 'scanne' AND a.scanned_at LIKE ?
    ''';
    List<dynamic> argsAttendees = ['$targetDate%'];
    if (campaignId != null) {
      sqlAttendees += ' AND a.campaign_id = ?';
      argsAttendees.add(campaignId);
    }

    final attendeesList = await db.rawQuery(sqlAttendees, argsAttendees);

    // Fusionner et dédoublonner par numéro de badge
    final Map<String, Map<String, dynamic>> combined = {};

    for (var r in dailyList) {
      final code = (r['numero_badge'] ?? '').toString().toUpperCase();
      if (code.isNotEmpty) {
        combined[code] = Map<String, dynamic>.from(r);
      }
    }

    for (var r in attendeesList) {
      final code = (r['numero_badge'] ?? '').toString().toUpperCase();
      if (code.isNotEmpty && !combined.containsKey(code)) {
        combined[code] = Map<String, dynamic>.from(r);
      }
    }

    var resultList = combined.values.toList();

    // Filtre par recherche textuelle
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      resultList = resultList.where((item) {
        final name = (item['nom_complet'] ?? '').toString().toLowerCase();
        final badge = (item['numero_badge'] ?? '').toString().toLowerCase();
        final org = (item['organisation'] ?? '').toString().toLowerCase();
        return name.contains(q) || badge.contains(q) || org.contains(q);
      }).toList();
    }

    resultList.sort((a, b) {
      final dateA = (a['scanned_at'] ?? '').toString();
      final dateB = (b['scanned_at'] ?? '').toString();
      return dateB.compareTo(dateA);
    });

    return resultList;
  }


  Future<void> seedInitialDataIfEmpty() async {
    try {
      final db = await instance.database;
    final agentCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM agent_session')) ?? 0;
    if (agentCount == 0) {
      // 1. Agent Samira Karim
      await db.insert('agent_session', {
        'id': 7,
        'code_agent': 'AGT-2026-BF4D3',
        'pin_code': '2942',
        'nom_complet': 'Samira Karim',
        'telephone': '+22791661174',
        'email': 'zouleha829@gmail.com',
        'photo_url': null,
        'role_agent': 'controleur_scan',
        'zone_affectation': 'Informatiques',
        'total_scans': 8,
        'is_logged_in': 1,
      });

      // 2. Campagnes
      await db.insert('campaign_info', {
        'id': 5,
        'titre': 'Formation E-shago',
        'categorie': 'workshop',
        'lieu': 'Makera Niamey',
        'date_debut': '2026-09-02 18:49:00',
        'date_fin': '2026-09-11 18:49:00',
        'type_acces': 'gratuit',
        'statut': 'en_cours',
        'mode_emargement': 'journalier',
      });
      await db.insert('campaign_info', {
        'id': 4,
        'titre': 'Illuminez Votre Marque à Niamey, BILLBOARD',
        'categorie': 'conference',
        'lieu': 'Palais de congrès Niamey',
        'date_debut': '2026-09-01 15:04:00',
        'date_fin': '2026-09-05 15:04:00',
        'type_acces': 'payant',
        'statut': 'planifiee',
        'mode_emargement': 'unique',
      });

      // 3. Participants
      final initialAttendees = [
        Attendee.fromJson({
          'id': 19,
          'campaign_id': 4,
          'commande_ref': 'CMD-20260901-53037',
          'numero_badge': 'MKR-2026-30905',
          'nom_complet': 'Adrouhamane Souley',
          'email': 'doudoulacho137@gmail.com',
          'telephone': '+22799783233',
          'organisation': '',
          'fonction': 'Directeur Générale',
          'type_pass': 'Standard',
          'photo_badge': 'uploads/avatars/avatar_1788272722_0_bot.avif',
          'statut_checkin': 'banni',
          'is_banned': 1,
          'ban_reason': 'Comportement Inapproprié',
          'campaign_titre': 'Illuminez Votre Marque à Niamey, BILLBOARD',
        }),
        Attendee.fromJson({
          'id': 23,
          'campaign_id': 5,
          'commande_ref': 'CMD-20260902-6D52A',
          'numero_badge': 'MKR-2026-50145',
          'nom_complet': 'Aziz',
          'email': 'kkdrone@numeris-niger.net',
          'telephone': '+22777783233',
          'organisation': '',
          'fonction': '',
          'type_pass': 'VIP',
          'photo_badge': 'uploads/avatars/avatar_1788355247_0_images2.jpeg',
          'statut_checkin': 'scanne',
          'campaign_titre': 'Formation E-shago',
        }),
        Attendee.fromJson({
          'id': 21,
          'campaign_id': 5,
          'commande_ref': 'CMD-20260902-E496D',
          'numero_badge': 'MKR-2026-01671',
          'nom_complet': 'Karim',
          'email': 'karim37@gmail.com',
          'telephone': '+22799783233',
          'organisation': '',
          'fonction': '',
          'type_pass': 'Standard',
          'photo_badge': 'uploads/avatars/avatar_1788354445_1_200121-developpeur-web.jpeg',
          'statut_checkin': 'scanne',
          'campaign_titre': 'Formation E-shago',
        }),
        Attendee.fromJson({
          'id': 20,
          'campaign_id': 5,
          'commande_ref': 'CMD-20260902-E496D',
          'numero_badge': 'MKR-2026-02328',
          'nom_complet': 'Kountché Aziz',
          'email': 'drone@numeris-niger.net',
          'telephone': '+22799783233',
          'organisation': '',
          'fonction': '',
          'type_pass': 'Standard',
          'photo_badge': 'uploads/avatars/avatar_1788354444_0_img-20240713-wa0007.jpg',
          'statut_checkin': 'scanne',
          'campaign_titre': 'Formation E-shago',
        }),
        Attendee.fromJson({
          'id': 22,
          'campaign_id': 5,
          'commande_ref': 'CMD-20260902-CB057',
          'numero_badge': 'MKR-2026-20520',
          'nom_complet': 'Sani',
          'email': 'doudoulacho@gmail.com',
          'telephone': '+22790783233',
          'organisation': '',
          'fonction': '',
          'type_pass': 'VIP',
          'photo_badge': 'uploads/avatars/avatar_1788354563_0_bot.jpg',
          'statut_checkin': 'scanne',
          'campaign_titre': 'Formation E-shago',
        }),
      ];
      await cacheAttendees(initialAttendees);
    }
    } catch (e) {
      // Ignorer ou logguer silencieusement sans bloquer le démarrage
    }
  }


  // Supprimer une campagne et toutes les données reliées (participants, émargements)
  Future<void> deleteCampaignAndData(int campaignId) async {
    final db = await instance.database;
    await db.delete('local_daily_attendance', where: 'campaign_id = ?', whereArgs: [campaignId]);
    await db.delete('local_attendees', where: 'campaign_id = ?', whereArgs: [campaignId]);
    await db.delete('campaign_info', where: 'id = ?', whereArgs: [campaignId]);
  }

  // Obtenir la liste des campagnes avec le nombre de participants locaux
  Future<List<Map<String, dynamic>>> getCampaignsWithStats() async {
    final db = await instance.database;
    final campaigns = await db.query('campaign_info');
    List<Map<String, dynamic>> results = [];
    for (var c in campaigns) {
      final cId = c['id'];
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM local_attendees WHERE campaign_id = ?', [cId]
      )) ?? 0;
      final scanned = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM local_attendees WHERE campaign_id = ? AND statut_checkin = 'scanne'", [cId]
      )) ?? 0;
      results.add({
        ...c,
        'attendees_count': count,
        'scanned_count': scanned,
      });
    }
    return results;
  }

  Future<void> logoutAgent() async {
    final db = await instance.database;
    await db.update('agent_session', {'is_logged_in': 0});
  }

  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('agent_session');
    await db.delete('campaign_info');
    await db.delete('local_attendees');
    await db.delete('action_sync_queue');
    await db.delete('agent_audit_logs');
  }
}
