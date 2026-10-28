const bool suportaInstalar = false;

Future<void> instalarApk(String url,
        void Function(String msg, double? progresso, bool erro) estado) async =>
    estado('Atualização só funciona no app do celular.', null, true);
