"""Relatorio de limpeza do Sonora 2.0 - SO LE, nao apaga nem move nada.

Uso (na pasta etapa1_nomes, depois de rodar atualizar_musicas.ps1):

    py relatorio_limpeza.py

Gera em saida\\limpeza\\ (pasta ignorada pelo git, tem IDs do Drive):
  resumo.txt             numeros gerais
  sem_foto_artistas.csv  artistas sem foto: faixas, genero, pastas, exemplos (para voce decidir)
  sem_foto_faixas.csv    uma linha por faixa desses artistas (com ID do Drive, para mover depois)
  sem_artista.csv        faixas em que nao se identificou o artista (nome de arquivo estranho)
  duplicadas.csv         copias repetidas (a que sobra x a que seria removida)

Abra os .csv no Excel (separador ;). Nada aqui altera o Drive.
"""
import csv
import collections
import sqlite3
import sys
from pathlib import Path

saida = Path(sys.argv[1] if len(sys.argv) > 1 else "saida")
db_path = saida / "catalogo.db"
if not db_path.exists():
    sys.exit(f"Nao achei {db_path}. Rode antes: .\\atualizar_musicas.ps1")
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

pasta_saida = saida / "limpeza"
pasta_saida.mkdir(exist_ok=True)
db = sqlite3.connect(db_path)
db.row_factory = sqlite3.Row


def csv_out(nome, cab, linhas):
    with open(pasta_saida / nome, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(cab)
        w.writerows(linhas)


mb = lambda b: round((b or 0) / 1024 / 1024, 1)

total = db.execute("SELECT COUNT(*) FROM faixas").fetchone()[0]

# ---- 1. artistas sem foto
artistas = db.execute("SELECT * FROM artistas WHERE foto IS NULL OR foto = '' ORDER BY faixas DESC").fetchall()
linhas_art, linhas_faixas = [], []
n_faixas_sem_foto = 0
for a in artistas:
    fs = db.execute("SELECT * FROM faixas WHERE artista_chave = ? ORDER BY pasta, arquivo", (a["chave"],)).fetchall()
    pastas = collections.Counter(f["pasta"] for f in fs)
    n_faixas_sem_foto += len(fs)
    linhas_art.append([
        a["nome"], len(fs), a["genero"] or "", a["status"], f"{a['pais'] or ''}",
        " | ".join(f"{p} ({n})" for p, n in pastas.most_common(3)),
        " | ".join(f["arquivo"] for f in fs[:3]),
    ])
    for f in fs:
        linhas_faixas.append([a["nome"], f["arquivo"], f["pasta"], f["id"], mb(f["tamanho"])])
csv_out("sem_foto_artistas.csv",
        ["artista", "faixas", "genero", "status_busca", "pais", "pastas", "exemplos"], linhas_art)
csv_out("sem_foto_faixas.csv", ["artista", "arquivo", "pasta", "id_drive", "mb"], linhas_faixas)

# ---- 2. faixas sem artista identificado
sem_art = db.execute(
    "SELECT * FROM faixas WHERE artista_chave IS NULL OR artista_chave = '' ORDER BY pasta, arquivo").fetchall()
csv_out("sem_artista.csv", ["arquivo", "pasta", "id_drive", "mb"],
        [[f["arquivo"], f["pasta"], f["id"], mb(f["tamanho"])] for f in sem_art])

# ---- 3. duplicadas
dups = db.execute("""
    SELECT d.arquivo AS dup_arquivo, d.pasta AS dup_pasta, d.id AS dup_id, d.tamanho AS dup_tam,
           p.arquivo AS fica_arquivo, p.pasta AS fica_pasta, a.nome AS artista, d.titulo AS titulo
    FROM faixas d
    JOIN faixas p ON p.dup_grupo = d.dup_grupo AND p.principal = 1
    LEFT JOIN artistas a ON a.chave = d.artista_chave
    WHERE d.principal = 0 ORDER BY a.nome, d.titulo""").fetchall()
csv_out("duplicadas.csv",
        ["artista", "titulo", "remover_arquivo", "remover_pasta", "remover_id", "mb", "fica_arquivo", "fica_pasta"],
        [[d["artista"], d["titulo"], d["dup_arquivo"], d["dup_pasta"], d["dup_id"], mb(d["dup_tam"]),
          d["fica_arquivo"], d["fica_pasta"]] for d in dups])

# ---- resumo
resumo = [
    f"Faixas no catalogo:            {total}",
    f"Artistas sem foto:             {len(artistas)}  ({n_faixas_sem_foto} faixas, "
    f"{sum(float(r[4]) for r in linhas_faixas):.0f} MB)",
    f"Faixas sem artista:            {len(sem_art)}",
    f"Faixas duplicadas (a remover): {len(dups)}  ({sum(float(mb(d['dup_tam'])) for d in dups):.0f} MB)",
    "",
    "Maiores artistas sem foto (confira se nao e erro de nome):",
] + [f"  {r[0][:40]:40} {r[1]:4} faixas  {r[5][:50]}" for r in linhas_art[:25]]
(pasta_saida / "resumo.txt").write_text("\n".join(resumo), encoding="utf-8")
print("\n".join(resumo))
print(f"\nArquivos em: {pasta_saida.resolve()}")
