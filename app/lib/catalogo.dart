import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'catalogo_local.dart';

class Genero {
  final String nome;
  final int artistas;
  final int faixas;
  Genero(this.nome, this.artistas, this.faixas);
  factory Genero.fromJson(Map<String, dynamic> j) =>
      Genero(j['nome'] as String, j['artistas'] as int, j['faixas'] as int);
}

class ArtistaResumo {
  final String id;
  final String nome;
  final String genero;
  final String? foto;
  final int faixas;
  ArtistaResumo(this.id, this.nome, this.genero, this.foto, this.faixas);
  factory ArtistaResumo.fromJson(Map<String, dynamic> j) => ArtistaResumo(
      j['id'] as String,
      j['nome'] as String,
      j['genero'] as String,
      j['foto'] as String?,
      j['faixas'] as int);
}

class Faixa {
  final String id; // id do arquivo no Drive
  final String titulo;
  final String artista;
  final String artistaId;
  final String? versao;
  final String? foto;
  Faixa(this.id, this.titulo, this.artista, this.artistaId, this.versao,
      this.foto);

  String get tituloCompleto => versao == null ? titulo : '$titulo ($versao)';

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'artista': artista,
        'artistaId': artistaId,
        'versao': versao,
        'foto': foto,
      };

  factory Faixa.fromJson(Map<String, dynamic> j) => Faixa(
      j['id'] as String,
      j['titulo'] as String,
      j['artista'] as String,
      (j['artistaId'] as String?) ?? '',
      j['versao'] as String?,
      j['foto'] as String?);
}

class Catalogo {
  final List<Genero> generos;
  final List<ArtistaResumo> artistas;
  Catalogo(this.generos, this.artistas);

  /// Catalogo carregado (usado para descobrir o genero de uma musica ao registrar o play).
  static Catalogo? atual;
  static bool _usandoLocal = true;
  Map<String, String>? _generoPorArtista;

  static String generoDe(String artistaId) {
    final c = atual;
    if (c == null || artistaId.isEmpty) return 'Outros';
    c._generoPorArtista ??= {for (final a in c.artistas) a.id: a.genero};
    return c._generoPorArtista![artistaId] ?? 'Outros';
  }

  // Indice de busca por musica: carregado so na primeira busca.
  List<_EntradaBusca>? _indiceFaixas;
  Map<String, ArtistaResumo>? _porId;

  static String _norm(String t) {
    const de = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
    const para = 'aaaaaaceeeeiiiinooooouuuuyy';
    final b = StringBuffer();
    for (final c in t.toLowerCase().split('')) {
      final i = de.indexOf(c);
      b.write(i >= 0 ? para[i] : c);
    }
    return b.toString();
  }

  /// Busca faixas pelo titulo (ou "titulo artista"), ignorando acentos.
  Future<List<Faixa>> buscarFaixas(String consulta, {int limite = 50}) async {
    if (_indiceFaixas == null) {
      final txt = await _ler('faixas_busca.json');
      _porId = {for (final a in artistas) a.id: a};
      _indiceFaixas = (jsonDecode(txt) as List).map((e) {
        final l = e as List;
        final art = _porId![l[3] as String];
        final titulo = l[1] as String;
        final versao = (l[2] as String).isEmpty ? null : l[2] as String;
        return _EntradaBusca(
            Faixa(l[0] as String, titulo, art?.nome ?? '', l[3] as String,
                versao, art?.foto),
            _norm('$titulo ${art?.nome ?? ''}'));
      }).toList();
    }
    final termos =
        _norm(consulta).split(' ').where((t) => t.isNotEmpty).toList();
    if (termos.isEmpty) return [];
    final r = <Faixa>[];
    for (final e in _indiceFaixas!) {
      if (termos.every(e.texto.contains)) {
        r.add(e.faixa);
        if (r.length >= limite) break;
      }
    }
    return r;
  }

  /// Le do catalogo baixado (se houver) e, se nao houver ou estiver ruim, do que veio no APK.
  static Future<String> _ler(String rel) async {
    final local = _usandoLocal ? await lerLocal(rel) : null;
    if (local != null) return local;
    return rootBundle.loadString('assets/catalogo/$rel');
  }

  static Future<Catalogo> carregar() async {
    Map<String, dynamic> j;
    try {
      final local = await lerLocal('indice.json');
      if (local == null) throw 'sem catalogo baixado';
      j = jsonDecode(local) as Map<String, dynamic>;
      _usandoLocal = true;
    } catch (_) {
      final txt = await rootBundle.loadString('assets/catalogo/indice.json');
      j = jsonDecode(txt) as Map<String, dynamic>;
      _usandoLocal = false;
    }
    return atual = Catalogo(
      (j['generos'] as List)
          .map((e) => Genero.fromJson(e as Map<String, dynamic>))
          .toList(),
      (j['artistas'] as List)
          .map((e) => ArtistaResumo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  List<ArtistaResumo> doGenero(String genero) =>
      artistas.where((a) => a.genero == genero).toList();

  Future<List<Faixa>> faixasDe(ArtistaResumo a) async {
    final txt = await _ler('artistas/${a.id}.json');
    final j = jsonDecode(txt) as Map<String, dynamic>;
    return (j['faixas'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      return Faixa(m['id'] as String, m['titulo'] as String, a.nome, a.id,
          m['versao'] as String?, a.foto);
    }).toList();
  }
}

class _EntradaBusca {
  final Faixa faixa;
  final String texto;
  _EntradaBusca(this.faixa, this.texto);
}
