import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_hub_screen.dart';
import 'services/api_service.dart';
import 'services/event_selection_service.dart';
import 'database/db_helper.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  await ApiService.initBaseUrl();
  await EventSelectionService.instance.init();
  await LocalDatabase.instance.seedInitialDataIfEmpty();

  bool hasSession = false;
  try {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('agent_session', where: 'is_logged_in = 1');
    if (rows.isNotEmpty) {
      hasSession = true;
    }
  } catch (_) {}

  runApp(MakeraAgentApp(hasSession: hasSession));
}

class MakeraAgentApp extends StatelessWidget {
  final bool hasSession;
  const MakeraAgentApp({super.key, required this.hasSession});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Makera Pass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('fr', 'FR'),
      home: hasSession ? const HomeHubScreen() : const LoginScreen(),
    );
  }
}
