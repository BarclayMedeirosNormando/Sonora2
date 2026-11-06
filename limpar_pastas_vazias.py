#!/usr/bin/env python3
"""Acha (e, se voce mandar, apaga) as pastas que NAO tem nenhuma musica dentro.

Uso:
  py limpar_pastas_vazias.py                      (so mostra; nao apaga nada)
  py limpar_pastas_vazias.py --apagar             (apaga as pastas 100% vazias, depois de confirmar)
  py limpar_pastas_vazias.py --apagar --com-outros (tambem apaga pastas sem musica que tem outros arquivos, ex.: capa.jpg)
  py limpar_pastas_vazias.py "G:\\outra\\pasta"    (outra pasta em vez da biblioteca padrao)

Arquivos de sistema (desktop.ini, Thumbs.db) nao contam como "outros arquivos".
Uma pasta "sem musica" e aquela cuja arvore inteira (ela e as subpastas) nao tem arquivo de audio.
Pastas que comecam com _ (ex.: _revisar) e a propria pasta raiz nunca sao apagadas.
No Google Drive para computador, o que e apagado vai para a Lixeira do Drive (da para restaurar).
Gera limpar_pastas_log.csv com o que foi apagado.
"""
import argparse
import csv
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

PADRAO = r"G:\Meu Drive\Musicas\Sonora_Musicas"
IGNORAR = {"desktop.ini", "thumbs.db", ".ds_store"}   # arquivos de sistema escondidos (o Drive cria desktop.ini em toda pasta)
AUDIO = {".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac", ".wma"}
LOG = Path(__file__).with_name("limpar_pastas_log.csv")


def varrer(raiz):
    """Devolve lista de (pasta, qtd_outros_arquivos) das pastas sem audio na arvore, da mais funda para a mais rasa."""
    tem_audio = {}
    outros = {}
    for atual, subs, arqs in os.walk(raiz, topdown=False):
        a = any(Path(n).suffix.lower() in AUDIO for n in arqs)
        a = a or any(tem_audio.get(os.path.join(atual, s), False) for s in subs)
        tem_audio[atual] = a
        outros[atual] = len(arqs)
    res = []
    for atual in tem_audio:
        if atual == str(raiz) or tem_audio[atual]:
            continue
        # ignora pastas _* e o que esta dentro delas
        partes = Path(atual).relative_to(raiz).parts
        if any(p.startswith("_") for p in partes):
            continue
        res.append(atual)
    res.sort(key=lambda p: -len(Path(p).parts))
    return res, outros


def total_arquivos(pasta):
    return sum(1 for _, _, fs in os.walk(pasta) for n in fs if n.lower() not in IGNORAR)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pasta", nargs="?", default=PADRAO)
    ap.add_argument("--apagar", action="store_true")
    ap.add_argument("--com-outros", action="store_true", help="tambem apaga pastas sem musica que tem outros arquivos")
    a = ap.parse_args()
    raiz = Path(a.pasta)
    if not raiz.is_dir():
        sys.exit(f"Pasta nao encontrada: {raiz}\n(O Google Drive para computador esta aberto e o G: aparece?)")
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    print(f"Varrendo {raiz} ...")
    pastas, _ = varrer(str(raiz))
    vazias, com_outros = [], []
    for p in pastas:
        (com_outros if total_arquivos(p) else vazias).append(p)
    print(f"\nPastas totalmente vazias: {len(vazias)}")
    for p in sorted(vazias)[:200]:
        print("   ", Path(p).relative_to(raiz))
    print(f"\nPastas sem musica mas com outros arquivos (capa, txt...): {len(com_outros)}")
    for p in sorted(com_outros)[:200]:
        print("   ", Path(p).relative_to(raiz), f"({total_arquivos(p)} arquivo(s))")
    if len(vazias) > 200 or len(com_outros) > 200:
        print("\n(mostrando so as 200 primeiras de cada lista)")
    alvo = vazias + (com_outros if a.com_outros else [])
    if not a.apagar:
        print("\nNada foi apagado. Para apagar: py limpar_pastas_vazias.py --apagar"
              + ("" if a.com_outros else "   (e --com-outros para incluir as da segunda lista)"))
        return
    if not alvo:
        print("\nNada para apagar.")
        return
    if input(f"\nApagar {len(alvo)} pastas? (s/N): ").strip().lower() != "s":
        sys.exit("Cancelado. Nada foi apagado.")
    rodada = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    feitas = []
    for p in alvo:                       # da mais funda para a mais rasa
        if not os.path.isdir(p):
            continue                     # ja foi junto com a mae
        try:
            shutil.rmtree(p)
            feitas.append(p)
        except OSError as e:
            print(f"  nao consegui apagar {p}: {e}")
    novo = not LOG.exists()
    with LOG.open("a", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter=";")
        if novo:
            w.writerow(["rodada", "pasta"])
        for p in feitas:
            w.writerow([rodada, p])
    print(f"\nPronto: {len(feitas)} pastas apagadas (no Drive elas ficam na Lixeira). Registro: {LOG.name}")


if __name__ == "__main__":
    main()
