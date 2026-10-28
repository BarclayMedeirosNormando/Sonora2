# Atualiza o catalogo depois de colocar musicas novas no Drive.
# Pre-requisito: etapa1_nomes\cache.json ja atualizado (gerado pelo /gerar-cache).
$ErrorActionPreference = 'Stop'
$pasta = Join-Path $PSScriptRoot 'etapa1_nomes'
Set-Location $pasta
py atualizar.py cache.json
if ($LASTEXITCODE -ne 0) { throw 'atualizar.py falhou' }
py exportar.py
if ($LASTEXITCODE -ne 0) { throw 'exportar.py falhou' }
$versao = Get-Date -Format 'yyyy-MM-dd_HHmm'
$destino = Join-Path $PSScriptRoot 'catalogos'
New-Item -ItemType Directory -Force -Path $destino | Out-Null
$arq = Join-Path $destino "catalogo-$versao.zip"
Copy-Item (Join-Path $pasta 'saida\catalogo.zip') $arq -Force
Write-Host ''
Write-Host "Catalogo pronto: $arq"
Write-Host "Versao para o painel: $versao"
Write-Host 'Agora: suba o zip no Drive, copie o link e publique no painel (card "Catalogo de musicas").'
explorer.exe $destino
