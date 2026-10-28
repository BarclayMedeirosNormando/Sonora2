import 'dart:async';
import 'dart:io' show Platform;
import 'package:ota_update/ota_update.dart';

bool get suportaInstalar => Platform.isAndroid;

/// Baixa o APK e abre o instalador do Android. [estado] recebe texto, progresso (0 a 1) e se deu erro.
Future<void> instalarApk(String url,
    void Function(String msg, double? progresso, bool erro) estado) async {
  final fim = Completer<void>();
  try {
    OtaUpdate()
        .execute(url, destinationFilename: 'sonora_update.apk')
        .listen((e) {
      switch (e.status) {
        case OtaStatus.DOWNLOADING:
          final p = double.tryParse(e.value ?? '');
          estado('Baixando… ${e.value ?? ''}%', p == null ? null : p / 100, false);
        case OtaStatus.INSTALLING:
          estado('Abrindo o instalador…', 1, false);
        case OtaStatus.INSTALLATION_DONE:
          estado('Instalado.', 1, false);
        case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
          estado(
              'Permita "Instalar apps desconhecidos" para o Sonora nas configurações do Android e tente de novo.',
              null,
              true);
        case OtaStatus.ALREADY_RUNNING_ERROR:
          estado('Já existe uma atualização em andamento.', null, true);
        case OtaStatus.CANCELED:
          estado('Cancelado.', null, true);
        default:
          estado('Falha na atualização (${e.status.name}). ${e.value ?? ''}', null, true);
      }
    }, onError: (Object err) {
      estado('Falha na atualização: $err', null, true);
    }, onDone: () {
      if (!fim.isCompleted) fim.complete();
    });
  } catch (err) {
    estado('Falha na atualização: $err', null, true);
    return;
  }
  await fim.future;
}
