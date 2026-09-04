import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../services/api_service.dart';
import 'home_hub_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _codeController = TextEditingController(text: 'AGT-2026-BF4D3');
  final _pinController = TextEditingController(text: '2942');
  final _serverController = TextEditingController(text: 'https://gayya-niger.ne/makera_event/api');
  bool _isLoading = false;
  bool _showSettings = false;
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    ApiService.initBaseUrl();
  }

  void _performLogin() async {
    final code = _codeController.text.trim().toUpperCase();
    final pin = _pinController.text.trim();

    if (code.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Veuillez renseigner le Code Agent et le Code PIN.'),
            ],
          ),
          backgroundColor: AppColors.warningAmber,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final res = await ApiService.loginAndSync(
      codeAgent: code,
      pinCode: pin,
      customBaseUrl: _serverController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (res['success'] == true) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeHubScreen()),
      );
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.dangerRed, size: 24),
              SizedBox(width: 10),
              Text('Échec d\'accès', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              res['message'] ?? 'Erreur de connexion',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Compris', style: TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Halo Décoratif Orange Haut Gauche
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryOrange.withOpacity(0.16),
              ),
            ),
          ),
          // Halo Décoratif Bleu Bas Droite
          Positioned(
            bottom: -90,
            right: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentBlue.withOpacity(0.16),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo & Badge Futuriste
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryOrange.withOpacity(0.15),
                        border: Border.all(color: AppColors.primaryOrange, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryOrange.withOpacity(0.35),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryOrange, size: 42),
                      ),
                    ).animate().scale(duration: 450.ms, curve: Curves.easeOutBack),

                    const SizedBox(height: 16),

                    Text(
                      'MAKERA PASS',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Contrôle d\'Accès Terrain & Émargements',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.65)),
                    ),

                    const SizedBox(height: 28),

                    // Carte Glassmorphism de Connexion
                    GlassContainer(
                      padding: const EdgeInsets.all(22),
                      borderRadius: 22,
                      borderColor: Colors.white.withOpacity(0.15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.fingerprint, color: AppColors.primaryOrange, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'CODE UNIQUE AGENT',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 0.8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _codeController,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF1E293B).withOpacity(0.6),
                              hintText: 'Ex: AGT-2026-BF4D3',
                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                              prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.primaryOrange, size: 20),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.primaryOrange, width: 1.8),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          const Row(
                            children: [
                              Icon(Icons.lock_outline, color: AppColors.primaryOrange, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'CODE PIN CONFIDENTIEL',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 0.8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            obscureText: _obscurePin,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              fontSize: 16,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF1E293B).withOpacity(0.6),
                              hintText: '••••',
                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                              prefixIcon: const Icon(Icons.dialpad, color: AppColors.primaryOrange, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
                                onPressed: () => setState(() => _obscurePin = !_obscurePin),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.primaryOrange, width: 1.8),
                              ),
                            ),
                          ),

                          const SizedBox(height: 22),

                          // Bouton Principal de Connexion
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _performLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryOrange,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 6,
                                shadowColor: AppColors.primaryOrange.withOpacity(0.4),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.bolt, color: Colors.white, size: 22),
                                        SizedBox(width: 8),
                                        Text(
                                          'OUVRIR LA SESSION',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Toggle Paramètres Serveur
                          Center(
                            child: TextButton.icon(
                              onPressed: () => setState(() => _showSettings = !_showSettings),
                              icon: Icon(
                                _showSettings ? Icons.keyboard_arrow_up : Icons.tune_rounded,
                                size: 16,
                                color: Colors.white54,
                              ),
                              label: Text(
                                _showSettings ? 'Masquer URL Serveur' : 'Configurer Serveur API',
                                style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),

                          if (_showSettings) ...[
                            const SizedBox(height: 6),
                            TextField(
                              controller: _serverController,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.black26,
                                labelText: 'URL de l\'API Serveur',
                                labelStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Mention Mode Hors-Ligne Pro
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.offline_bolt_rounded, size: 14, color: AppColors.successGreen),
                        const SizedBox(width: 6),
                        Text(
                          'Fonctionne 100% Hors-Ligne après premier login',
                          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
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
    );
  }
}
