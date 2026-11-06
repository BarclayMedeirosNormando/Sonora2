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
    _audio.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _terminou();
      notifyListeners();
    });
  }
  static final PlayerService instancia = PlayerService._();

  final AudioPlayer _audio = AudioPlayer();
  final Random _rng = Random();
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
    await tocarIndice(aleatorio ? _rng.nextInt(_fila.length) : indice);
  }

  Future<void> tocarIndice(int i) async {
    if (i < 0 || i >= _fila.length) return;
    _indice = i;
    erro = null;
    MinhaBiblioteca.i.registrarRecente(_fila[i]);
    _agendarTelemetria(_fila[i]);
    notifyListeners();
    try {
      final f = _fila[i];
      final item = MediaItem(
        id: f.id,
        title: f.tituloCompleto,
        artist: f.artista,
        artUri: (f.foto != null && f.foto!.startsWith('http'))
            ? Uri.parse(f.foto!)
            : null,
      );
      final local = DownloadService.i.caminho(f.id);
      if (local != null) {
        await _audio.setFilePath(local, tag: item);
      } else {
        final appId = await AcessoService.i.obterId();
        try {
          await _audio.setUrl(urlAudio(f.id, appId), tag: item);
        } catch (_) {
          // backend fora do ar ou aparelho nao liberado: tenta o link direto do Drive
          await _audio.setUrl(urlAudioDireto(f.id), tag: item);
        }
      }
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

  void _terminou() {
    if (repetir == 2) {
      tocarIndice(_indice);
    } else {
      proxima();
    }
  }

  Future<void> alternar() async {
    _audio.playing ? await _audio.pause() : _audio.play();
    notifyListeners();
  }

  Future<void> proxima() async {
    if (_fila.isEmpty) return;
    if (embaralhar && _fila.length > 1) {
      var n = _rng.nextInt(_fila.length);
      while (n == _indice) {
        n = _rng.nextInt(_fila.length);
      }
      await tocarIndice(n);
    } else if (_indice + 1 < _fila.length) {
      await tocarIndice(_indice + 1);
    } else if (repetir == 1) {
      await tocarIndice(0);
    }
  }

  Future<void> anterior() async {
    if ((await _audio.position).inSeconds > 3) {
      await _audio.seek(Duration.zero);
    } else if (_indice > 0) {
      await tocarIndice(_indice - 1);
    }
  }

  Future<void> ir(Duration d) => _audio.seek(d);

  void alternarEmbaralhar() {
    embaralhar = !embaralhar;
    notifyListeners();
  }

  void alternarRepetir() {
    repetir = (repetir + 1) % 3;
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
    notifyListeners();
  }

  /// Poe a musica no fim da fila.
  void adicionarNaFila(Faixa f) {
    if (_fila.isEmpty) {
      tocarLista([f], 0);
      return;
    }
    _fila.add(f);
    notifyListeners();
  }

  void reordenar(int de, int para) {
    if (de < 0 || de >= _fila.length) return;
    final atual = this.atual;
    if (para > de) para -= 1;
    final f = _fila.removeAt(de);
    _fila.insert(para, f);
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
