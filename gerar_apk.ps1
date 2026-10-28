# Gera o APK release e copia para apks\<versao>\sonora-<versao>.apk
$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
$app = Join-Path $raiz 'app'
$linha = Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
$versao = $linha.Matches[0].Groups[1].Value
Set-Location $app
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build falhou' }
$destino = Join-Path $raiz "apks\$versao"
New-Item -ItemType Directory -Force -Path $destino | Out-Null
$arq = Join-Path $destino "sonora-$versao.apk"
Copy-Item (Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk') $arq -Force
Write-Host "APK pronto: $arq"
explorer.exe $destino
