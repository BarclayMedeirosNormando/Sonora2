"""Exporta saida/catalogo.db para JSONs que o app Sonora 2.0 le.

    py exportar.py [--saida saida]

Gera saida/app/:
  indice.json           generos + artistas (leve, carrega na abertura do app)
  artistas/<slug>.json  faixas de cada artista (carrega ao abrir o artista)
  faixas_busca.json     indice compacto de todas as faixas [id, titulo, versao, artistaId] (busca por musica)
  sem_artista.json      faixas que o nome nao permitiu identificar (por pasta)
  catalogo.zip          tudo acima compactado (e o que se publica no painel)
As fotos NAO vao no catalogo: cada artista guarda o endereco (Deezer) e o app baixa a foto
na primeira vez que ela aparece, guardando no celular.
So entram faixas principais (repetidas ficam de fora).
"""
import argparse
import json
import shutil
import sqlite3
import sys
import zipfile
from pathlib import Path

OUTROS = "Outros"


def slug(k):
    return "".join(c if c.isalnum() else "_" for c in k)[:60]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--saida", default="saida")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    saida = Path(args.saida)
    db = sqlite3.connect(saida / "catalogo.db")
    db.row_factory = sqlite3.Row
    out = saida / "app"
    if out.exists():
        shutil.rmtree(out)
    (out / "artistas").mkdir(parents=True)
    urls = {}
    arq_art = saida / "artistas.json"
    if arq_art.exists():
        for k, v in json.loads(arq_art.read_text(encoding="utf-8")).items():
            if v.get("foto_url"):
                urls[k] = v["foto_url"]

    faixas = {}
    for f in db.execute("""select id, titulo, versao, convidados, artista_chave, pasta
                           from faixas where principal=1 order by lower(titulo)"""):
        faixas.setdefault(f["artista_chave"], []).append(f)

    artistas, generos, n_fotos = [], {}, 0
    busca = []
    for a in db.execute("select * from artistas order by faixas desc"):
        fs = faixas.get(a["chave"])
        if not fs:
            continue
        g = a["genero"] or OUTROS
        foto = None
        if a["foto"] and urls.get(a["chave"]):
            foto, n_fotos = urls[a["chave"]], n_fotos + 1
        s = slug(a["chave"])
        artistas.append({"id": s, "nome": a["nome"], "genero": g, "foto": foto, "faixas": len(fs)})
        generos.setdefault(g, {"nome": g, "artistas": 0, "faixas": 0})
        generos[g]["artistas"] += 1
        generos[g]["faixas"] += len(fs)
        lista = []
        for f in fs:
            busca.append([f["id"], f["titulo"], f["versao"] or "", s])
            item = {"id": f["id"], "titulo": f["titulo"]}
            if f["versao"]:
                item["versao"] = f["versao"]
            if f["convidados"]:
                item["convidados"] = f["convidados"]
            lista.append(item)
        (out / "artistas" / f"{s}.json").write_text(json.dumps(
            {"id": s, "nome": a["nome"], "genero": g, "foto": foto, "faixas": lista},
            ensure_ascii=False), encoding="utf-8")

    ordem = sorted(generos.values(), key=lambda x: (x["nome"] == OUTROS, -x["faixas"]))
    (out / "indice.json").write_text(json.dumps(
        {"generos": ordem, "artistas": artistas}, ensure_ascii=False), encoding="utf-8")

    (out / "faixas_busca.json").write_text(
        json.dumps(busca, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    sem = {}
    for f in db.execute("""select id, arquivo, pasta from faixas
                           where principal=1 and (artista_chave is null or artista_chave='')"""):
        sem.setdefault(f["pasta"] or "", []).append({"id": f["id"], "arquivo": f["arquivo"]})
    (out / "sem_artista.json").write_text(json.dumps(sem, ensure_ascii=False), encoding="utf-8")

    zpath = saida / "catalogo.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in sorted(out.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(out).as_posix())
    print(f"{len(artistas)} artistas, {len(generos)} generos, {n_fotos} fotos (por endereco)")
    print(f"Zip: {zpath} ({zpath.stat().st_size / 1e6:.1f} MB)")
    print(f"{sum(len(v) for v in sem.values())} faixas sem artista em {len(sem)} pastas")
    print(f"Pronto: {out}")


if __name__ == "__main__":
    main()
