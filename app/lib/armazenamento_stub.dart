const bool suportaDownload = false;

Future<String> pastaDownloads() async => throw UnsupportedError('web');
Future<bool> arquivoExiste(String caminho) async => false;
Future<void> apagarArquivo(String caminho) async {}
Future<int> baixarArquivo(
  String url,
  String destino, {
  required void Function(int recebidos, int? total) aoProgresso,
  required bool Function() cancelado,
}) async =>
    throw UnsupportedError('Downloads so funcionam no app do celular.');
