import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'acesso.dart';
import 'catalogo.dart';
import 'config.dart';

/// Junta o que o aparelho ouviu e envia ao painel em lotes (a cada 3 minutos ou a cada
/// 10 musicas), para nao sobrecarregar o servidor. O que nao foi enviado fica guardado
/// no celular e segue depois, por exemplo quando voltar a internet.
class TelemetriaService {
  TelemetriaService._();
  static final TelemetriaService i = TelemetriaService._();

  static const _chave = 'sonora2_fila_plays';
  static const _maxFila = 500;
  static const _tamanhoLote = 100;

  final List<Map<String, dynamic>> _fila = [];
  List<Map<String, dynamic>>? _voo; // lote em envio (mantem o mesmo id em novas tentativas)
  String? _vooId;
  Timer? _timer;
  bool _enviando = false;

  Future<void> iniciar() async {
    if (urlControle.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final txt = sp.getString(_chave);
      if (txt != null) {
        _fila
          ..clear()
          ..addAll((jsonDecode(txt) as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => enviar());
    enviar();
  }

  /// Chamado pelo player depois de alguns segundos ouvindo a mesma musica.
  void registrarPlay(Faixa f, String genero) {
    if (urlControle.isEmpty) return;
    _fila.add({
      't': DateTime.now().millisecondsSinceEpoch,
      'f': f.id,
      'ti': f.tituloCompleto,
      'ar': f.artista,
      'g': genero,
    });
    if (_fila.length > _maxFila) _fila.removeRange(0, _fila.length - _maxFila);
    _salvar();
    if (_fila.length >= 10) enviar();
  }

  Future<void> _salvar() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_chave, jsonEncode(_fila));
    } catch (_) {}
  }

  Future<void> enviar() async {
    if (_enviando || urlControle.isEmpty) return;
    if (_voo == null && _fila.isEmpty) return;
    if (AcessoService.i.estado != EstadoAcesso.liberado) return;
    _enviando = true;
    try {
      final id = await AcessoService.i.obterId();
      if (_voo == null) {
        _voo = _fila.take(_tamanhoLote).toList();
        _vooId = '${DateTime.now().millisecondsSinceEpoch}-${_voo!.length}';
      }
      final corpo = jsonEncode(
          {'action': 'plays', 'id': id, 'lote': _vooId, 'eventos': _voo});
      final r = await http
          .post(Uri.parse(urlControle),
              headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: corpo)
          .timeout(const Duration(seconds: 25));
      // O Apps Script grava e responde com um redirecionamento (302): isso tambem e sucesso.
      if (r.statusCode == 200 || r.statusCode == 302) {
        if (r.statusCode == 200) {
          try {
            final j = jsonDecode(r.body) as Map<String, dynamic>;
            if (j['ok'] != true && j['status'] != null) {
              await AcessoService.i.registrarStatus(j['status'] as String);
            }
          } catch (_) {}
        }
        final n = _voo!.length;
        _fila.removeRange(0, n.clamp(0, _fila.length));
        _voo = null;
        _vooId = null;
        await _salvar();
      }
    } catch (_) {
      // tenta de novo no proximo ciclo, com o mesmo lote
    } finally {
      _enviando = false;
    }
  }
}
