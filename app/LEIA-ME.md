# Sonora 2.0 - app

Telas: Splash, Início, Buscar, Biblioteca (Artistas, Gêneros, Favoritas, Playlists),
Gênero, Artista, Player, Fila, Playlist e "Adicionar à playlist".
Favoritas, playlists e recentes ficam salvos no aparelho (shared_preferences).
Ainda NÃO tem: downloads/offline, busca por música (só artista e gênero).

Primeira vez, nesta pasta (C:\ProjetosClaude\Sonora2\app):

    flutter create --platforms=android,web --project-name sonora2 .
    flutter pub get

Dados: depois de rodar `py exportar.py` na pasta etapa1_nomes:

    xcopy ..\etapa1_nomes\saida\app\* assets\catalogo\ /E /I /Y

Rodar:

    flutter run -d chrome        (web)
    flutter run                  (celular conectado)

No web o link direto do Drive pode ser bloqueado por CORS; no Android funciona.
O endereço do áudio fica em lib\config.dart.
