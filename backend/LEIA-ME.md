# Sonora 2.0 – Painel de liberação (Apps Script)

## 1. Criar a planilha e o script
1. Google Sheets → nova planilha chamada **Sonora2_Controle**.
2. **Extensões → Apps Script**.
3. Apague o conteúdo de `Código.gs` e cole `backend/Codigo.gs`.
4. **+ → HTML**, nome exatamente **Painel**, cole `backend/Painel.html`.
5. ⚙ Configurações do projeto → fuso horário **America/Sao_Paulo**.

## 2. Preparar
1. Escolha a função `configurar` e clique em **Executar** (autorize quando pedir).
2. Ela cria as abas `Aparelhos`, `Plays`, `Config` e gera a chave do painel (veja em **Execuções → log**, ou em Configurações do projeto → Propriedades do script → `PAINEL_CHAVE`).

## 3. Publicar
1. **Implantar → Nova implantação → App da Web**.
2. Executar como: **Eu**. Quem tem acesso: **Qualquer pessoa**.
3. Copie a URL que termina em `/exec`.
4. Ao alterar o código depois: **Implantar → Gerenciar → editar → Nova versão** (a URL continua a mesma).

## 4. Ligar o app
Em `app/lib/config.dart`:
```dart
const String urlControle = 'COLE_AQUI_A_URL_/exec';
```
Depois: `flutter pub get` e `flutter run` (ou gerar o APK).

## 5. Usar
- **Painel:** `<URL /exec>?page=painel&chave=<PAINEL_CHAVE>` (guarde como favorito; não compartilhe a chave).
- Quem abre o app pela primeira vez vê um código. Ele aparece no painel em **Aparelhos** como *Aguardando*; clique **Liberar**.
- Com `urlControle = ''` o controle fica desligado e o app abre para todos.

## Limites
- Apps Script aceita ~30 execuções simultâneas. O app já reduz isso (libera por 12 h em cache, envia plays em lotes a cada 3 min). Se crescer muito, trocar `urlControle` por um serviço próprio (Cloud Run).
- Planilha tem limite de 10 milhões de células: rode `limparPlaysAntigos()` de vez em quando (apaga plays com mais de 180 dias).

## Atualizar o catálogo (músicas novas) sem gerar APK
1. Coloque as músicas novas na pasta da biblioteca (nome `Artista - Título.mp3`) e gere o `cache.json` de novo.
2. No PowerShell: `powershell -ExecutionPolicy Bypass -File .\atualizar_catalogo.ps1`
   (roda `atualizar.py` e `exportar.py` e salva `catalogos\catalogo-<data>.zip`).
3. Suba o zip no Drive (acesso "qualquer pessoa com o link") e copie o link.
4. No painel, aba **Aparelhos**, card **Catálogo de músicas**: versão (o script mostra, ex. `2026-10-28_1130`), link e notas → **Publicar catálogo**.
5. Ao abrir o app, cada aparelho liberado baixa o catálogo novo sozinho. Não precisa de APK.
As fotos dos artistas não vão no zip: o app baixa cada foto na primeira vez que ela aparece.
