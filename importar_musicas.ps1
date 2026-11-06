# Entrada -> biblioteca -> catalogo, em um comando so (pergunta antes de cada passo importante):
#   powershell -ExecutionPolicy Bypass -File .\importar_musicas.ps1
#   .\importar_musicas.ps1                      (usa as pastas padrao)
#   .\importar_musicas.ps1 -Entrada "G:\...\Entrada" -Destino "G:\...\Sonora_Musicas"
#   .\importar_musicas.ps1 -SemCatalogo         (nao atualiza o catalogo no fim)
#
# Passos: 1) renomear (opcional: todos do mesmo cantor/banda)  2) plano do organizar (nao move nada)
#         3) voce confirma e ele transfere  4) atualiza o catalogo (depois do Drive sincronizar)
param(
    [string]$Entrada = 'G:\Meu Drive\Musicas\Entrada',
    [string]$Destino = 'G:\Meu Drive\Musicas\Sonora_Musicas',
    [switch]$SemCatalogo
)
$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
Set-Location $raiz

function Perguntar($texto, $padraoSim) {
    $suf = if ($padraoSim) { '(S/n)' } else { '(s/N)' }
    $r = (Read-Host "$texto $suf").Trim().ToLower()
    if ($r -eq '') { return $padraoSim }
    return ($r -eq 's' -or $r -eq 'sim')
}

if (-not (Test-Path -LiteralPath $Entrada)) { throw "Pasta Entrada nao encontrada: $Entrada (o Google Drive para computador esta aberto?)" }
if (-not (Test-Path -LiteralPath $Destino)) { throw "Pasta da biblioteca nao encontrada: $Destino" }

$ext = '.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.aac'
$arquivos = @(Get-ChildItem -LiteralPath $Entrada -File -Recurse | Where-Object { $ext -contains $_.Extension.ToLower() })
if ($arquivos.Count -eq 0) { Write-Host "Nenhuma musica em $Entrada. Nada a fazer."; return }
Write-Host ("{0} musicas na Entrada." -f $arquivos.Count)

# 1) renomear (opcional)
Write-Host ''
if (Perguntar 'Todas essas musicas sao do MESMO cantor/banda e precisam ser renomeadas?' $false) {
    py renomear_manual.py $Entrada
    if ($LASTEXITCODE -ne 0) { Write-Host 'Renomear cancelado; seguindo sem renomear.' }
}

# 2) plano (nao move nada)
Write-Host ''
Write-Host '--- PLANO (nada foi movido ainda) ---'
py organizar_musicas.py $Entrada --destino $Destino --buscar-artista
if ($LASTEXITCODE -ne 0) { throw 'organizar_musicas.py falhou ao montar o plano.' }

$plano = Import-Csv -LiteralPath (Join-Path $raiz 'plano_organizar.csv') -Delimiter ';'
$nOk = @($plano | Where-Object { $_.situacao -eq 'ok' }).Count
$nSug = @($plano | Where-Object { $_.situacao -eq 'sugerido' }).Count
$nRev = @($plano | Where-Object { $_.situacao -eq 'revisar' }).Count
Write-Host ''
Write-Host ("Prontas: {0}   Sugeridas (artista descoberto pelo titulo): {1}   Para revisar (ficam na Entrada): {2}" -f $nOk, $nSug, $nRev)
if (($nOk + $nSug) -eq 0) { Write-Host 'Nada para transferir. Corrija os "revisar" (veja plano_organizar.csv) e rode de novo.'; return }

$flags = @()
if ($nSug -gt 0 -and (Perguntar "Incluir as $nSug sugeridas?" $false)) { $flags += '--incluir-sugeridos' }
$total = $nOk + $(if ($flags -contains '--incluir-sugeridos') { $nSug } else { 0 })

# 3) transferir
Write-Host ''
if (-not (Perguntar "Transferir $total musicas para a biblioteca?" $false)) { Write-Host 'Cancelado. Nada foi movido.'; return }
py organizar_musicas.py $Entrada --destino $Destino --buscar-artista --aplicar @flags
if ($LASTEXITCODE -ne 0) { throw 'organizar_musicas.py falhou ao transferir.' }

# 4) catalogo
if ($SemCatalogo) { Write-Host 'Pronto. (Catalogo nao atualizado: use .\atualizar_musicas.ps1 depois.)'; return }
Write-Host ''
Write-Host 'Transferido. Antes de atualizar o catalogo, espere o Google Drive terminar de sincronizar'
Write-Host '(icone do Drive na barra de tarefas sem a seta girando).'
if (Perguntar 'Atualizar o catalogo agora?' $true) {
    & (Join-Path $raiz 'atualizar_musicas.ps1')
} else {
    Write-Host 'Ok. Quando o Drive terminar, rode: .\atualizar_musicas.ps1'
}
