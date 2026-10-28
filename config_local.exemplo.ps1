# Copie este arquivo para config_local.ps1 e preencha. O config_local.ps1 NAO vai para o Git.

# Chave do /gerar-cache do backend antigo (Cloud Run). Fica em Cloud Run > sonora-backend > variavel GERAR_CACHE_CHAVE
$ChaveGerarCache = 'COLE_A_CHAVE_AQUI'

# ID de um aparelho LIBERADO na planilha Log_Acesso_Sonora (serve para baixar o cache)
$AppIdCache = 'COLE_UM_ID_LIBERADO'

# Pasta do "Google Drive para computador" onde o catalogo.zip deve ficar (sobe sozinho).
# Deixe '' se nao usa; entao o zip so e salvo em catalogos\ e voce sobe manualmente.
$PastaDrive = ''
