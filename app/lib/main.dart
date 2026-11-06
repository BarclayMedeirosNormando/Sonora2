import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Servico de audio em primeiro plano: mantem a musica e a troca de faixa
  // funcionando com a tela apagada ou o app em segundo plano.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'br.sonora2.audio',
    androidNotificationChannelName: 'Sonora',
    androidNotificationOngoing: true,
    // sem botoes de avancar/voltar 10s: o app nao usa e eles quebravam a
    // notificacao no Android 13+ (icone de CustomAction ausente)
    fastForwardInterval: Duration.zero,
    rewindInterval: Duration.zero,
  );
  // Android 13+: pede permissao para mostrar a notificacao de midia.
  try {
    await Permission.notification.request();
  } catch (_) {}
  runApp(const SonoraApp());
}

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
