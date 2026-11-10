import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'acesso.dart';
import 'biblioteca_usuario.dart';
import 'catalogo.dart';
import 'config.dart';
import 'downloads.dart';
import 'telemetria.dart';

/// Player unico do app: fila, tocar/pausar, proxima/anterior, embaralhar,
/// repetir e timer para dormir.
class PlayerService extends ChangeNotifier {
  PlayerService._() {
    _audio.playerStateStream.listen((_) => notifyListeners());
    // Quem troca de faixa e o player nativo (lista gapless): continua funcionando
    // com a tela apagada, mesmo se o Android suspender o codigo Dart.
    _audio.currentIndexStream.listen(_mudouIndice);
    _audio.playbackEventStream.listen((_) {}, onError: _erroNativo);
  }
  static final PlayerService instancia = PlayerService._();

  final AudioPlayer _audio = AudioPlayer();
  final Random _rng = Random();
  ConcatenatingAudioSource _fonte = ConcatenatingAudioSource(children: []);
  String _appId = '';
  String? _marcado; // faixa ja registrada como recente/telemetria
  final Set<String> _direto = {}; // faixas que ja cairam para o link direto do Drive
  List<Faixa> _fila = [];
  int _indice = -1;
  bool embaralhar = false;
  int repetir = 0; // 0 = nao, 1 = fila toda, 2 = uma faixa
  String? erro;
  Timer? _sono;
  Timer? _telemetria;
  DateTime? sonoAte;

  List<Faixa> get fila => List.unmodifiable(_fila);
  int get indice => _indice;
  Faixa? get atual =>
      (_indice >= 0 && _indice < _fila.length) ? _fila[_indice] : null;
  bool get tocando => _audio.playing;
  Stream<Duration> get posicao => _audio.positionStream;
  Stream<Duration?> get duracao => _audio.durationStream;

  Future<void> tocarLista(List<Faixa> lista, int indice,
      {bool aleatorio = false}) async {
    if (lista.isEmpty) return;
    final dl = DownloadService.i;
    if (dl.modoOffline) {
      // Modo offline: so entram na fila as musicas ja baixadas.
      final alvo = indice < lista.length ? lista[indice] : null;
      final baixadas = lista.where((f) => dl.estaBaixada(f.id)).toList();
      if (baixadas.isEmpty) {
        erro = 'Modo offline: nenhuma dessas músicas está baixada.';
        notifyListeners();
        return;
      }
      final novo =
          alvo == null ? -1 : baixadas.indexWhere((f) => f.id == alvo.id);
      lista = baixadas;
      indice = novo < 0 ? 0 : novo;
    }
    _fila = List.of(lista);
    embaralhar = aleatorio;
    erro = null;
    _marcado = null;
    _direto.clear();
    final alvo = aleatorio ? _rng.nextInt(_fila.length) : indice;
    _indice = alvo;
    _marcarInicio(_fila[alvo]);
    notifyListeners();
    try {
      _appId = await AcessoService.i.obterId();
      _fonte = ConcatenatingAudioSource(children: [for (final f in _fila) _fonteDe(f)]);
      await _audio.setLoopMode(_modoRepetir());
      await _audio.setShuffleModeEnabled(embaralhar);
      await _audio.setAudioSource(_fonte,
          initialIndex: alvo, initialPosition: Duration.zero);
      if (embaralhar) await _audio.shuffle();
      _audio.play();
    } catch (e) {
      erro = 'Nao foi possivel tocar: $e';
    }
    notifyListeners();
  }

  AudioSource _fonteDe(Faixa f, {bool direto = false}) {
    final item = MediaItem(
      id: f.id,
      title: f.tituloCompleto,
      artist: f.artista,
      artUri: (f.foto != null && f.foto!.startsWith('http'))
          ? Uri.parse(f.foto!)
          : null,
    );
    final local = DownloadService.i.caminho(f.id);
    if (local != null) return AudioSource.file(local, tag: item);
    final url = direto ? urlAudioDireto(f.id) : urlAudio(f.id, _appId);
    return AudioSource.uri(Uri.parse(url), tag: item);
  }

  LoopMode _modoRepetir() => switch (repetir) {
        1 => LoopMode.all,
        2 => LoopMode.one,
        _ => LoopMode.off,
      };

  void _marcarInicio(Faixa f) {
    if (_marcado == f.id) return;
    _marcado = f.id;
    MinhaBiblioteca.i.registrarRecente(f);
    _agendarTelemetria(f);
  }

  void _mudouIndice(int? i) {
    if (i == null || i < 0 || i >= _fila.length) return;
    _indice = i;
    erro = null;
    _marcarInicio(_fila[i]);
    notifyListeners();
  }

  /// Falha ao abrir uma faixa: tenta uma vez o link direto do Drive; senao pula.
  void _erroNativo(Object e, StackTrace st) {
    final i = _audio.currentIndex; // PlayerException nao informa o indice; a faixa com erro e a atual
    if (i != null && i >= 0 && i < _fila.length && _direto.add(_fila[i].id)) {
      _trocarPorDireto(i);
      return;
    }
    erro = 'Nao foi possivel tocar: $e';
    notifyListeners();
    if (_audio.hasNext) _audio.seekToNext();
  }

  Future<void> _trocarPorDireto(int i) async {
    try {
      await _fonte.removeAt(i);
      await _fonte.insert(i, _fonteDe(_fila[i], direto: true));
      await _audio.seek(Duration.zero, index: i);
      _audio.play();
    } catch (e) {
      erro = 'Nao foi possivel tocar: $e';
      notifyListeners();
    }
  }

  Future<void> tocarIndice(int i) async {
    if (i < 0 || i >= _fila.length) return;
    erro = null;
    try {
      await _audio.seek(Duration.zero, index: i);
      _audio.play();
    } catch (e) {
      erro = 'Nao foi possivel tocar: $e';
    }
    notifyListeners();
  }

  /// So conta como "ouvida" depois de 8 segundos na mesma musica (pular rapido nao conta).
  void _agendarTelemetria(Faixa f) {
    _telemetria?.cancel();
    _telemetria = Timer(const Duration(seconds: 8), () {
      if (atual?.id == f.id && _audio.playing) {
        TelemetriaService.i.registrarPlay(f, Catalogo.generoDe(f.artistaId));
      }
    });
  }

  Future<void> alternar() async {
    _audio.playing ? await _audio.pause() : _audio.play();
    notifyListeners();
  }

  Future<void> proxima() async {
    if (_fila.isEmpty) return;
    await _audio.seekToNext();
    if (!_audio.playing) _audio.play();
  }

  Future<void> anterior() async {
    if ((await _audio.position).inSeconds > 3) {
      await _audio.seek(Duration.zero);
    } else {
      await _audio.seekToPrevious();
    }
  }

  Future<void> ir(Duration d) => _audio.seek(d);

  void alternarEmbaralhar() {
    embaralhar = !embaralhar;
    _audio.setShuffleModeEnabled(embaralhar);
    if (embaralhar) _audio.shuffle();
    notifyListeners();
  }

  void alternarRepetir() {
    repetir = (repetir + 1) % 3;
    _audio.setLoopMode(_modoRepetir());
    notifyListeners();
  }

  /// Poe a musica logo depois da que esta tocando (com embaralhar ligado a ordem e aleatoria).
  void tocarAProxima(Faixa f) {
    if (_fila.isEmpty) {
      tocarLista([f], 0);
      return;
    }
    final pos = _indice + 1 > _fila.length ? _fila.length : _indice + 1;
    _fila.insert(pos, f);
    _fonte.insert(pos, _fonteDe(f));
    notifyListeners();
  }

  /// Poe a musica no fim da fila.
  void adicionarNaFila(Faixa f) {
    if (_fila.isEmpty) {
      tocarLista([f], 0);
      return;
    }
    _fila.add(f);
    _fonte.add(_fonteDe(f));
    notifyListeners();
  }

  void reordenar(int de, int para) {
    if (de < 0 || de >= _fila.length) return;
    final atual = this.atual;
    if (para > de) para -= 1;
    final f = _fila.removeAt(de);
    _fila.insert(para, f);
    _fonte.move(de, para);
    if (atual != null) _indice = _fila.indexOf(atual);
    notifyListeners();
  }

  /// Timer para dormir: pausa a musica depois de [d]. null cancela.
  void agendarSono(Duration? d) {
    _sono?.cancel();
    _sono = null;
    sonoAte = null;
    if (d != null) {
      sonoAte = DateTime.now().add(d);
      _sono = Timer(d, () {
        _audio.pause();
        sonoAte = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }
}
