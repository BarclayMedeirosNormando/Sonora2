"""Sonora 2.0 - atualizacao do catalogo (rode toda vez que colocar musicas novas).

    py atualizar.py cache.json                 # tudo, buscando ate 300 artistas novos
    py atualizar.py cache.json --max-artistas 1000
    py atualizar.py cache.json --sem-rede      # nao consulta internet; so reorganiza

O que faz, em ordem:
  1. le o cache da biblioteca (lista de pastas/arquivos do Drive)
  2. descobre artista/titulo de TODAS as faixas (rapido, sem internet)
  3. busca na internet SO os artistas que ainda nao estao em saida/artistas.json
  4. decide o genero de cada artista (tags + pastas)
  5. aplica suas correcoes (correcoes.csv)
  6. marca faixas repetidas
  7. grava saida/catalogo.db  (e' esse arquivo que o app vai usar)

E' seguro rodar de novo quantas vezes quiser: o catalogo e' refeito do zero a partir
do cache + artistas.json + correcoes.csv, e a internet so e' usada para o que e' novo.
"""
import argparse
import collections
import csv
import json
import re
import sqlite3
import sys
from pathlib import Path

from nomes import chave, ler_nome, reparar_nomes, sem_acento
from generos import genero_por_pastas, genero_por_tags, mapear, ESPECIFICOS
import buscar_artistas as ba

ESQUEMA = """
CREATE TABLE faixas (
    id TEXT PRIMARY KEY,          -- id do arquivo no Drive
    arquivo TEXT, pasta_id TEXT, pasta TEXT,
    artista_chave TEXT, titulo TEXT, versao TEXT, convidados TEXT,
    confianca TEXT, origem TEXT, tamanho INTEGER,
    titulo_chave TEXT, dup_grupo INTEGER, principal INTEGER DEFAULT 1
);
CREATE TABLE artistas (
    chave TEXT PRIMARY KEY, nome TEXT, faixas INTEGER,
    genero TEXT, genero_fonte TEXT, foto TEXT, pais TEXT, tags TEXT, status TEXT
);
CREATE INDEX i_faixas_artista ON faixas(artista_chave);
CREATE INDEX i_faixas_pasta ON faixas(pasta_id);
CREATE INDEX i_artistas_genero ON artistas(genero);
"""


def ler_correcoes(caminho):
    """correcoes.csv: tipo;alvo;valor   (linhas com # sao comentarios)
       genero ; Zé Vaqueiro ; Piseiro        -> forca o genero de um artista
       unir   ; Beatles     ; The Beatles    -> junta dois nomes no mesmo artista
       faixa  ; 03 - Foo.mp3; Fulano         -> forca o artista de um arquivo"""
    c = {"genero": {}, "unir": {}, "faixa": {}}
    p = Path(caminho)
    if not p.exists():
        return c
    with open(p, newline="", encoding="utf-8-sig") as fh:
        for linha in csv.reader(fh, delimiter=";"):
            if not linha or not linha[0].strip() or linha[0].lstrip().startswith("#") or len(linha) < 3:
                continue
            tipo, alvo, valor = linha[0].strip().lower(), linha[1].strip(), linha[2].strip()
            if tipo == "genero":
                c["genero"][chave(alvo)] = valor
            elif tipo == "unir":
                c["unir"][chave(alvo)] = valor
            elif tipo == "faixa":
                c["faixa"][alvo] = valor
    return c


# Parenteses que indicam OUTRA gravacao (nao devem ser juntados com a versao normal).
_OUTRA_VERSAO = re.compile(r"take|demo|mix|edit|acoust|ac[uú]stic|instrumental|session|mono|stereo|"
                           r"karaoke|cover|tribute|anthology|outtake|alternat|extended|vers[aã]o", re.I)
_MESMA_COISA = re.compile(r"remaster|deluxe|feat|ft\.|bonus|re-?recorded|explicit|single|album", re.I)


def titulo_chave(titulo, versao):
    """Chave para achar a MESMA gravacao repetida. Ignora (Remastered), (feat. X);
    mantem separadas ao vivo, remix, demo, take, acustico etc."""
    titulo = titulo or ""
    marcas = []
    for trecho in re.findall(r"[\(\[](.*?)[\)\]]", titulo):
        if re.search(r"ao vivo|\blive\b", trecho, re.I):
            marcas.append("vivo")
        elif _OUTRA_VERSAO.search(trecho) and not _MESMA_COISA.search(trecho):
            marcas.append(chave(trecho))
        elif re.search(r"take|demo|anthology|outtake", trecho, re.I):
            marcas.append(chave(trecho))
    if versao and re.search(r"ao vivo|live", versao, re.I) and "vivo" not in marcas:
        marcas.append("vivo")
    base = chave(re.sub(r"[\(\[].*?[\)\]]", " ", titulo))
    return base + ("|" + "|".join(sorted(set(marcas))) if marcas else "")


def construir(cache_path, saida, max_artistas, usar_rede, correcoes_path):
    saida = Path(saida)
    saida.mkdir(parents=True, exist_ok=True)
    corr = ler_correcoes(correcoes_path)

    # ---- 1/2. ler o cache e identificar artista/titulo de todas as faixas
    dados = json.loads(Path(cache_path).read_text(encoding="utf-8"))
    arvore = dados["arvore"]
    pastas = {p["id"]: p for p in arvore if p["tipo"] == "pasta"}
    faixas = [x for x in arvore if x["tipo"] == "faixa"]
    print(f"[1/7] Cache: {len(faixas)} faixas em {len(pastas)} pastas")

    reparos, resumo = reparar_nomes(faixas, pastas)
    print(f"      Reparos de nome: {resumo['invertidas']} invertidas (Titulo - Artista), "
          f"{resumo['numero_no_nome']} com numero no nome do artista (ex.: 50 Cent)")

    def passada(conhecidos):
        res = []
        for f in faixas:
            pai = pastas.get(f["paiId"])
            avo = pastas.get(pai["paiId"]) if pai else None
            nome, manter = reparos.get(f["id"], (f["name"], False))
            res.append(ler_nome(nome, pai["name"] if pai else None,
                                avo["name"] if avo else None, conhecidos,
                                manter_numero=manter))
        return res

    primeira = passada(None)
    cont = collections.Counter(r.chave_artista for r in primeira if r.chave_artista and r.confianca == "alta")
    leituras = passada({k for k, n in cont.items() if n >= 2})
    print(f"[2/7] Nomes lidos: {sum(1 for r in leituras if r.confianca in ('alta', 'media'))} "
          f"com artista de {len(leituras)}")

    # correcoes por faixa e por uniao de nomes
    uniao = {k: (chave(v), v) for k, v in corr["unir"].items()}
    nome_exibicao = collections.defaultdict(collections.Counter)
    linhas = []
    for f, r in zip(faixas, leituras):
        artista = r.artista
        conf, origem = r.confianca, r.origem
        if f["name"] in corr["faixa"]:
            artista, conf, origem = corr["faixa"][f["name"]], "alta", "correcao"
        k = chave(artista) if artista and conf in ("alta", "media") else None
        if k and k in uniao:
            k, artista = uniao[k]
        if k:
            nome_exibicao[k][artista] += 1
        pai = pastas.get(f["paiId"])
        linhas.append((f, r, k, conf, origem, pai))

    por_artista = collections.Counter(k for _, _, k, _, _, _ in linhas if k)
    pastas_do_artista = collections.defaultdict(collections.Counter)
    for f, r, k, conf, origem, pai in linhas:
        if k and pai:
            pastas_do_artista[k][pai["name"]] += 1

    # ---- 3. internet: so artistas novos
    arq = saida / "artistas.json"
    banco = json.loads(arq.read_text(encoding="utf-8")) if arq.exists() else {}
    pendentes = [{"chave": k, "nome": nome_exibicao[k].most_common(1)[0][0], "faixas": n}
                 for k, n in por_artista.most_common() if k not in banco]
    print(f"[3/7] Artistas: {len(por_artista)} no total, {len(banco)} ja buscados, {len(pendentes)} novos")
    if usar_rede and pendentes:
        lote = pendentes[:max_artistas]
        print(f"      buscando {len(lote)} agora (Ctrl+C para parar; o que ja foi feito fica salvo)\n")
        ba.processar(lote, saida, banco)
    elif pendentes:
        print("      (--sem-rede: pulando a busca)")

    # ---- 4/5. genero final + correcoes
    artistas = {}
    for k, n in por_artista.items():
        b = banco.get(k, {})
        gt = genero_por_tags(b.get("mb_tags"))
        gp, _ = genero_por_pastas(pastas_do_artista[k])
        if k in corr["genero"]:
            g, fonte = corr["genero"][k], "correcao"
        elif gt:
            g, fonte = gt, "tags"
        elif gp:
            g, fonte = gp, "pasta"
        else:
            g, fonte = None, None
        artistas[k] = (nome_exibicao[k].most_common(1)[0][0], n, g, fonte, b.get("foto"),
                       b.get("mb_pais"), ", ".join(b.get("mb_tags", [])), b.get("status", "pendente"))
    print(f"[4/7] Generos decididos: {sum(1 for a in artistas.values() if a[2])} de {len(artistas)} artistas")
    print(f"[5/7] Correcoes aplicadas: {len(corr['genero'])} generos, {len(corr['unir'])} unioes, "
          f"{len(corr['faixa'])} faixas")

    # ---- 6. duplicatas: mesmo artista + mesmo titulo (sem remaster) => mantem a maior
    grupos = collections.defaultdict(list)
    for f, r, k, conf, origem, pai in linhas:
        if k and r.titulo:
            grupos[(k, titulo_chave(r.titulo, r.versao))].append(f)
    titulos_por_id = {l[0]["id"]: l[1].titulo for l in linhas}
    principal, dup_grupo, n_dup = {}, {}, 0
    for gid, (chv, fs) in enumerate(g for g in grupos.items() if len(g[1]) > 1):
        tam = sorted(int(x.get("size") or 0) for x in fs)
        mediana = tam[len(tam) // 2]
        # Preferida: titulo mais limpo (sem parenteses), depois tamanho mais perto do tipico, depois id.
        fs_ord = sorted(fs, key=lambda x: ("(" in (titulos_por_id.get(x["id"]) or ""),
                                          abs(int(x.get("size") or 0) - mediana), x["id"]))
        for j, f in enumerate(fs_ord):
            dup_grupo[f["id"]] = gid
            principal[f["id"]] = 1 if j == 0 else 0
        n_dup += len(fs_ord) - 1
    print(f"[6/7] Repetidas: {n_dup} faixas duplicadas em {len(set(dup_grupo.values()))} grupos")

    # ---- 7. gravar o catalogo
    db_path = saida / "catalogo.db"
    if db_path.exists():
        db_path.unlink()
    db = sqlite3.connect(db_path)
    db.executescript(ESQUEMA)
    db.executemany("INSERT INTO artistas VALUES (?,?,?,?,?,?,?,?,?)",
                   [(k,) + v for k, v in artistas.items()])
    db.executemany("INSERT INTO faixas VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
        (f["id"], f["name"], f["paiId"], pai["name"] if pai else None, k, r.titulo, r.versao,
         ", ".join(r.convidados), conf, origem, int(f.get("size") or 0),
         titulo_chave(r.titulo, r.versao) if r.titulo else None,
         dup_grupo.get(f["id"]), principal.get(f["id"], 1))
        for f, r, k, conf, origem, pai in linhas])
    db.commit()
    db.close()

    ok = sum(1 for l in linhas if l[2])
    print(f"[7/7] Catalogo gravado: {db_path}  ({db_path.stat().st_size / 1024:.0f} KB)")
    por_gen = collections.Counter(a[2] or "(sem genero)" for a in artistas.values())
    print("\nArtistas por genero:", ", ".join(f"{g} ({n})" for g, n in por_gen.most_common(12)))
    print(f"Faixas com artista: {ok} de {len(linhas)} ({ok / max(1, len(linhas)):.0%})")
    return db_path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cache", help="cache.json da biblioteca (o mesmo que o app usa)")
    ap.add_argument("--saida", default="saida")
    ap.add_argument("--max-artistas", type=int, default=300, help="maximo de artistas novos buscados por rodada")
    ap.add_argument("--sem-rede", action="store_true")
    ap.add_argument("--correcoes", default="correcoes.csv")
    a = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    construir(a.cache, a.saida, a.max_artistas, not a.sem_rede, a.correcoes)


if __name__ == "__main__":
    main()
