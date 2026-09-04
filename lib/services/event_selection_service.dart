import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EventSelectionService {
  static final EventSelectionService instance = EventSelectionService._();
  EventSelectionService._();

  static const String _keySelectedCampaignId = 'active_selected_campaign_id';
  static const String _keySelectedCampaignTitle = 'active_selected_campaign_title';

  int? _selectedCampaignId;
  String? _selectedCampaignTitle;

  int? get selectedCampaignId => _selectedCampaignId;
  String? get selectedCampaignTitle => _selectedCampaignTitle;
  bool get isGlobalMode => _selectedCampaignId == null;

  final ValueNotifier<int?> selectionNotifier = ValueNotifier<int?>(null);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (prefs.containsKey(_keySelectedCampaignId)) {
        final val = prefs.get(_keySelectedCampaignId);
        if (val is int) {
          _selectedCampaignId = val;
        } else if (val is String) {
          _selectedCampaignId = int.tryParse(val);
        }
        _selectedCampaignTitle = prefs.getString(_keySelectedCampaignTitle);
        selectionNotifier.value = _selectedCampaignId;
      }
    } catch (_) {}
  }

  Future<void> setSelectedCampaign({int? campaignId, String? campaignTitle}) async {
    _selectedCampaignId = campaignId;
    _selectedCampaignTitle = campaignTitle;
    selectionNotifier.value = campaignId;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (campaignId != null && campaignId > 0) {
        await prefs.setInt(_keySelectedCampaignId, campaignId);
        if (campaignTitle != null && campaignTitle.isNotEmpty) {
          await prefs.setString(_keySelectedCampaignTitle, campaignTitle);
        }
      } else {
        await prefs.remove(_keySelectedCampaignId);
        await prefs.remove(_keySelectedCampaignTitle);
      }
    } catch (_) {}
  }
}
