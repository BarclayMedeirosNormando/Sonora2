/// Endereco do backend do Sonora (Cloud Run) que serve o audio pela rota /midia.
/// Cole aqui a mesma URL usada no app Sonora atual (AppConstants.cloudRunBaseUrl),
/// sem barra no final. Ex.: 'https://sonora-backend-xxxxx-uc.a.run.app'
const String urlBackend = '';

/// De onde o audio e buscado. Sem backend configurado, tenta o link direto do
/// Drive (no navegador costuma falhar por CORS; no Android funciona).
String urlAudio(String fileId) => urlBackend.isEmpty
    ? 'https://drive.google.com/uc?export=download&id=$fileId'
    : '$urlBackend/midia/$fileId';

/// Endereco do Web App (Apps Script) que libera aparelhos e recebe o que foi ouvido,
/// o mesmo que termina em /exec. Deixe VAZIO para desligar o controle (o app abre para todos).
const String urlControle = 'https://script.google.com/macros/s/AKfycbyXh50EaxHMiVv4BqbFNcSZ0RmEztszXWt8LTZT_QJoLLKBgT62ffHmdxwEXaUEH17D/exec';

/// Versao mostrada na tela Inicio e enviada ao painel. Manter igual ao pubspec.yaml.
const String versaoApp = '0.7.2+9';
