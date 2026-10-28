"""Testa o leitor de nomes em cima do cache da biblioteca atual do Sonora.

    python testar_nomes.py cache.json [saida.csv]

Mostra quantas faixas foram identificadas, quantos artistas existem e uma
amostra para voce conferir a olho.
"""
import collections
import csv
import json
import random
import sys

from nomes import ler_nome


def main(caminho, saida=None):
    dados = json.load(open(caminho, encoding="utf-8"))
    arvore = dados["arvore"]
    pastas = {p["id"]: p for p in arvore if p["tipo"] == "pasta"}
    faixas = [x for x in arvore if x["tipo"] == "faixa"]

    def passada(conhecidos):
        saida_ = []
        for f in faixas:
            pai = pastas.get(f["paiId"])
            avo = pastas.get(pai["paiId"]) if pai else None
            r = ler_nome(f["name"], pai["name"] if pai else None, avo["name"] if avo else None, conhecidos)
            saida_.append((f, pai["name"] if pai else "", r))
        return saida_

    # 1a passada: so o que o proprio nome do arquivo diz. Os artistas que aparecem
    # 2+ vezes viram "conhecidos" e so entao a pasta pode ser usada como artista.
    primeira = passada(None)
    cont = collections.Counter(r.chave_artista for _, _, r in primeira
                               if r.chave_artista and r.confianca == "alta")
    conhecidos = {k for k, n in cont.items() if n >= 2}
    leituras = passada(conhecidos)

    total = len(leituras)
    por_conf = collections.Counter(r.confianca for _, _, r in leituras)
    print(f"Faixas: {total}")
    for k in ("alta", "media", "baixa", "nenhuma"):
        print(f"  {k:8} {por_conf[k]:6}  {por_conf[k] / total:5.1%}")

    artistas = collections.Counter(r.chave_artista for _, _, r in leituras if r.chave_artista)
    print(f"Artistas distintos: {len(artistas)}")
    print("Mais frequentes:", ", ".join(f"{a} ({n})" for a, n in artistas.most_common(12)))
    unicos = sum(1 for n in artistas.values() if n == 1)
    print(f"Artistas com so 1 faixa (suspeitos de erro de leitura): {unicos}")

    sug = sum(1 for _, _, r in leituras if r.confianca == "baixa" and r.artista_sugerido)
    print(f"Faixas 'baixa' que ja tem artista sugerido pela pasta: {sug}")
    pior = collections.Counter(p for _, p, r in leituras if r.confianca == "baixa")
    print("Pastas com mais faixas sem artista:", "; ".join(f"{p} ({n})" for p, n in pior.most_common(8)))

    random.seed(7)
    for conf in ("alta", "media", "baixa"):
        grupo = [x for x in leituras if x[2].confianca == conf]
        print(f"\n--- amostra '{conf}' ---")
        for f, pasta, r in random.sample(grupo, min(12, len(grupo))):
            print(f"  [{pasta[:22]:22}] {f['name'][:60]:60} => {r.artista!r} | {r.titulo!r}"
                  + (f" | {r.versao}" if r.versao else ""))

    if saida:
        with open(saida, "w", newline="", encoding="utf-8-sig") as fh:
            w = csv.writer(fh, delimiter=";")
            w.writerow(["arquivo", "pasta", "artista", "artista_sugerido", "titulo", "versao", "convidados", "confianca", "origem"])
            for f, pasta, r in leituras:
                w.writerow([f["name"], pasta, r.artista or "", r.artista_sugerido or "", r.titulo or "", r.versao or "",
                            ", ".join(r.convidados), r.confianca, r.origem])
        print(f"\nCSV salvo em {saida}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
