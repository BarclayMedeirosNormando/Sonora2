#!/usr/bin/env python3
"""Renomeia todas as musicas de uma pasta de uma vez: voce digita so o cantor/banda.

Uso:
  py renomear_manual.py "G:\\Meu Drive\\Musicas\\Entrada"
  py renomear_manual.py --desfazer          (volta a ultima rodada)

Pergunta o cantor/banda uma unica vez e renomeia todos os arquivos para 'Artista - Musica.ext'
(o titulo e o proprio nome do arquivo, sem o numero da faixa). Mostra a lista e so renomeia
depois que voce confirmar com 's'.
"""
import argparse
import csv
import re
import sys
from datetime import datetime
from pathlib import Path

EXT = {".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac"}
LOG = Path(__file__).with_name("renomear_manual_log.csv")
ILEGAIS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def limpar(txt):
    txt = ILEGAIS.sub("", txt.replace("_", " "))
    return re.sub(r"\s+", " ", txt).strip(" .-")


def sugestao_titulo(stem):
    """Tira numero de faixa do comeco: '03 - Sailing' -> 'Sailing'."""
    t = re.sub(r"^\s*\d{1,3}\s*[-._)]?\s+", "", stem.replace("_", " "))
    return limpar(t)


def desfazer():
    if not LOG.exists():
        sys.exit("Nada para desfazer.")
    with LOG.open(encoding="utf-8", newline="") as f:
        linhas = list(csv.DictReader(f, delimiter=";"))
    if not linhas:
        sys.exit("Nada para desfazer.")
    ultimo = linhas[-1]["rodada"]
    n = 0
    for l in reversed([x for x in linhas if x["rodada"] == ultimo]):
        novo, velho = Path(l["para"]), Path(l["de"])
        if novo.exists() and not velho.exists():
            novo.rename(velho)
            n += 1
    restantes = [x for x in linhas if x["rodada"] != ultimo]
    with LOG.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["rodada", "de", "para"], delimiter=";")
        w.writeheader()
        w.writerows(restantes)
    print(f"{n} arquivos voltaram ao nome anterior.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pasta", nargs="?")
    ap.add_argument("--desfazer", action="store_true")
    a = ap.parse_args()
    if a.desfazer:
        return desfazer()
    if not a.pasta:
        ap.error("informe a pasta com as musicas")
    pasta = Path(a.pasta)
    if not pasta.is_dir():
        sys.exit(f"Pasta nao encontrada: {pasta}")
    arquivos = sorted(p for p in pasta.iterdir() if p.is_file() and p.suffix.lower() in EXT)
    if not arquivos:
        sys.exit("Nenhuma musica encontrada.")

    print(f"{len(arquivos)} musicas encontradas em {pasta}")
    try:
        artista = limpar(input("Cantor/banda de TODAS essas musicas: "))
    except (EOFError, KeyboardInterrupt):
        sys.exit("\nCancelado. Nada foi alterado.")
    if not artista:
        sys.exit("Precisa informar o cantor/banda. Nada foi alterado.")

    plano = []
    for p in arquivos:
        titulo = sugestao_titulo(p.stem)
        if titulo.lower().startswith(artista.lower() + " - "):
            titulo = titulo[len(artista) + 3:]          # ja estava como 'Artista - Musica'
        if not titulo:
            print(f"  (sem titulo, pulei: {p.name})")
            continue
        plano.append((p, p.with_name(f"{artista} - {titulo}{p.suffix.lower()}")))

    plano = [(p, n) for p, n in plano if p != n]
    if not plano:
        sys.exit("Nada para renomear.")
    print("\n=== RESUMO ===")
    for p, n in plano:
        print(f"  {p.name}\n    -> {n.name}")
    if input(f"\nRenomear {len(plano)} arquivos? (s/N): ").strip().lower() != "s":
        sys.exit("Cancelado. Nada foi alterado.")

    rodada = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    feitos = []
    for p, n in plano:
        if n.exists():
            print(f"  ja existe, pulei: {n.name}")
            continue
        p.rename(n)
        feitos.append((p, n))
    novo_log = not LOG.exists()
    with LOG.open("a", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter=";")
        if novo_log:
            w.writerow(["rodada", "de", "para"])
        for p, n in feitos:
            w.writerow([rodada, str(p), str(n)])
    print(f"\nPronto: {len(feitos)} arquivos renomeados. Para voltar atras: py renomear_manual.py --desfazer")


if __name__ == "__main__":
    main()
