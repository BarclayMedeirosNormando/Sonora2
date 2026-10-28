import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'armazenamento.dart';
import 'catalogo.dart';
import 'config.dart';

class Baixada {
  final Faixa faixa;
  final String arquivo; // nome do arquivo dentro da pasta de downloads
  final int bytes;
  Baixada(this.faixa, this.arquivo, this.bytes);
}

/// Musicas baixadas para ouvir offline: fila (2 por vez), progresso,
/// cancelar, tentar de novo e remover. O indice fica em shared_preferences.
class DownloadService extends ChangeNotifier {
  DownloadService._();
  static final DownloadService i = DownloadService._();

  static const _chave = 'sonora_downloads_v1';
  static const _maxSimultaneos = 2;

  final Map<String, Baixada> _baixadas = {}; // mais recente primeiro
  final List<Faixa> _fila = [];
  final Map<String, Faixa> _ativas = {};
  final Map<String, double> _progresso = {};
  final Map<String, Faixa> _falhas = {};
  final Map<String, String> motivoFalha = {};
  final Set<String> _cancelados = {};
  String? _pasta;
  bool modoOffline = false;

  bool get suportado => suportaDownload;
  List<Baixada> get baixadas => _baixadas.values.toList();
  List<Faixa> get faixasBaixadas => _baixadas.values.map((b) => b.faixa).toList();
  List<Faixa> get emAndamento => [..._ativas.values, ..._fila];
  List<Faixa> get falhas => _falhas.values.toList();
  int get totalBytes => _baixadas.values.fold(0, (a, b) => a + b.bytes);

  bool estaBaixada(String id) => _baixadas.containsKey(id);
  bool estaNaFila(String id) =>
      _ativas.containsKey(id) || _fila.any((f) => f.id == id);

  /// 0..1 enquanto baixa; null se ainda esta na fila ou sem tamanho conhecido.
  double? progresso(String id) => _progresso[id];

  /// Caminho do arquivo local se a faixa estiver baixada.
  String? caminho(String id) {
    final b = _baixadas[id];
    if (b == null || _pasta == null) return null;
    return '$_pasta/${b.arquivo}';
  }

  Future<void> carregar() async {
    if (!suportaDownload) return;
    try {
      _pasta = await pastaDownloads();
      final sp = await SharedPreferences.getInstance();
      modoOffline = sp.getBool('${_chave}_offline') ?? false;
      final txt = sp.getString(_chave);
      if (txt == null) return;
      final lista = jsonDecode(txt) as List;
      for (final e in lista) {
        final m = e as Map<String, dynamic>;
        final b = Baixada(Faixa.fromJson(m['faixa'] as Map<String, dynamic>),
            m['arquivo'] as String, (m['bytes'] as num).toInt());
        if (await arquivoExiste('$_pasta/${b.arquivo}')) {
          _baixadas[b.faixa.id] = b;
        }
      }
      notifyListeners();
    } catch (_) {
      // indice corrompido: comeca vazio
    }
  }

  Future<void> _salvar() async {
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _chave,
          jsonEncode(_baixadas.values
              .map((b) => {
                    'faixa': b.faixa.toJson(),
                    'arquivo': b.arquivo,
                    'bytes': b.bytes,
                  })
              .toList()));
    } catch (_) {}
  }

  Future<void> definirModoOffline(bool v) async {
    modoOffline = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('${_chave}_offline', v);
    } catch (_) {}
  }

  /// Poe varias faixas na fila. Devolve quantas realmente entraram.
  int baixarVarias(List<Faixa> faixas) {
    if (!suportaDownload) return 0;
    var n = 0;
    for (final f in faixas) {
      if (estaBaixada(f.id) || estaNaFila(f.id)) continue;
      _falhas.remove(f.id);
      motivoFalha.remove(f.id);
      _cancelados.remove(f.id);
      _fila.add(f);
      n++;
    }
    notifyListeners();
    _processar();
    return n;
  }

  void baixar(Faixa f) => baixarVarias([f]);

  void tentarNovamente() => baixarVarias(falhas);

  void limparFalhas() {
    _falhas.clear();
    motivoFalha.clear();
    notifyListeners();
  }

  void _processar() {
    while (_ativas.length < _maxSimultaneos && _fila.isNotEmpty) {
      final f = _fila.removeAt(0);
      _ativas[f.id] = f;
      _baixarUma(f);
    }
  }

  Future<void> _baixarUma(Faixa f) async {
    final arquivo = '${f.id}.mp3';
    try {
      _pasta ??= await pastaDownloads();
      final bytes = await baixarArquivo(
        urlAudio(f.id),
        '$_pasta/$arquivo',
        aoProgresso: (rec, total) {
          final novo = total == null ? null : rec / total;
          final antigo = _progresso[f.id];
          if (novo != null && (antigo == null || novo - antigo >= 0.02)) {
            _progresso[f.id] = novo;
            notifyListeners();
          }
        },
        cancelado: () => _cancelados.contains(f.id),
      );
      _baixadas.remove(f.id);
      final novas = {f.id: Baixada(f, arquivo, bytes), ..._baixadas};
      _baixadas
        ..clear()
        ..addAll(novas);
      await _salvar();
    } catch (e) {
      if (!_cancelados.contains(f.id)) {
        _falhas[f.id] = f;
        motivoFalha[f.id] = '$e';
      }
    } finally {
      _ativas.remove(f.id);
      _progresso.remove(f.id);
      _cancelados.remove(f.id);
      notifyListeners();
      _processar();
    }
  }

  void cancelar(String id) {
    final antes = _fila.length;
    _fila.removeWhere((f) => f.id == id);
    if (_fila.length == antes && _ativas.containsKey(id)) {
      _cancelados.add(id);
    }
    notifyListeners();
  }

  void cancelarTodos() {
    _fila.clear();
    _cancelados.addAll(_ativas.keys);
    notifyListeners();
  }

  Future<void> remover(String id) async {
    final c = caminho(id);
    _baixadas.remove(id);
    if (c != null) await apagarArquivo(c);
    await _salvar();
  }

  Future<void> removerTodas() async {
    final ids = _baixadas.keys.toList();
    for (final id in ids) {
      final c = caminho(id);
      _baixadas.remove(id);
      if (c != null) await apagarArquivo(c);
    }
    await _salvar();
  }
}

String formatarBytes(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
