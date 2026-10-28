# Sonora 2.0 - Guia do dia a dia

## Como as pecas se encaixam
- **App (Flutter)**: toca as musicas direto do Google Drive. O catalogo (artistas, generos, faixas) fica no
  celular e e atualizado pelo painel, sem APK novo.
- **Painel** (Apps Script + planilha `Sonora2_Controle`): libera aparelhos, mostra quem ouve o que, publica
  APK novo e catalogo novo. Endereco: `<URL /exec>?page=painel&chave=<PAINEL_CHAVE>`.
- **Python** (`etapa1_nomes/`): le os nomes dos arquivos e monta o catalogo.
- **Drive**: pasta `Musicas\Sonora2_APKs` guarda o `catalogo.zip` e os APKs (acesso "qualquer pessoa com o link").

## 1. Entrou musica nova (nao precisa de APK)
1. Coloque os MP3 na pasta da biblioteca no Drive (nome `Artista - Titulo.mp3`).
2. Rode:
   ```
   cd C:\ProjetosClaude\Sonora2
   powershell -ExecutionPolicy Bypass -File .\atualizar_musicas.ps1
   ```
   Ele gera o cache no Drive, baixa, identifica artistas/generos/fotos, monta o catalogo e copia o
   `catalogo.zip` para a pasta do Drive.
3. O app mostra "Musicas novas disponiveis" ao abrir. So toca em **Atualizar agora**.
- Se o Deezer estiver bloqueado na rede (erro `getaddrinfo failed`), os artistas ficam sem foto. Em outra rede, rode
  `.\atualizar_musicas.ps1 -RefazerFotos`.
- Primeira vez: no painel, card **Catalogo de musicas**, cole o link do `catalogo.zip` do Drive, deixe a versao
  vazia (automatica) e clique **Publicar catalogo**.

## 2. Mudou o app (precisa de APK novo)
1. Suba a versao em `app\lib\config.dart` (`versaoApp`) e `app\pubspec.yaml` (`version`). O numero depois do `+`
   precisa aumentar sempre. Ex.: `0.7.2+9` -> `0.7.3+10`.
2. `powershell -ExecutionPolicy Bypass -File .\gerar_apk.ps1` (gera `apks\<versao>\sonora-<versao>.apk`).
3. Suba o APK no Drive (arquivo novo), copie o link e publique no painel, card **Atualizacao do app**
   (versao igual a do APK + link). Os aparelhos recebem o aviso ao abrir o app.
- Teste rapido por cabo: `adb install -r <apk>`
  (`%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`).

## 3. Mudou o painel (Codigo.gs / Painel.html)
Cole nos arquivos do Apps Script e use **Implantar > Gerenciar implantacoes > lapis > Nova versao**. A URL nao muda.

## 4. Trabalhar em OUTRO computador
**Importante:** o APK e assinado com a chave `debug.keystore` deste PC. Se outro PC gerar o APK com outra chave,
o Android recusa a atualizacao por cima (todos teriam que desinstalar e reinstalar). Por isso a chave precisa ir junto.

No PC de origem:
1. `powershell -ExecutionPolicy Bypass -File .\backup_para_outro_pc.ps1`
   Cria `Sonora2_backup_pc.zip` na Area de Trabalho (chave de assinatura, `config_local.ps1`, `artistas.json`).
   Leve por pen drive. Nao suba em nuvem publica.

No PC novo:
1. Instale Git, Flutter (com Android SDK), Python 3 e o Google Drive para computador.
2. `git clone https://github.com/BarclayMedeirosNormando/Sonora2.git C:\ProjetosClaude\Sonora2`
3. `cd C:\ProjetosClaude\Sonora2`
   `powershell -ExecutionPolicy Bypass -File .\restaurar_no_novo_pc.ps1 -Zip "D:\Sonora2_backup_pc.zip"`
4. Se o Drive estiver em outra letra, ajuste `$PastaDrive` no `config_local.ps1`.
5. `cd app` e `flutter pub get`; depois `flutter doctor` para conferir.
6. `powershell -ExecutionPolicy Bypass -File .\atualizar_musicas.ps1`
   (recria o catalogo local do app; sem o `artistas.json` do backup ele busca tudo de novo e demora).
7. Pronto para `gerar_apk.ps1`. Confira que a versao do APK e MAIOR que a instalada.
- Sem o backup, se perder a chave: gere uma nova e todos precisam desinstalar/reinstalar uma vez.

## 5. Problemas comuns
| Sintoma | Causa e solucao |
|---|---|
| App fecha ao tocar em Atualizar | Falta o provider no manifest (ja corrigido). Veja `adb logcat -d \| findstr FATAL` |
| APK atualiza mas continua pedindo | O APK do Drive e de versao antiga: confira o numero apos o `+` |
| "Catalogo nao encontrado" ao abrir | `app\assets\catalogo` vazio: rode `atualizar_musicas.ps1` e gere o APK |
| Artista sem foto | Deezer bloqueado na rede: `atualizar_musicas.ps1 -RefazerFotos` em outra rede |
| Aparelho "Aguardando" | Libere no painel, aba Aparelhos |
| Gerar cache: chave invalida | Chave trocada: veja `GERAR_CACHE_CHAVE` no Cloud Run e atualize `config_local.ps1` |

## 6. O que NAO esta no Git (de proposito)
`config_local.ps1` (chaves), `etapa1_nomes/cache.json` e `saida/` (IDs do Drive), `app/assets/catalogo/`,
`catalogos/`, `apks/`.
