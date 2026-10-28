import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'acesso.dart';
import 'catalogo.dart';
import 'catalogo_local.dart';
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

Map<String, dynamic>? _ultima;
DateTime _ultimaEm = DateTime.fromMillisecondsSinceEpoch(0);

/// Uma unica pergunta ao servidor serve para o APK e para o catalogo (guardada por 30 s).
Future<Map<String, dynamic>?> _consultar() async {
  if (urlControle.isEmpty) return null;
  if (_ultima != null && DateTime.now().difference(_ultimaEm).inSeconds < 30) {
    return _ultima;
  }
  try {
    final id = await AcessoService.i.obterId();
    final uri = Uri.parse(urlControle)
        .replace(queryParameters: {'action': 'versao', 'id': id});
    final r = await http.get(uri).timeout(const Duration(seconds: 15));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['ok'] != true) return null;
    _ultima = j;
    _ultimaEm = DateTime.now();
    return j;
  } catch (_) {
    return null;
  }
}

/// Devolve null quando o APK esta em dia, sem internet, ou o aparelho nao esta liberado.
Future<InfoAtualizacao?> verificarAtualizacao() async {
  if (!suportaInstalar) return null;
  final j = await _consultar();
  if (j == null) return null;
  final url = j['url'] as String?;
  if (url == null || url.isEmpty) return null;
  if ((j['build'] as num? ?? 0).toInt() <= _build(versaoApp)) return null;
  return InfoAtualizacao(j['versao'] as String? ?? '', url, j['notas'] as String? ?? '');
}

class InfoCatalogo {
  final String versao;
  final String url;
  final String notas;
  InfoCatalogo(this.versao, this.url, this.notas);
}

/// Devolve o catalogo novo publicado no painel, se for diferente do que o app ja usa.
Future<InfoCatalogo?> verificarCatalogo() async {
  if (!suportaCatalogoRemoto) return null;
  final j = await _consultar();
  if (j == null) return null;
  final url = j['catUrl'] as String?;
  final versao = j['catVersao'] as String? ?? '';
  if (url == null || url.isEmpty || versao.isEmpty) return null;
  if (versao == await versaoLocal()) return null;
  return InfoCatalogo(versao, url, j['catNotas'] as String? ?? '');
}

/// Mostra a janela "Nova versao" e, ao tocar em Atualizar, baixa e abre o instalador.
Future<void> mostrarAtualizacao(BuildContext context, InfoAtualizacao info) {
  return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoAtualizacao(info));
}

/// Procura APK novo e catalogo novo. [manual]: avisa tambem quando esta tudo em dia.
/// [aoAtualizarCatalogo] recebe o catalogo recem-instalado, ja carregado.
Future<void> verificarTudo(BuildContext context,
    {bool manual = false, required void Function(Catalogo) aoAtualizarCatalogo}) async {
  final msg = ScaffoldMessenger.of(context);
  if (manual) {
    _ultima = null;
    msg.showSnackBar(const SnackBar(content: Text('Procurando atualização…')));
  }
  final app = await verificarAtualizacao();
  final cat = await verificarCatalogo();
  if (manual) msg.hideCurrentSnackBar();
  if (!context.mounted) return;
  if (app != null) await mostrarAtualizacao(context, app);
  if (cat != null && context.mounted) {
    final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DialogoCatalogo(cat));
    if (ok == true) aoAtualizarCatalogo(await Catalogo.carregar());
  }
  if (manual && app == null && cat == null && context.mounted) {
    msg.showSnackBar(const SnackBar(content: Text('Tudo em dia: app e catálogo atualizados.')));
  }
}

class _DialogoCatalogo extends StatefulWidget {
  final InfoCatalogo info;
  const _DialogoCatalogo(this.info);
  @override
  State<_DialogoCatalogo> createState() => _DialogoCatalogoState();
}

class _DialogoCatalogoState extends State<_DialogoCatalogo> {
  bool _baixando = false;
  String? _erro;
  double? _prog;

  Future<void> _atualizar() async {
    setState(() {
      _baixando = true;
      _erro = null;
      _prog = null;
    });
    try {
      await baixarEInstalarCatalogo(widget.info.url, widget.info.versao, (p) {
        if (mounted) setState(() => _prog = p);
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _baixando = false;
          _erro = 'Não foi possível atualizar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Músicas novas disponíveis'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Catálogo ${widget.info.versao}', style: const TextStyle(color: cinzaTexto)),
        if (widget.info.notas.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(widget.info.notas),
        ],
        if (_baixando) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _prog, color: verde),
          const SizedBox(height: 8),
          Text(_prog == null ? 'Baixando…' : 'Baixando… ${(_prog! * 100).round()}%',
              style: const TextStyle(color: cinzaTexto)),
        ],
        if (_erro != null) ...[
          const SizedBox(height: 12),
          Text(_erro!, style: const TextStyle(color: Colors.redAccent)),
        ],
      ]),
      actions: [
        if (!_baixando)
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Depois')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: verde, foregroundColor: Colors.black),
          onPressed: _baixando ? null : _atualizar,
          child: Text(_erro != null ? 'Tentar de novo' : 'Atualizar agora'),
        ),
      ],
    );
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
