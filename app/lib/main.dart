import 'package:flutter/material.dart';
import 'splash.dart';

void main() => runApp(const SonoraApp());

class SonoraApp extends StatelessWidget {
  const SonoraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sonora',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF1DB954),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF121212),
          appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF121212),
              surfaceTintColor: Colors.transparent,
              elevation: 0),
          navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Color(0xFF181818),
              indicatorColor: Color(0xFF2A2A2A)),
        ),
        home: const Splash(),
      );
}
