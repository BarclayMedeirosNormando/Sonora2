# Sonora 2.0 - Catalogo e atualizacao

Um comando so, que pode ser rodado quantas vezes quiser (a biblioteca vai crescendo):

    py atualizar.py cache.json

O que faz: le as faixas, identifica artista/titulo, busca foto e genero SO dos artistas
novos (guarda em saida/artistas.json), aplica correcoes.csv, marca musicas repetidas
e gera saida/catalogo.db (SQLite).

Opcoes:
    --max-artistas 300   limita quantos artistas novos buscar na internet por rodada
    --sem-rede           so reorganiza, sem buscar nada na internet
    --correcoes arq.csv  usa outro arquivo de correcoes

Correcoes (correcoes.csv, separador ;):
    genero;Artista;Genero
    unir;Nome origem;Nome destino
    faixa;arquivo.mp3;Artista
Linhas com # sao comentarios. As correcoes valem em toda rodada futura.

Precisa de cache.json (gerado pelo /gerar-cache do backend) nesta pasta.
Para rodar de novo as buscas que falharam: py buscar_artistas.py resultado.csv --refazer-falhas
