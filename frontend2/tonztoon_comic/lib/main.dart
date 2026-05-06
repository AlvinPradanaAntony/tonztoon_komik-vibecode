import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/core/app_theme.dart';
import 'src/features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Awal aplikasi (Splash & Onboarding): Fullscreen tanpa status bar dan nav bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  runApp(const TonztoonApp());
}

class TonztoonApp extends StatelessWidget {
  const TonztoonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TonzToon',
      // Menggunakan tema terang dan gelap dari app_theme.dart (dengan Palet Baru!)
      theme: TonztoonTheme.light(),
      darkTheme: TonztoonTheme.dark(),
      themeMode: ThemeMode.system, // Menyesuaikan dengan sistem (gelap/terang)
      // Aplikasi kini dimulai dari SplashScreen sebelum ke AppShell
      home: const SplashScreen(),
    );
  }
}
