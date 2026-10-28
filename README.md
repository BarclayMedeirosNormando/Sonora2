# Sonora 2.0

Player de musica (Flutter) organizado automaticamente por artista e genero, lendo os
nomes dos arquivos de uma biblioteca no Google Drive. Sem custo de servidor: o catalogo
fica dentro do app e as favoritas, playlists e downloads ficam no aparelho.

## Pastas

- `etapa1_nomes/` - scripts Python (so biblioteca padrao): leem o `cache.json` da biblioteca,
  identificam artista/titulo, buscam genero e foto (MusicBrainz/Deezer) e geram o catalogo.
  Veja `LEIA-ME.md` e `LEIA-ME-ATUALIZAR.md`.
- `app/` - o app Flutter (Android e web). Veja `app/LEIA-ME.md`.

## O que NAO esta no repositorio

Por conter IDs de arquivos do Drive, ficam de fora e sao gerados localmente:
`etapa1_nomes/cache.json`, `etapa1_nomes/saida/` e `app/assets/catalogo/`.

## Gerar o catalogo e rodar o app

    cd etapa1_nomes
    py atualizar.py cache.json
    py exportar.py
    xcopy saida\app\* ..\app\assets\catalogo\ /E /I /Y
    cd ..\app
    flutter pub get
    flutter run

## Recursos

Busca por artista, genero e musica; favoritas, playlists e recentes; fila, embaralhar,
repetir e timer para dormir; downloads para ouvir offline (so no celular).
