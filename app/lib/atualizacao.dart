import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'acesso.dart';
import 'config.dart';
import 'instalador.dart';
import 'widgets.dart';

class InfoAtualizacao {
  final String versao;
  final String url;
  final String notas;
  InfoAtualizacao(this.versao, this.url, this.notas);
}

int _build(String v) {
  final m = RegExp(r'\+(\d+)').firstMatch(v);
  return m == null ? 0 : int.parse(m.group(1)!);
}

/// Pergunta ao servidor se existe versao mais nova do que a instalada.
/// Devolve null quando esta em dia, sem internet, ou o aparelho nao esta liberado.
Future<InfoAtualizacao?> verificarAtualizacao() async {
  if (urlControle.isEmpty || !suportaInstalar) return null;
  try {
    final id = await AcessoService.i.obterId();
    final uri = Uri.parse(urlControle)
        .replace(queryParameters: {'action': 'versao', 'id': id});
    final r = await http.get(uri).timeout(const Duration(seconds: 15));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['ok'] != true) return null;
    final url = j['url'] as String?;
    final versao = j['versao'] as String? ?? '';
    if (url == null || url.isEmpty) return null;
    if ((j['build'] as num? ?? 0).toInt() <= _build(versaoApp)) return null;
    return InfoAtualizacao(versao, url, j['notas'] as String? ?? '');
  } catch (_) {
    return null;
  }
}

/// Mostra a janela "Nova versao" e, ao tocar em Atualizar, baixa e abre o instalador.
Future<void> mostrarAtualizacao(BuildContext context, InfoAtualizacao info) {
  return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoAtualizacao(info));
}

/// Usado no toque na versao (Inicio): verifica e avisa mesmo quando esta em dia.
Future<void> verificarManual(BuildContext context) async {
  final msg = ScaffoldMessenger.of(context);
  msg.showSnackBar(const SnackBar(content: Text('Procurando atualização…')));
  final info = await verificarAtualizacao();
  msg.hideCurrentSnackBar();
  if (!context.mounted) return;
  if (info == null) {
    msg.showSnackBar(const SnackBar(content: Text('Você já está na versão mais nova.')));
  } else {
    await mostrarAtualizacao(context, info);
  }
}

class _DialogoAtualizacao extends StatefulWidget {
  final InfoAtualizacao info;
  const _DialogoAtualizacao(this.info);
  @override
  State<_DialogoAtualizacao> createState() => _DialogoAtualizacaoState();
}

class _DialogoAtualizacaoState extends State<_DialogoAtualizacao> {
  bool _baixando = false;
  bool _erro = false;
  String _msg = '';
  double? _prog;

  Future<void> _atualizar() async {
    setState(() {
      _baixando = true;
      _erro = false;
      _msg = 'Iniciando…';
      _prog = null;
    });
    await instalarApk(widget.info.url, (m, p, erro) {
      if (!mounted) return;
      setState(() {
        _msg = m;
        _prog = p;
        _erro = erro;
        if (erro) _baixando = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Nova versão disponível'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Versão ${widget.info.versao}  (você tem $versaoApp)',
            style: const TextStyle(color: cinzaTexto)),
        if (widget.info.notas.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(widget.info.notas),
        ],
        if (_msg.isNotEmpty) ...[
          const SizedBox(height: 16),
          if (_baixando) LinearProgressIndicator(value: _prog, color: verde),
          const SizedBox(height: 8),
          Text(_msg, style: TextStyle(color: _erro ? Colors.redAccent : cinzaTexto)),
        ],
      ]),
      actions: [
        if (!_baixando)
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Depois')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: verde, foregroundColor: Colors.black),
          onPressed: _baixando ? null : _atualizar,
          child: Text(_erro ? 'Tentar de novo' : 'Atualizar agora'),
        ),
      ],
    );
  }
}
