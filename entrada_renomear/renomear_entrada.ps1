# Uso: .\renomear_entrada.ps1            -> aplica o plano.csv e grava desfazer_AAAA-MM-DD_HHmm.csv
#      .\renomear_entrada.ps1 -Simular   -> so mostra o que faria
#      .\renomear_entrada.ps1 -Desfazer arquivo.csv -> volta os nomes antigos
param([switch]$Simular, [string]$Desfazer, [string]$Raiz = 'G:\Meu Drive\Musicas\Entrada')
$ErrorActionPreference = 'Stop'
$aqui = $PSScriptRoot
if ($Desfazer) {
    foreach ($r in (Import-Csv -LiteralPath $Desfazer -Delimiter ';' -Encoding UTF8)) {
        $novo = Join-Path $r.pasta $r.novo_nome
        if (Test-Path -LiteralPath $novo) { Rename-Item -LiteralPath $novo -NewName $r.nome_atual; Write-Host "VOLTOU: $($r.nome_atual)" }
    }
    return
}
$log = Join-Path $aqui ("desfazer_{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
$out = @(); $ok = 0; $pul = 0
foreach ($r in (Import-Csv -LiteralPath (Join-Path $aqui 'plano.csv') -Delimiter ';' -Encoding UTF8)) {
    $dir = Join-Path $Raiz $r.pasta
    $de = Join-Path $dir $r.nome_atual
    $para = Join-Path $dir $r.novo_nome
    if (-not (Test-Path -LiteralPath $de)) { Write-Host "NAO ACHEI: $($r.nome_atual)"; $pul++; continue }
    if (Test-Path -LiteralPath $para) { Write-Host "JA EXISTE: $($r.novo_nome)"; $pul++; continue }
    if ($Simular) { Write-Host "$($r.nome_atual)  ->  $($r.novo_nome)"; continue }
    Rename-Item -LiteralPath $de -NewName $r.novo_nome
    $out += [pscustomobject]@{ pasta = $dir; nome_atual = $r.nome_atual; novo_nome = $r.novo_nome }
    $ok++
}
if (-not $Simular -and $out.Count) { $out | Export-Csv -LiteralPath $log -Delimiter ';' -Encoding UTF8 -NoTypeInformation; Write-Host "Renomeados: $ok | Pulados: $pul | Log: $log" }
