"""Etapa 2b: decide o GENERO FINAL de cada artista (sem internet).

Junta duas fontes:
  1. tags do MusicBrainz (saida/artistas.json)  -> mapeadas para uma lista fixa de generos
  2. nomes das pastas onde as musicas do artista estao (resultado.csv)

    python generos.py resultado.csv saida/artistas.json

Gera saida/generos.csv e imprime quanto as duas fontes concordam entre si.
"""
import collections
import csv
import json
import re
import sys
from pathlib import Path

from nomes import chave, sem_acento

# (palavra-chave, genero). A ORDEM importa: a primeira que casar vence.
REGRAS = [
    (r"piseiro|pisadinha", "Piseiro"),
    (r"forro|xote|baiao|forr[oó]", "Forró"),
    (r"sertanej|country|moda de viola|caipira", "Sertanejo"),
    (r"axe\b|ax[eé]|samba-reggae", "Axé"),
    (r"pagode|samba", "Pagode/Samba"),
    (r"mpb|bossa nova|tropicalia|musica popular brasileira", "MPB"),
    (r"brega|bolero|cabare|romantico brega", "Brega"),
    (r"gospel|christian|worship|louvor|adora[cç]", "Gospel"),
    (r"funk (carioca|brasil)|baile funk|\bfunk\b", "Funk"),
    (r"hip.?hop|\brap\b|gangsta|trap", "Rap"),
    (r"reggae|\bska\b|\bdub\b|raggae", "Reggae"),
    (r"blues", "Blues"),
    (r"disco|eurodance|italo", "Discoteca"),
    (r"pop rock|soft rock|alternative|new wave", "Rock"),
    (r"dance.?pop|\bpop\b|synth.?pop|teen pop", "Pop"),
    (r"electro|edm|house|techno|trance|\bdance\b|eletr[oô]nic|dubstep|drum and bass", "Eletrônica"),
    (r"metal|hard rock|punk|grunge|rock|alternative|progressive|psychedelic|new wave|hardcore", "Rock"),
    (r"r&b|\bsoul\b|rhythm and blues", "R&B/Soul"),
    (r"adult contemporary|romantic|romantica|love songs|ballad", "Românticas"),
    (r"jazz", "Jazz"),
    (r"classical|classica|instrumental|orquestra", "Clássica"),
]
_COMPILADAS = [(re.compile(p), g) for p, g in REGRAS]

# Tags que nao dizem genero nenhum.
_IGNORAR = re.compile(r"^(\d{4}s|\d{2}s|singer-songwriter|brazil|brazilian|latin|promessa|american|british|"
                      r"seen live|favorites?|male vocalists?|female vocalists?|00s|10s|20s|90s|80s|70s|60s)$")


def mapear(texto):
    t = sem_acento(texto).casefold()
    for rx, g in _COMPILADAS:
        if rx.search(t):
            return g
    return None


# Generos "especificos": dizem mais que Pop/Rock e vencem quando aparecem entre as tags.
ESPECIFICOS = {"Piseiro", "Forró", "Sertanejo", "Axé", "Pagode/Samba", "MPB", "Brega", "Gospel",
               "Funk", "Rap", "Reggae"}


def genero_por_tags(tags):
    mapeados = []
    for tag in (tags or [])[:5]:
        if _IGNORAR.match(sem_acento(tag).casefold().strip()):
            continue
        g = mapear(tag)
        if g:
            mapeados.append(g)
    for g in mapeados:
        if g in ESPECIFICOS:
            return g
    return mapeados[0] if mapeados else None


def genero_por_pastas(pastas):
    """pastas: Counter {nome_da_pasta: quantas faixas do artista}."""
    votos = collections.Counter()
    for p, n in pastas.items():
        g = mapear(p)
        if g in ESPECIFICOS:
            votos[g] += n
    if not votos:
        return None, 0.0
    g, n = votos.most_common(1)[0]
    return g, n / sum(votos.values())


def main(csv_path, json_path):
    banco = json.loads(Path(json_path).read_text(encoding="utf-8"))
    pastas_do_artista = collections.defaultdict(collections.Counter)
    with open(csv_path, newline="", encoding="utf-8-sig") as fh:
        for l in csv.DictReader(fh, delimiter=";"):
            a = (l.get("artista") or "").strip()
            if a and l.get("confianca") in ("alta", "media"):
                pastas_do_artista[chave(a)][l["pasta"]] += 1

    saida = Path(json_path).parent / "generos.csv"
    stat = collections.Counter()
    concordam = discordam = 0
    divergentes = []
    with open(saida, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["artista", "faixas", "genero", "fonte", "genero_tags", "genero_pasta", "tags_brutas"])
        for k, r in sorted(banco.items(), key=lambda kv: -kv[1]["faixas"]):
            gt = genero_por_tags(r.get("mb_tags"))
            gp, forca = genero_por_pastas(pastas_do_artista.get(k, {}))
            if gt and gp:
                if gt == gp:
                    concordam += 1
                else:
                    discordam += 1
                    divergentes.append((r["nome"], gt, gp))
            if gt:
                final, fonte = gt, "tags"
            elif gp:
                final, fonte = gp, "pasta"
            else:
                final, fonte = "", "nenhuma"
            stat[fonte] += 1
            w.writerow([r["nome"], r["faixas"], final, fonte, gt or "", gp or "", ", ".join(r.get("mb_tags", []))])

    total = len(banco)
    print(f"Artistas: {total}")
    for f in ("tags", "pasta", "nenhuma"):
        print(f"  genero via {f:8} {stat[f]:4}  {stat[f] / max(1, total):5.0%}")
    ambos = concordam + discordam
    if ambos:
        print(f"\nQuando as DUAS fontes opinam ({ambos} artistas): concordam em {concordam / ambos:.0%}")
        for n, a, b in divergentes[:12]:
            print(f"  divergem: {n:28} tags={a:12} pasta={b}")
    print(f"\nSalvo em {saida}")


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    main(sys.argv[1], sys.argv[2])
