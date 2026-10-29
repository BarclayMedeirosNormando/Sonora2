"""Renomeia as musicas de uma pasta para o padrao do Sonora:  NN - Artista - Titulo.mp3

Uso (PowerShell):
    py renomear_musicas.py                  # pergunta a pasta
    py renomear_musicas.py "G:\\Meu Drive\\Musicas\\Sonora\\Rap\\Racionais MCs\\Album 1"
    py renomear_musicas.py --desfazer       # volta a ultima renomeacao

O que pergunta: pasta, artista, album (opcional). Depois mostra COMO VAI FICAR e so
renomeia se voce confirmar com "s". Tudo fica gravado em renomear_log.csv (para desfazer).

Regras:
  - mantem o numero da faixa que o arquivo ja tem; se nao tiver, numera pela ordem do nome
  - tira o "Artista - " do comeco do nome se ja existir (para nao ficar repetido)
  - "MC_s" vira "MC's" (o Drive troca ' por _)
  - se voce informar o album, a pasta tambem e renomeada para "Artista - Album"
"""
import csv
import re
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

LOG = Path(__file__).with_name("renomear_log.csv")
EXT = {".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac"}
ILEGAIS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
NUM = re.compile(r"^\s*(\d{1,3})\s*[-._)]?\s+(?=\S)|^\s*(\d{1,3})\s*[-._)]\s*")


def sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


def comparavel(s):
    return re.sub(r"[^a-z0-9]+", "", sem_acento(s).casefold())


def limpar(txt):
    txt = unicodedata.normalize("NFKC", txt)
    txt = re.sub(r"(?<=[A-Za-z0-9])_(?=(t|s|ll|re|ve|d|m)\b)", "'", txt)   # MC_s -> MC's
    txt = txt.replace(" _ ", " & ").replace("_", " ")
    txt = ILEGAIS.sub("", txt)
    return re.sub(r"\s+", " ", txt).strip(" .-")


def separar(nome_sem_ext, artista):
    """Devolve (numero ou None, titulo) a partir do nome atual do arquivo."""
    t = limpar(nome_sem_ext)
    numero = None
    m = NUM.match(t)
    if m and not re.fullmatch(r"\d+", t):
        numero = int(m.group(1) or m.group(2))
        t = t[m.end():].strip(" .-")
    # "Artista - Titulo" -> "Titulo" (so se o lado esquerdo for o artista informado)
    partes = re.split(r"\s+[-–—]\s+", t, maxsplit=1)
    if len(partes) == 2 and comparavel(partes[0]) == comparavel(artista):
        t = partes[1].strip()
    return numero, t or limpar(nome_sem_ext)


def perguntar(msg, padrao=None, obrigatorio=True):
    while True:
        r = input(msg + (f" [{padrao}]" if padrao else "") + ": ").strip().strip('"')
        if not r and padrao:
            return padrao
        if r or not obrigatorio:
            return r


def gravar_log(pares):
    novo = not LOG.exists()
    with open(LOG, "a", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        if novo:
            w.writerow(["quando", "de", "para"])
        agora = datetime.now().isoformat(timespec="seconds")
        for de, para in pares:
            w.writerow([agora, str(de), str(para)])


def desfazer():
    if not LOG.exists():
        print("Nenhum registro de renomeacao.")
        return
    linhas = list(csv.reader(open(LOG, newline="", encoding="utf-8-sig"), delimiter=";"))[1:]
    if not linhas:
        print("Nada para desfazer.")
        return
    ultimo = linhas[-1][0]
    lote = [l for l in linhas if l[0] == ultimo]
    print(f"Desfazendo {len(lote)} renomeacoes de {ultimo}...")
    for _, de, para in reversed(lote):            # volta do fim para o comeco (pasta por ultimo)
        if Path(para).exists() and not Path(de).exists():
            Path(para).rename(de)
    restante = [l for l in linhas if l[0] != ultimo]
    with open(LOG, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["quando", "de", "para"])
        w.writerows(restante)
    print("Pronto.")


def processar(pasta):
    pasta = Path(pasta)
    if not pasta.is_dir():
        print(f"Pasta nao encontrada: {pasta}")
        return
    arquivos = sorted((p for p in pasta.iterdir() if p.is_file() and p.suffix.lower() in EXT),
                      key=lambda p: p.name.casefold())
    if not arquivos:
        print("Nenhum arquivo de musica nessa pasta.")
        return
    print(f"\n{len(arquivos)} musicas em: {pasta}")
    artista = limpar(perguntar("Nome do artista"))
    album = limpar(perguntar("Nome do album (Enter para pular)", obrigatorio=False))

    lidos = [(p,) + separar(p.stem, artista) for p in arquivos]
    usados = {n for _, n, _ in lidos if n}
    prox = 1
    plano = []
    for p, num, titulo in lidos:
        if num is None:
            while prox in usados:
                prox += 1
            num = prox
            usados.add(num)
        plano.append((p, f"{num:02d} - {artista} - {titulo}{p.suffix.lower()}"))

    # nomes repetidos: acrescenta (2), (3)...
    vistos = {}
    for i, (p, novo) in enumerate(plano):
        k = novo.casefold()
        if k in vistos:
            vistos[k] += 1
            base = Path(novo)
            plano[i] = (p, f"{base.stem} ({vistos[k]}){base.suffix}")
        else:
            vistos[k] = 1

    print("\nVai ficar assim:\n")
    for p, novo in plano:
        print(f"  {p.name}\n    -> {novo}")
    nova_pasta = None
    if album:
        nova_pasta = pasta.with_name(limpar(f"{artista} - {album}"))
        print(f"\n  Pasta: {pasta.name}\n    -> {nova_pasta.name}")
    if input("\nRenomear? (s/n): ").strip().lower() != "s":
        print("Cancelado, nada foi alterado.")
        return

    feitos = []
    for p, novo in plano:
        destino = p.with_name(novo)
        if destino == p:
            continue
        if destino.exists():
            print(f"  ! ja existe, pulei: {novo}")
            continue
        p.rename(destino)
        feitos.append((p, destino))
    if nova_pasta and nova_pasta != pasta:
        if nova_pasta.exists():
            print(f"  ! a pasta {nova_pasta.name} ja existe, nao renomeei a pasta")
        else:
            pasta.rename(nova_pasta)
            feitos.append((pasta, nova_pasta))   # a pasta por ultimo: ao desfazer, ela volta primeiro
    gravar_log(feitos)
    print(f"\nPronto: {len(feitos)} itens renomeados. Para voltar: py renomear_musicas.py --desfazer")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    args = sys.argv[1:]
    if args and args[0] == "--desfazer":
        desfazer()
        return
    pasta = args[0] if args else perguntar("Pasta com as musicas (cole o caminho)")
    while True:
        processar(pasta)
        if input("\nOutra pasta? (s/n): ").strip().lower() != "s":
            break
        pasta = perguntar("Pasta com as musicas (cole o caminho)")


if __name__ == "__main__":
    main()
