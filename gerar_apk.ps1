# Gera o APK release e copia para apks\<versao>\sonora-<versao>.apk
#   .\gerar_apk.ps1              -> so gera o APK
#   .\gerar_apk.ps1 -Publicar    -> gera, copia para o Drive (sonora.apk), espera sincronizar e avisa os aparelhos
#   -Espera 180                  -> segundos de espera do Drive antes de publicar (padrao 120)
param([switch]$Publicar, [int]$Espera = 120)
$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
. (Join-Path $raiz 'config_local.ps1')
$app = Join-Path $raiz 'app'
if (-not (Test-Path (Join-Path $app 'assets\catalogo\indice.json'))) {
    throw 'Falta o catalogo dentro do app. Rode primeiro: .\atualizar_musicas.ps1'
}
$linha = Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
$versao = $linha.Matches[0].Groups[1].Value
$cfg = Select-String -Path (Join-Path $app 'lib\config.dart') -Pattern "versaoApp\s*=\s*'([^']+)'" | Select-Object -First 1
if ($cfg -and $cfg.Matches[0].Groups[1].Value -ne $versao) {
    throw "Versao diferente: pubspec.yaml=$versao e config.dart=$($cfg.Matches[0].Groups[1].Value). Deixe as duas iguais."
}
Set-Location $app
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build falhou' }
$destino = Join-Path $raiz "apks\$versao"
New-Item -ItemType Directory -Force -Path $destino | Out-Null
$arq = Join-Path $destino "sonora-$versao.apk"
Copy-Item (Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk') $arq -Force
Write-Host "APK pronto: $arq"

if (-not $Publicar) { explorer.exe $destino; return }

if (-not $PastaDrive -or -not (Test-Path $PastaDrive)) { throw 'PastaDrive nao existe no config_local.ps1' }
if (-not $UrlControle -or -not $ChavePainel) { throw 'Faltam $UrlControle e $ChavePainel no config_local.ps1 (veja o LEIA-ME)' }
# nome fixo: o Drive troca o conteudo e o link publicado no painel continua o mesmo
Copy-Item $arq (Join-Path $PastaDrive 'sonora.apk') -Force
Write-Host "Copiado para $PastaDrive\sonora.apk. Esperando $Espera s o Drive sincronizar..."
Start-Sleep -Seconds $Espera
$corpo = @{ action = 'publicar_apk'; chave = $ChavePainel; versao = $versao } | ConvertTo-Json -Compress
$r = Invoke-RestMethod -Uri $UrlControle -Method Post -Body $corpo -ContentType 'application/json' -TimeoutSec 60
if (-not $r.ok) { throw "O painel recusou: $($r | ConvertTo-Json -Compress)" }
Write-Host "PUBLICADO: versao $versao. Os aparelhos antigos vao avisar ao abrir o app."
