import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'armazenamento_io.dart' show baixarArquivo;

const bool suportaCatalogoRemoto = true;

Future<Directory> _base() async {
  final d = await getApplicationDocumentsDirectory();
  return Directory('${d.path}/catalogo_remoto');
}

/// Le um arquivo do catalogo baixado (ex.: 'indice.json'); null se nao houver catalogo baixado.
Future<String?> lerLocal(String rel) async {
  try {
    final f = File('${(await _base()).path}/atual/$rel');
    if (await f.exists()) return await f.readAsString();
  } catch (_) {}
  return null;
}

Future<String> versaoLocal() async {
  try {
    final f = File('${(await _base()).path}/versao.txt');
    if (await f.exists()) return (await f.readAsString()).trim();
  } catch (_) {}
  return '';
}

/// Baixa o catalogo.zip, descompacta numa pasta nova e so entao troca pela atual,
/// para nunca ficar com um catalogo pela metade.
Future<void> baixarEInstalarCatalogo(
    String url, String versao, void Function(double? progresso) aoProgresso) async {
  final base = await _base();
  await base.create(recursive: true);
  final zip = '${base.path}/catalogo.zip';
  await baixarArquivo(url, zip,
      aoProgresso: (r, t) => aoProgresso(t == null || t == 0 ? null : r / t),
      cancelado: () => false);
  final novo = Directory('${base.path}/novo');
  if (await novo.exists()) await novo.delete(recursive: true);
  await novo.create();
  await extractFileToDisk(zip, novo.path);
  if (!await File('${novo.path}/indice.json').exists()) {
    await novo.delete(recursive: true);
    throw 'Arquivo de catálogo inválido (sem indice.json).';
  }
  final atual = Directory('${base.path}/atual');
  if (await atual.exists()) await atual.delete(recursive: true);
  await novo.rename(atual.path);
  await File('${base.path}/versao.txt').writeAsString(versao);
  try {
    await File(zip).delete();
  } catch (_) {}
}
