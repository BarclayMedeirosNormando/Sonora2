import 'package:flutter/material.dart';
import 'acesso.dart';
import 'acesso_tela.dart';
import 'biblioteca_usuario.dart';
import 'catalogo.dart';
import 'downloads.dart';
import 'shell.dart';
import 'telemetria.dart';
import 'widgets.dart';

class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  String? _erro;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final res = await Future.wait<Object?>([
        Catalogo.carregar(),
        MinhaBiblioteca.i.carregar(),
        DownloadService.i.carregar(),
        Future<void>.delayed(const Duration(milliseconds: 1200)),
        AcessoService.i.validar(),
      ]);
      if (!mounted) return;
      final cat = res[0] as Catalogo;
      final acesso = res[4] as EstadoAcesso;
      if (acesso != EstadoAcesso.liberado) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => TelaAcesso(acesso, cat)));
        return;
      }
      TelemetriaService.i.iniciar();
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => Shell(cat)));
    } catch (e) {
      setState(() => _erro = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const alturas = [28.0, 56.0, 84.0, 48.0, 70.0, 36.0, 20.0];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(32)),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (final h in alturas)
                        Container(
                          width: 8,
                          height: h,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                              color: verde, borderRadius: BorderRadius.circular(4)),
                        ),
                    ]),
              ),
              const SizedBox(height: 28),
              const Text('Sonora',
                  style: TextStyle(
                      fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              const Text('Sua música, organizada para você',
                  style: TextStyle(fontSize: 15, color: cinzaTexto)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(80, 0, 80, 72),
            child: _erro != null
                ? Text(
                    'Catálogo não encontrado.\nCopie saida/app para assets/catalogo e rode de novo.\n\n$_erro',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: cinzaTexto))
                : Column(children: const [
                    LinearProgressIndicator(
                        minHeight: 4,
                        color: verde,
                        backgroundColor: Color(0xFF333333)),
                    SizedBox(height: 12),
                    Text('Carregando biblioteca…',
                        style: TextStyle(fontSize: 12, color: cinzaTexto)),
                  ]),
          ),
        ]),
      ),
    );
  }
}
