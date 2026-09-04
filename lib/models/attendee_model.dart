class Attendee {
  final int id;
  final int campaignId;
  final String commandeRef;
  final String numeroBadge;
  final String nomComplet;
  final String email;
  final String telephone;
  final String organisation;
  final String fonction;
  final String typePass;
  final String? photoBadge;
  final String campaignTitre;
  String statutCheckin;
  String? scannedAt;
  String? scannedDoor;
  int isSynced;
  int isBanned;
  String? banReason;
  String? banExpiresAt;
  String? bannedAt;

  Attendee({
    required this.id,
    required this.campaignId,
    required this.commandeRef,
    required this.numeroBadge,
    required this.nomComplet,
    required this.email,
    required this.telephone,
    required this.organisation,
    required this.fonction,
    required this.typePass,
    this.photoBadge,
    this.campaignTitre = '',
    required this.statutCheckin,
    this.scannedAt,
    this.scannedDoor,
    this.isSynced = 1,
    this.isBanned = 0,
    this.banReason,
    this.banExpiresAt,
    this.bannedAt,
  });

  String? get resolvedPhotoUrl {
    if (photoBadge == null || photoBadge!.trim().isEmpty) return null;
    final p = photoBadge!.trim();
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    return 'https://gayya-niger.ne/makera_event/$p';
  }

  factory Attendee.fromJson(Map<String, dynamic> json) {
    return Attendee(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      campaignId: json['campaign_id'] is int ? json['campaign_id'] : int.parse(json['campaign_id'].toString()),
      commandeRef: json['commande_ref'] ?? '',
      numeroBadge: json['numero_badge'] ?? '',
      nomComplet: json['nom_complet'] ?? 'Participant',
      email: json['email'] ?? '',
      telephone: json['telephone'] ?? '',
      organisation: json['organisation'] ?? '',
      fonction: json['fonction'] ?? '',
      typePass: json['type_pass'] ?? 'Standard',
      photoBadge: json['photo_badge'],
      campaignTitre: json['campaign_titre'] ?? '',
      statutCheckin: json['statut_checkin'] ?? 'non_scanne',
      scannedAt: json['scanned_at'],
      scannedDoor: json['scanned_door'],
      isSynced: 1,
      isBanned: json['is_banned'] != null ? int.tryParse(json['is_banned'].toString()) ?? 0 : 0,
      banReason: json['ban_reason'],
      banExpiresAt: json['ban_expires_at'],
      bannedAt: json['banned_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'campaign_id': campaignId,
      'commande_ref': commandeRef,
      'numero_badge': numeroBadge,
      'nom_complet': nomComplet,
      'email': email,
      'telephone': telephone,
      'organisation': organisation,
      'fonction': fonction,
      'type_pass': typePass,
      'photo_badge': photoBadge,
      'campaign_titre': campaignTitre,
      'statut_checkin': statutCheckin,
      'scanned_at': scannedAt,
      'scanned_door': scannedDoor,
      'is_synced': isSynced,
      'is_banned': isBanned,
      'ban_reason': banReason,
      'ban_expires_at': banExpiresAt,
      'banned_at': bannedAt,
    };
  }

  factory Attendee.fromMap(Map<String, dynamic> map) {
    return Attendee(
      id: map['id'],
      campaignId: map['campaign_id'],
      commandeRef: map['commande_ref'] ?? '',
      numeroBadge: map['numero_badge'] ?? '',
      nomComplet: map['nom_complet'] ?? '',
      email: map['email'] ?? '',
      telephone: map['telephone'] ?? '',
      organisation: map['organisation'] ?? '',
      fonction: map['fonction'] ?? '',
      typePass: map['type_pass'] ?? 'Standard',
      photoBadge: map['photo_badge'],
      campaignTitre: map['campaign_titre'] ?? '',
      statutCheckin: map['statut_checkin'] ?? 'non_scanne',
      scannedAt: map['scanned_at'],
      scannedDoor: map['scanned_door'],
      isSynced: map['is_synced'] ?? 1,
      isBanned: map['is_banned'] ?? 0,
      banReason: map['ban_reason'],
      banExpiresAt: map['ban_expires_at'],
      bannedAt: map['banned_at'],
    );
  }
}
