# Junta o que NAO esta no GitHub e e preciso para trabalhar em outro computador.
# Gera Sonora2_backup_pc.zip na sua Area de Trabalho. Leve por pen drive (NAO suba em lugar publico).
$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
$tmp = Join-Path $env:TEMP 'sonora2_backup'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null

$itens = @(
    @{ origem = Join-Path $env:USERPROFILE '.android\debug.keystore'; nome = 'debug.keystore' },
    @{ origem = Join-Path $raiz 'config_local.ps1'; nome = 'config_local.ps1' },
    @{ origem = Join-Path $raiz 'etapa1_nomes\saida\artistas.json'; nome = 'artistas.json' }
)
foreach ($i in $itens) {
    if (Test-Path $i.origem) { Copy-Item $i.origem (Join-Path $tmp $i.nome); Write-Host "ok   $($i.nome)" }
    else { Write-Host "FALTA $($i.origem)" -ForegroundColor Yellow }
}
$zip = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Sonora2_backup_pc.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip
Write-Host ''
Write-Host "Pronto: $zip"
Write-Host 'Atencao: contem a chave de assinatura do app e a chave do cache. Guarde so com voce.'
