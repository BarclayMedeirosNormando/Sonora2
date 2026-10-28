# Atualiza o catalogo do Sonora com as musicas novas, em um comando so:
#   powershell -ExecutionPolicy Bypass -File .\atualizar_musicas.ps1
# Uso: .\atualizar_musicas.ps1            (normal)
#      .\atualizar_musicas.ps1 -RefazerFotos   (tenta de novo artistas sem foto, se a rede falhou)
param([switch]$RefazerFotos)
$ErrorActionPreference = 'Stop'
$extra = @()
if ($RefazerFotos) { $extra = @('--refazer-falhas') }
$raiz = $PSScriptRoot
. (Join-Path $raiz 'config_local.ps1')
$base = 'https://sonora-backend-99445390129.us-central1.run.app'
$pasta = Join-Path $raiz 'etapa1_nomes'

Write-Host '1/5 Lendo a biblioteca no Drive (gerar cache)...'
try {
    $r = Invoke-RestMethod "$base/gerar-cache?chave=$ChaveGerarCache" -TimeoutSec 1800
} catch {
    throw "Nao consegui gerar o cache. Chave errada em config_local.ps1? ($($_.Exception.Message))"
}
if (-not $r.ok) { throw "gerar-cache respondeu erro: $($r | ConvertTo-Json -Compress)" }
Write-Host ("    {0} albuns, {1} faixas" -f $r.totalAlbuns, $r.totalFaixas)

Write-Host '2/5 Baixando o cache...'
$novo = Join-Path $pasta 'cache_novo.json'
Invoke-WebRequest "$base/cache?appId=$AppIdCache" -OutFile $novo -UseBasicParsing -TimeoutSec 600
$cab = (Get-Content $novo -TotalCount 1 -Encoding UTF8)
if ($cab.Length -gt 400) { $cab = $cab.Substring(0, 400) }
if ($cab -notmatch '"geradoEm"') { throw 'O arquivo baixado nao parece um cache valido (AppIdCache liberado?).' }
$atual = Join-Path $pasta 'cache.json'
if (Test-Path $atual) { Copy-Item $atual (Join-Path $pasta 'cache_anterior.json') -Force }
Move-Item $novo $atual -Force

Set-Location $pasta
Write-Host '3/5 Identificando artistas, generos e fotos (precisa de internet)...'
py atualizar.py cache.json --max-artistas 1000 @extra
if ($LASTEXITCODE -ne 0) { throw 'atualizar.py falhou' }

Write-Host '4/5 Gerando o catalogo...'
py exportar.py
if ($LASTEXITCODE -ne 0) { throw 'exportar.py falhou' }

Write-Host '5/5 Guardando o catalogo.zip...'
$zip = Join-Path $pasta 'saida\catalogo.zip'
$versao = Get-Date -Format 'yyyy-MM-dd_HHmm'
$hist = Join-Path $raiz 'catalogos'
New-Item -ItemType Directory -Force -Path $hist | Out-Null
Copy-Item $zip (Join-Path $hist "catalogo-$versao.zip") -Force
if ($PastaDrive -and (Test-Path $PastaDrive)) {
    Copy-Item $zip (Join-Path $PastaDrive 'catalogo.zip') -Force
    Write-Host ''
    Write-Host "PRONTO. catalogo.zip copiado para $PastaDrive (o Drive sobe sozinho)."
    Write-Host 'Os aparelhos recebem o catalogo novo ao abrir o app, se o painel estiver em versao automatica.'
} else {
    Write-Host ''
    Write-Host "PRONTO. Suba este arquivo no Drive (substituindo o catalogo.zip, via Gerenciar versoes):"
    Write-Host "  $hist\catalogo-$versao.zip"
    explorer.exe $hist
}
