// Acesso a arquivos do aparelho. No navegador (web) nao ha downloads offline,
// entao la usa-se uma versao vazia.
export 'armazenamento_stub.dart'
    if (dart.library.io) 'armazenamento_io.dart';
