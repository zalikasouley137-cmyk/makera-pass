import '../services/event_selection_service.dart';
import '../services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../database/db_helper.dart';
import '../utils/sound_haptic_helper.dart';
import '../widgets/scan_result_sheet.dart';

class ScannerHudScreen extends StatefulWidget {
  final String doorName;
  final int agentId;
  final int? activeCampaignId;

  const ScannerHudScreen({
    super.key,
    required this.doorName,
    required this.agentId,
    this.activeCampaignId,
  });

  @override
  State<ScannerHudScreen> createState() => _ScannerHudScreenState();
}

class _ScannerHudScreenState extends State<ScannerHudScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  bool _torchOn = false;
  int? _currentCampaignId;
  String _currentCampaignTitle = EventSelectionService.instance.selectedCampaignTitle ?? 'Multi-Événements';

  @override
  void initState() {
    super.initState();
    _currentCampaignId = widget.activeCampaignId ?? EventSelectionService.instance.selectedCampaignId;
    _loadCampaignInfo();
  }

  void _loadCampaignInfo() async {
    if (_currentCampaignId != null && _currentCampaignId! > 0) {
      final camps = await LocalDatabase.instance.getAllCampaigns();
      final cur = camps.firstWhere((c) => c['id'] == _currentCampaignId, orElse: () => {});
      if (mounted) {
        setState(() {
          _currentCampaignTitle = cur['titre'] ?? 'Événement Actif';
        });
      }
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    setState(() => _isProcessing = true);

    final res = await LocalDatabase.instance.validateBadge(
      rawValue,
      widget.doorName,
      widget.agentId,
      activeCampaignId: _currentCampaignId,
    );

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

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScanResultModal(
        resultType: resultType,
        attendee: res['attendee'],
        rawBadgeCode: rawValue,
        wrongCampaign: res['wrongCampaign'] == true,
        agentId: widget.agentId,
        onNextScan: () => Navigator.pop(context),
      ),
    );

    // Reprendre la détection
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Scanner Camera Feed
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),

          // Futuristic Targeting Reticle & Hologram
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isProcessing ? Colors.orangeAccent : const Color(0xFFF28123).withOpacity(0.6),
                  width: 2,
                ),
              ),
              child: Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isProcessing ? Colors.greenAccent : const Color(0xFFF28123),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF28123).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Top App Bar Controls & Active Campaign Info
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      // Active Campaign Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFF28123), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.qr_code_scanner, color: Color(0xFFF28123), size: 14),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 110),
                              child: Text(
                                _currentCampaignTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Voyant Réseau
                      const ConnectivityVoyant(mini: true),
                      // Flashlight Toggle
                      IconButton(
                        icon: Icon(
                          _torchOn ? Icons.flash_on : Icons.flash_off,
                          color: _torchOn ? Colors.yellowAccent : Colors.white,
                        ),
                        onPressed: () async {
                          await _scannerController.toggleTorch();
                          setState(() => _torchOn = !_torchOn);
                        },
                      ),
                    ],
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
