/// Endereco do backend do Sonora (Cloud Run) que serve o audio pela rota /midia.
/// Cole aqui a mesma URL usada no app Sonora atual (AppConstants.cloudRunBaseUrl),
/// sem barra no final. Ex.: 'https://sonora-backend-xxxxx-uc.a.run.app'
const String urlBackend = '';

/// De onde o audio e buscado. Sem backend configurado, tenta o link direto do
/// Drive (no navegador costuma falhar por CORS; no Android funciona).
String urlAudio(String fileId) => urlBackend.isEmpty
    ? 'https://drive.google.com/uc?export=download&id=$fileId'
    : '$urlBackend/midia/$fileId';
