import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'acesso.dart';
import 'catalogo.dart';
import 'shell.dart';
import 'telemetria.dart';
import 'widgets.dart';

/// Tela mostrada quando o aparelho ainda nao foi liberado (ou foi bloqueado).
class TelaAcesso extends StatefulWidget {
  final EstadoAcesso estado;
  final Catalogo catalogo;
  const TelaAcesso(this.estado, this.catalogo, {super.key});
  @override
  State<TelaAcesso> createState() => _TelaAcessoState();
}

class _TelaAcessoState extends State<TelaAcesso> {
  late EstadoAcesso _estado = widget.estado;
  final _nome = TextEditingController();
  String _id = '';
  bool _verificando = false;

  @override
  void initState() {
    super.initState();
    AcessoService.i.obterId().then((v) {
      if (mounted) setState(() => _id = v);
    });
    AcessoService.i.nomeSalvo().then((v) {
      if (mounted) _nome.text = v;
    });
  }

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _verificar() async {
    setState(() => _verificando = true);
    await AcessoService.i.salvarNome(_nome.text);
    final e = await AcessoService.i.validar(forcar: true);
    if (!mounted) return;
    if (e == EstadoAcesso.liberado) {
      TelemetriaService.i.iniciar();
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => Shell(widget.catalogo)));
      return;
    }
    setState(() {
      _estado = e;
      _verificando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (icone, titulo, texto) = switch (_estado) {
      EstadoAcesso.bloqueado => (
          Icons.block,
          'Acesso bloqueado',
          'Este aparelho foi bloqueado. Fale com o administrador.'
        ),
      EstadoAcesso.semConexao => (
          Icons.wifi_off,
          'Sem conexão',
          'Não foi possível verificar o acesso. Conecte-se à internet e tente de novo.'
        ),
      _ => (
          Icons.lock_outline,
          'Aguardando liberação',
          'Envie o código abaixo para o administrador liberar o seu acesso e depois toque em "Verificar".'
        ),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icone, size: 64, color: verde),
                const SizedBox(height: 16),
                Text(titulo,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(texto,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: cinzaTexto)),
                if (_estado != EstadoAcesso.semConexao) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(
                          child: SelectableText(_id.isEmpty ? '...' : _id,
                              style: const TextStyle(fontSize: 13))),
                      IconButton(
                          tooltip: 'Copiar',
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: _id.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(ClipboardData(text: _id));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Código copiado')));
                                }),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nome,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Seu nome (para o administrador saber quem é)',
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: verde,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(46)),
                  onPressed: _verificando ? null : _verificar,
                  icon: _verificando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(_verificando ? 'Verificando…' : 'Verificar'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
