import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

enum EstadoAcesso { liberado, aguardando, bloqueado, semConexao }

/// Libera ou nega o uso do app por aparelho. Cada aparelho gera um ID no primeiro uso;
/// voce libera esse ID no painel. A resposta "Liberado" fica guardada no celular, entao
/// o app continua funcionando offline e nao pergunta a cada abertura.
class AcessoService {
  AcessoService._();
  static final AcessoService i = AcessoService._();

  static const _kId = 'sonora2_app_id';
  static const _kNome = 'sonora2_nome';
  static const _kStatus = 'sonora2_acesso_status';
  static const _kQuando = 'sonora2_acesso_quando';
  static const _kVersao = 'sonora2_versao_validada';
  static const _revalidarApos = Duration(hours: 12);
  static const _toleranciaOffline = Duration(days: 14);

  EstadoAcesso estado = EstadoAcesso.liberado;
  String? _id;

  bool get controleLigado => urlControle.isNotEmpty;

  Future<String> obterId() async {
    if (_id != null) return _id!;
    final sp = await SharedPreferences.getInstance();
    var id = sp.getString(_kId);
    if (id == null || id.length < 8) {
      final r = Random.secure();
      final h = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
      id = '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
          '${h.substring(16, 20)}-${h.substring(20)}';
      await sp.setString(_kId, id);
    }
    return _id = id;
  }

  Future<String> nomeSalvo() async =>
      (await SharedPreferences.getInstance()).getString(_kNome) ?? '';

  Future<void> salvarNome(String nome) async =>
      (await SharedPreferences.getInstance()).setString(_kNome, nome.trim());

  EstadoAcesso _de(String? s) => switch (s) {
        'Liberado' => EstadoAcesso.liberado,
        'Bloqueado' => EstadoAcesso.bloqueado,
        _ => EstadoAcesso.aguardando,
      };

  /// Anota um status recebido do servidor (ex.: bloqueado no meio do uso).
  Future<void> registrarStatus(String status) async {
    estado = _de(status);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kStatus, status);
    await sp.setInt(_kQuando, DateTime.now().millisecondsSinceEpoch);
  }

  /// [forcar] ignora o que ficou guardado e pergunta ao servidor.
  Future<EstadoAcesso> validar({bool forcar = false}) async {
    if (!controleLigado) return estado = EstadoAcesso.liberado;
    final sp = await SharedPreferences.getInstance();
    final id = await obterId();
    final guardado = sp.getString(_kStatus);
    final quando = sp.getInt(_kQuando) ?? 0;
    final idade = DateTime.now().millisecondsSinceEpoch - quando;

    final versaoMudou = sp.getString(_kVersao) != versaoApp;
    if (!forcar &&
        !versaoMudou &&
        guardado == 'Liberado' &&
        idade < _revalidarApos.inMilliseconds) {
      return estado = EstadoAcesso.liberado;
    }
    try {
      final nome = sp.getString(_kNome) ?? '';
      final uri = Uri.parse(urlControle).replace(queryParameters: {
        'action': 'validar',
        'id': id,
        'versao': versaoApp,
        'plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
        if (nome.isNotEmpty) 'nome': nome,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 20));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['ok'] != true) throw Exception(j['erro'] ?? 'resposta invalida');
      await registrarStatus(j['status'] as String? ?? 'Aguardando');
      await sp.setString(_kVersao, versaoApp);
      return estado;
    } catch (_) {
      // sem internet: mantem o acesso se ja foi liberado ha menos de 14 dias
      if (guardado == 'Liberado' && idade < _toleranciaOffline.inMilliseconds) {
        return estado = EstadoAcesso.liberado;
      }
      return estado = EstadoAcesso.semConexao;
    }
  }
}
