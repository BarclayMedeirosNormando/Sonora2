"""Etapa 2 do Sonora 2.0: busca genero e foto de cada artista em fontes gratuitas.

Fontes (sem chave, sem custo):
  - MusicBrainz  -> generos/tags, pais, tipo (pessoa/banda)
  - Deezer       -> foto do artista

Uso (na pasta etapa1_nomes, depois de rodar testar_nomes.py):

    python buscar_artistas.py resultado.csv --top 50

Pode ser interrompido com Ctrl+C e rodado de novo: continua de onde parou
(guarda tudo em saida/artistas.json). Ao final abre `saida/conferir.html`
com foto, generos e a nota de cada artista para voce conferir a olho.
"""
import argparse
import collections
import csv
import difflib
import html
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from nomes import chave

UA = "Sonora2/0.1 (barclaymedeiros@gmail.com)"  # MusicBrainz exige identificacao
PAUSA_MB = 1.1       # MusicBrainz: no maximo 1 consulta por segundo
PAUSA_DEEZER = 0.3   # Deezer: ~50 consultas por 5 s


def http_get(url, binario=False, tentativas=3):
    ultimo = None
    for i in range(tentativas):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=25) as r:
                dados = r.read()
            return dados if binario else json.loads(dados.decode("utf-8"))
        except urllib.error.HTTPError as e:
            ultimo = e
            if e.code in (429, 503):          # limite de uso: espera e tenta de novo
                time.sleep(5 * (i + 1))
                continue
            break
        except Exception as e:                  # rede instavel
            ultimo = e
            time.sleep(2 * (i + 1))
    print(f"   ! falha em {url[:80]}: {ultimo}")
    return None


def ler_artistas(csv_path, top):
    """Agrupa o resultado.csv por artista. Usa so faixas de confianca alta/media."""
    cont = collections.Counter()
    nomes = collections.defaultdict(collections.Counter)
    with open(csv_path, newline="", encoding="utf-8-sig") as fh:
        for linha in csv.DictReader(fh, delimiter=";"):
            a = (linha.get("artista") or "").strip()
            if not a or linha.get("confianca") not in ("alta", "media"):
                continue
            k = chave(a)
            if k:
                cont[k] += 1
                nomes[k][a] += 1
    saida = []
    for k, n in cont.most_common(top):
        saida.append({"chave": k, "nome": nomes[k].most_common(1)[0][0], "faixas": n})
    return saida


def buscar_musicbrainz(nome, k):
    q = urllib.parse.quote(f'artist:"{nome}"')
    d = http_get(f"https://musicbrainz.org/ws/2/artist/?query={q}&fmt=json&limit=5")
    time.sleep(PAUSA_MB)
    if not d:
        return None
    def montar(a, parecido=None):
        tags = sorted(a.get("tags", []), key=lambda t: -t.get("count", 0))
        r = {"mb_nome": a.get("name"), "mb_score": a.get("score"),
             "mb_tags": [t["name"] for t in tags[:5]], "mb_pais": a.get("country"),
             "mb_tipo": a.get("type"), "mb_id": a.get("id")}
        if parecido is not None:
            r["mb_parecido"] = round(parecido, 2)   # achado por nome parecido, nao exato
        return r

    candidatos = d.get("artists", [])
    for a in candidatos:
        if chave(a.get("name", "")) == k or chave(nome) in [chave(x.get("name", "")) for x in a.get("aliases", [])]:
            return montar(a)
    # Segunda tentativa: busca sem aspas e nome so parecido (ex: "&" x "e", artigos).
    d2 = http_get(f"https://musicbrainz.org/ws/2/artist/?query={urllib.parse.quote(nome)}&fmt=json&limit=5")
    time.sleep(PAUSA_MB)
    candidatos = (d2 or {}).get("artists", [])
    melhor = max(candidatos, key=lambda a: difflib.SequenceMatcher(None, k, chave(a.get("name", ""))).ratio(),
                 default=None)
    if melhor:
        sim = difflib.SequenceMatcher(None, k, chave(melhor.get("name", ""))).ratio()
        if sim >= 0.88 and (melhor.get("score") or 0) >= 85:
            return montar(melhor, sim)
    return {"mb_candidatos": [a.get("name") for a in candidatos[:3]], "mb_nome": None, "mb_tags": []} if candidatos else None


def buscar_deezer(nome, k):
    d = http_get(f"https://api.deezer.com/search/artist?q={urllib.parse.quote(nome)}&limit=8")
    time.sleep(PAUSA_DEEZER)
    if not d:
        return None
    certos = [a for a in d.get("data", []) if chave(a.get("name", "")) == k]
    if not certos:
        return None
    a = max(certos, key=lambda x: x.get("nb_fan", 0))
    return {"deezer_nome": a.get("name"), "deezer_fas": a.get("nb_fan"),
            "deezer_id": a.get("id"), "foto_url": a.get("picture_big") or a.get("picture_medium")}


def slug(k):
    return "".join(c if c.isalnum() else "_" for c in k)[:60]


def processar(artistas, saida, banco, refazer=False):
    """Busca MusicBrainz + Deezer para cada artista que ainda nao esta no `banco`.
    Grava em saida/artistas.json a cada 5 artistas. Devolve quantos foram buscados."""
    saida = Path(saida)
    (saida / "fotos").mkdir(parents=True, exist_ok=True)
    arq = saida / "artistas.json"
    feitos_agora = 0
    try:
        for i, a in enumerate(artistas, 1):
            k = a["chave"]
            if k in banco and not (refazer and banco[k].get("status") in ("nao-achado", "sem-foto")):
                continue
            reg = dict(a)
            mb = buscar_musicbrainz(a["nome"], k)
            dz = buscar_deezer(a["nome"], k)
            reg.update(mb or {})
            if mb and not mb.get("mb_nome"):
                mb = None
            reg.update(dz or {})
            if dz and dz.get("foto_url"):
                img = http_get(dz["foto_url"], binario=True)
                if img:
                    nome_foto = f"{slug(k)}.jpg"
                    (saida / "fotos" / nome_foto).write_bytes(img)
                    reg["foto"] = nome_foto
            reg["status"] = ("ok" if mb and mb.get("mb_tags") and reg.get("foto")
                             else "sem-genero" if reg.get("foto")          # tem foto; genero vem da pasta
                             else "sem-foto" if mb else "nao-achado")
            banco[k] = reg
            feitos_agora += 1
            print(f"[{i}/{len(artistas)}] {a['nome']:30} {reg['status']:11} "
                  f"{', '.join(reg.get('mb_tags', [])[:3])}")
            if feitos_agora % 5 == 0:
                arq.write_text(json.dumps(banco, ensure_ascii=False, indent=1), encoding="utf-8")
    except KeyboardInterrupt:
        print("\nInterrompido - o que ja foi feito esta salvo.")
    arq.write_text(json.dumps(banco, ensure_ascii=False, indent=1), encoding="utf-8")
    return feitos_agora


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--top", type=int, default=50, help="quantos artistas (mais frequentes primeiro)")
    ap.add_argument("--saida", default="saida")
    ap.add_argument("--refazer-falhas", action="store_true",
                    help="tenta de novo os artistas que deram nao-achado/sem-foto")
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    saida = Path(args.saida)
    (saida / "fotos").mkdir(parents=True, exist_ok=True)
    arq = saida / "artistas.json"
    banco = json.loads(arq.read_text(encoding="utf-8")) if arq.exists() else {}

    artistas = ler_artistas(args.csv, args.top)
    print(f"{len(artistas)} artistas para processar ({sum(1 for a in artistas if a['chave'] in banco)} ja feitos)\n")

    processar(artistas, saida, banco, args.refazer_falhas)

    feitos = [banco[a["chave"]] for a in artistas if a["chave"] in banco]
    cont = collections.Counter(r["status"] for r in feitos)
    print("\n=== RELATORIO ===")
    for st in ("ok", "sem-genero", "sem-foto", "nao-achado"):
        print(f"  {st:11} {cont[st]:4}  {cont[st] / max(1, len(feitos)):5.0%}")
    gen = collections.Counter(t for r in feitos for t in r.get("mb_tags", [])[:1])
    print("  generos principais:", ", ".join(f"{g} ({n})" for g, n in gen.most_common(10)))

    linhas = []
    for r in feitos:
        foto = f'<img src="fotos/{html.escape(r["foto"])}" width="90">' if r.get("foto") else "(sem foto)"
        linhas.append(
            f"<tr><td>{foto}</td><td><b>{html.escape(r['nome'])}</b><br>{r['faixas']} faixas</td>"
            f"<td>{html.escape(r.get('mb_nome') or '-')}<br>{html.escape(', '.join(r.get('mb_tags', [])) or '-')}"
            f"<br>{html.escape(str(r.get('mb_pais') or ''))} {html.escape(str(r.get('mb_tipo') or ''))}</td>"
            f"<td>{html.escape(r['status'])}</td></tr>")
    (saida / "conferir.html").write_text(
        "<meta charset='utf-8'><title>Conferir artistas</title>"
        "<style>body{font-family:sans-serif}td{border-bottom:1px solid #ccc;padding:6px;vertical-align:top}</style>"
        "<h2>Conferir artistas</h2><table>" + "".join(linhas) + "</table>", encoding="utf-8")
    print(f"\nAbra: {saida / 'conferir.html'}")


if __name__ == "__main__":
    main()
