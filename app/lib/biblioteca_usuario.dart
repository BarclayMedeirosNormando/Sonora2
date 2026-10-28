import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalogo.dart';

class Playlist {
  final String id;
  String nome;
  final List<Faixa> faixas;
  Playlist(this.id, this.nome, this.faixas);

  Map<String, dynamic> toJson() =>
      {'id': id, 'nome': nome, 'faixas': faixas.map((f) => f.toJson()).toList()};

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
      j['id'] as String,
      j['nome'] as String,
      (j['faixas'] as List)
          .map((e) => Faixa.fromJson(e as Map<String, dynamic>))
          .toList());
}

/// Dados do usuario guardados no aparelho: favoritas, playlists e recentes.
class MinhaBiblioteca extends ChangeNotifier {
  MinhaBiblioteca._();
  static final MinhaBiblioteca i = MinhaBiblioteca._();

  static const _chave = 'sonora_usuario_v1';
  final List<Faixa> favoritos = [];
  final List<Playlist> playlists = [];
  final List<Faixa> recentes = [];

  Future<void> carregar() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final txt = sp.getString(_chave);
      if (txt == null) return;
      final j = jsonDecode(txt) as Map<String, dynamic>;
      favoritos
        ..clear()
        ..addAll((j['favoritos'] as List? ?? [])
            .map((e) => Faixa.fromJson(e as Map<String, dynamic>)));
      playlists
        ..clear()
        ..addAll((j['playlists'] as List? ?? [])
            .map((e) => Playlist.fromJson(e as Map<String, dynamic>)));
      recentes
        ..clear()
        ..addAll((j['recentes'] as List? ?? [])
            .map((e) => Faixa.fromJson(e as Map<String, dynamic>)));
    } catch (_) {
      // dados corrompidos: comeca vazio
    }
  }

  Future<void> _salvar() async {
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _chave,
          jsonEncode({
            'favoritos': favoritos.map((f) => f.toJson()).toList(),
            'playlists': playlists.map((p) => p.toJson()).toList(),
            'recentes': recentes.map((f) => f.toJson()).toList(),
          }));
    } catch (_) {}
  }

  bool ehFavorito(String id) => favoritos.any((f) => f.id == id);

  void alternarFavorito(Faixa f) {
    if (ehFavorito(f.id)) {
      favoritos.removeWhere((x) => x.id == f.id);
    } else {
      favoritos.insert(0, f);
    }
    _salvar();
  }

  void registrarRecente(Faixa f) {
    recentes.removeWhere((x) => x.id == f.id);
    recentes.insert(0, f);
    if (recentes.length > 20) recentes.removeRange(20, recentes.length);
    _salvar();
  }

  Playlist criarPlaylist(String nome) {
    final p = Playlist(DateTime.now().microsecondsSinceEpoch.toString(),
        nome.trim().isEmpty ? 'Minha playlist' : nome.trim(), []);
    playlists.insert(0, p);
    _salvar();
    return p;
  }

  void renomear(Playlist p, String nome) {
    if (nome.trim().isEmpty) return;
    p.nome = nome.trim();
    _salvar();
  }

  void excluir(Playlist p) {
    playlists.removeWhere((x) => x.id == p.id);
    _salvar();
  }

  bool estaNa(Playlist p, String faixaId) => p.faixas.any((f) => f.id == faixaId);

  void alternarNaPlaylist(Playlist p, Faixa f) {
    if (estaNa(p, f.id)) {
      p.faixas.removeWhere((x) => x.id == f.id);
    } else {
      p.faixas.add(f);
    }
    _salvar();
  }

  void removerDaPlaylist(Playlist p, Faixa f) {
    p.faixas.removeWhere((x) => x.id == f.id);
    _salvar();
  }
}
