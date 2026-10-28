const bool suportaCatalogoRemoto = false;

Future<String?> lerLocal(String rel) async => null;
Future<String> versaoLocal() async => '';
Future<void> baixarEInstalarCatalogo(
        String url, String versao, void Function(double? progresso) aoProgresso) async =>
    throw UnsupportedError('Catálogo remoto só funciona no app do celular.');
