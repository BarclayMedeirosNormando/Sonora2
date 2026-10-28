# Sonora 2.0 - Etapa 1: leitor de nomes

Le o nome do arquivo MP3 (e a pasta) e descobre artista e titulo, com nota de confianca.
So usa Python padrao (sem instalar nada).

    python testar_nomes.py cache.json resultado.csv

- `nomes.py`: o leitor (`ler_nome`).
- `testar_nomes.py`: roda no cache da biblioteca atual e mostra estatisticas + amostras.
- `resultado.csv`: uma linha por faixa (abra no Excel, separador `;`).

Confianca: **alta** = "Artista - Titulo" claro; **media** = artista deduzido da pasta ou
formato duvidoso; **baixa** = so o titulo (artista desconhecido).

## Etapa 2: genero e foto dos artistas

Na pasta `etapa1_nomes`, no prompt:

    python buscar_artistas.py resultado.csv --top 50

Consulta MusicBrainz (generos) e Deezer (foto), 1 artista por vez, com pausas para
respeitar os limites. Pode interromper (Ctrl+C) e rodar de novo: continua de onde parou.
Ao final abra `saida\conferir.html` para ver foto + generos de cada artista.

### Etapa 2b: genero final (sem internet)

    python generos.py resultado.csv saida\artistas.json

Junta as tags do MusicBrainz com os nomes das pastas e grava `saida\generos.csv`
(coluna `genero` = resultado final, `fonte` = tags ou pasta).

### Refazer os que falharam (nao-achado)

    python buscar_artistas.py resultado.csv --top 50 --refazer-falhas
