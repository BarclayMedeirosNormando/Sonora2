# Rode no computador NOVO, depois de clonar o repositorio e instalar Flutter/Python.
# Uso: .\restaurar_no_novo_pc.ps1 -Zip "D:\Sonora2_backup_pc.zip"
param([Parameter(Mandatory = $true)][string]$Zip)
$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
$tmp = Join-Path $env:TEMP 'sonora2_restaurar'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive -Path $Zip -DestinationPath $tmp

$ks = Join-Path $tmp 'debug.keystore'
if (Test-Path $ks) {
    $dest = Join-Path $env:USERPROFILE '.android'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $alvo = Join-Path $dest 'debug.keystore'
    if (Test-Path $alvo) { Copy-Item $alvo "$alvo.bak-$(Get-Date -Format yyyyMMdd_HHmm)" }
    Copy-Item $ks $alvo -Force
    Write-Host 'ok   chave de assinatura (debug.keystore) restaurada'
}
$cfg = Join-Path $tmp 'config_local.ps1'
if (Test-Path $cfg) { Copy-Item $cfg (Join-Path $raiz 'config_local.ps1') -Force; Write-Host 'ok   config_local.ps1' }
$art = Join-Path $tmp 'artistas.json'
if (Test-Path $art) {
    $d = Join-Path $raiz 'etapa1_nomes\saida'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Copy-Item $art (Join-Path $d 'artistas.json') -Force
    Write-Host 'ok   artistas.json (fotos e generos ja buscados)'
}
Write-Host ''
Write-Host 'Edite config_local.ps1 se o caminho do Google Drive (G:) for diferente neste PC.'
