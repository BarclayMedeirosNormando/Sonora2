import 'dart:io';
import 'package:path_provider/path_provider.dart';

const bool suportaDownload = true;

/// Pasta privada do app onde ficam as musicas baixadas.
Future<String> pastaDownloads() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory('${base.path}${Platform.pathSeparator}musicas');
  if (!await d.exists()) await d.create(recursive: true);
  return d.path;
}

Future<bool> arquivoExiste(String caminho) => File(caminho).exists();

Future<void> apagarArquivo(String caminho) async {
  try {
    final f = File(caminho);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// Baixa [url] para [destino] (grava em .part e renomeia no fim, para nunca
/// deixar um arquivo pela metade). Devolve o tamanho em bytes.
Future<int> baixarArquivo(
  String url,
  String destino, {
  required void Function(int recebidos, int? total) aoProgresso,
  required bool Function() cancelado,
}) async {
  final cli = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final tmp = File('$destino.part');
  try {
    final req = await cli.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) throw 'Erro HTTP ${resp.statusCode}';
    final tipo = resp.headers.contentType?.mimeType ?? '';
    if (tipo.contains('text/html')) {
      throw 'O Drive devolveu uma pagina em vez do audio '
          '(arquivo muito grande ou sem permissao)';
    }
    final total = resp.contentLength > 0 ? resp.contentLength : null;
    var recebidos = 0;
    final sink = tmp.openWrite();
    try {
      await for (final bloco in resp) {
        if (cancelado()) throw 'cancelado';
        sink.add(bloco);
        recebidos += bloco.length;
        aoProgresso(recebidos, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (recebidos == 0) throw 'arquivo vazio';
    await tmp.rename(destino);
    return recebidos;
  } catch (e) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    rethrow;
  } finally {
    cli.close(force: true);
  }
}
