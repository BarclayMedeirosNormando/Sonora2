"""Organiza e renomeia musicas soltas sozinho, sem perguntar nada.

    py organizar_musicas.py "<pasta com as musicas>"                 # so MOSTRA o plano (nao mexe em nada)
    py organizar_musicas.py "<pasta>" --destino "<pasta de saida>"   # define para onde vao
    py organizar_musicas.py "<pasta>" --aplicar                      # faz de verdade
    py organizar_musicas.py --desfazer                               # volta a ultima rodada

Para cada arquivo de musica (procura em subpastas tambem):
  1. le as tags do MP3 (artista, titulo, album, faixa), se existirem  [precisa: py -m pip install mutagen]
  2. se nao tiver tag, le o NOME do arquivo (mesmo leitor do Sonora) e o nome da pasta ("Artista - Album")
  3. renomeia para  NN - Artista - Titulo.mp3  e guarda assim:

        <destino>\\Artista\\Artista - Album\\NN - Artista - Titulo.mp3     (quando se sabe o album)
        <destino>\\Artista\\Artista - Titulo.mp3                            (quando nao se sabe)
        <destino>\\_Revisar\\nome-original.mp3                              (quando NAO deu para saber o artista)

Por padrao so mostra o plano e grava plano_organizar.csv (abra no Excel e confira). Com --aplicar
move os arquivos e grava organizar_log.csv, que o --desfazer usa. Use --copiar para manter os originais.
Nao reescreve tags nem apaga nada.
"""
import argparse
import csv
import re
import shutil
import sys
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "etapa1_nomes"))
from nomes import ler_nome, chave  # noqa: E402

try:
    import mutagen  # type: ignore
except ImportError:
    mutagen = None

SEM_TAGS = False
ONLINE = True
CONHECIDOS = set()   # chaves de artistas ja confirmados (etapa1_nomes/saida/artistas.json)


def carregar_conhecidos():
    import json
    arq = Path(__file__).resolve().parent / "etapa1_nomes" / "saida" / "artistas.json"
    if not arq.exists():
        return
    try:
        banco = json.loads(arq.read_text(encoding="utf-8"))
    except Exception:
        return
    CONHECIDOS.update(k for k, v in banco.items() if v.get("status") in ("ok", "sem-genero") and v.get("foto"))
    CONHECIDOS.update(k for k, v in banco.items() if v.get("status") == "ok")


def corrigir_ordem(stem):
    """'03 Titulo - Artista' -> '03 Artista - Titulo' quando so o lado direito e um artista conhecido."""
    m = re.match(r"^(\s*\d{1,3}\s*[-._)]?\s+)?(.*)$", stem)
    prefixo, resto = (m.group(1) or ""), m.group(2)
    partes = re.split(r"\s+[-–—]\s+", resto)
    if len(partes) != 2:
        return stem, False
    a, b = partes
    ka, kb = chave(a.replace("_", " ")), chave(b.replace("_", " "))
    if kb in CONHECIDOS and ka not in CONHECIDOS:
        return f"{prefixo}{b} - {a}", True
    if ka not in CONHECIDOS and kb not in CONHECIDOS and ONLINE:
        # nenhum lado conhecido: pergunta ao Deezer qual dos dois e nome de artista
        fa, fb = deezer_e_artista(a), deezer_e_artista(b)
        if fb and (not fa or fb >= 5 * fa):
            CONHECIDOS.add(kb)
            return f"{prefixo}{b} - {a}", True
        if fa and (not fb or fa >= 5 * fb):
            CONHECIDOS.add(ka)
        elif fa and fb:
            print(f"  (duvida: '{a}' e '{b}' existem como artista no Deezer; deixei '{a}' como artista)")
    return stem, False


_CACHE_DZ = {}


def deezer_e_artista(nome):
    """Numero de fas do artista do Deezer com exatamente esse nome (0 = nao existe)."""
    global ONLINE
    k = chave(nome.replace("_", " "))
    if not k:
        return 0
    if k in _CACHE_DZ:
        return _CACHE_DZ[k]
    import json
    import time
    import urllib.parse
    import urllib.request
    ok = 0
    try:
        url = "https://api.deezer.com/search/artist?limit=5&q=" + urllib.parse.quote(nome.replace("_", " "))
        with urllib.request.urlopen(url, timeout=10) as r:
            dados = json.loads(r.read().decode("utf-8"))
        ok = max([d.get("nb_fan", 0) or 1 for d in dados.get("data", []) if chave(d.get("name", "")) == k] or [0])
        time.sleep(0.25)
    except Exception:
        ONLINE = False
        print("(Deezer fora do ar nesta rede: sigo so com os artistas ja conhecidos)")
        return 0
    _CACHE_DZ[k] = ok
    return ok


LOG = Path(__file__).with_name("organizar_log.csv")
PLANO = Path(__file__).with_name("plano_organizar.csv")
EXT = {".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac"}
ILEGAIS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
PASTA_ARTISTA_ALBUM = re.compile(r"^(.+?)\s+[-–—]\s+(.+)$")


def limpar(txt):
    txt = unicodedata.normalize("NFKC", txt or "")
    txt = ILEGAIS.sub("", txt)
    return re.sub(r"\s+", " ", txt).strip(" .-")


def tags(caminho):
    """(artista, titulo, album, faixa) das tags do arquivo; None onde nao houver."""
    if mutagen is None:
        return None, None, None, None
    try:
        f = mutagen.File(caminho, easy=True)
    except Exception:
        return None, None, None, None
    if not f:
        return None, None, None, None
    g = lambda k: (f.get(k) or [None])[0]
    faixa = None
    m = re.match(r"\s*(\d+)", str(g("tracknumber") or ""))
    if m:
        faixa = int(m.group(1))
    return g("artist") or g("albumartist"), g("title"), g("album"), faixa


def principal(artista):
    """'A feat. B' / 'A, B' -> 'A' (o artista principal fica na pasta)."""
    a = re.split(r"\s+(?:feat\.?|ft\.?|featuring)\s+", artista or "", maxsplit=1, flags=re.I)[0]
    if "," in a and not re.search(r",\s*wind\b", a, re.I):
        a = a.split(",")[0]
    return limpar(a)


KW = re.compile(r"ao vivo|live|remaster(?:ed)?|remix|mix|edit|radio|acoustic|ac[uú]stic[oa]|vers[aã]o|version|demo|"
                r"instrumental|mono|stereo|deluxe|bonus|single|explicit|original|album|[aá]lbum", re.I)


def so_versao(txt):
    """'Ao Vivo', '2013 Remaster', 'Remix' -> True (descreve a versao). 'Atitude 67 (Ao Vivo)' -> False (e um nome)."""
    resto = KW.sub(" ", txt or "")
    return not re.search(r"[^\W\d_]", resto)


def tirar_album(stem):
    """'Artista - Titulo (Album)' -> ('Artista - Titulo', 'Album'). Mantem '(Ao Vivo)', '(2013 Remaster)'."""
    s = stem.rstrip()
    if not s.endswith(")"):
        return stem, None
    fundo, i = 0, len(s) - 1
    while i >= 0:
        fundo += (s[i] == ")") - (s[i] == "(")
        if fundo == 0:
            break
        i -= 1
    if i <= 0 or fundo != 0:
        return stem, None
    conteudo, prefixo = s[i + 1:-1].strip(), s[:i].rstrip()
    if not conteudo or not prefixo or so_versao(conteudo) or re.match(r"(feat|ft)\b", conteudo, re.I):
        return stem, None
    return prefixo, conteudo


def normalizar_titulo(titulo):
    """'Saideira - Ao Vivo' -> 'Saideira (Ao Vivo)'; 'Hotel California - 2013 Remaster' -> '... (2013 Remaster)'."""
    m = re.match(r"^(.*?)\s+[-–—]\s+(.+)$", titulo or "")
    if m and so_versao(m.group(2)):
        return f"{m.group(1).strip()} ({m.group(2).strip()})"
    return titulo


def base_comparavel(txt):
    t = re.sub(r"[\(\[]([^()\[\]]*)[\)\]]", lambda m: " " if so_versao(m.group(1)) else m.group(0), txt or "")
    return chave(KW.sub(" ", t))


def planejar(origem, destino):
    arquivos = sorted(p for p in origem.rglob("*") if p.is_file() and p.suffix.lower() in EXT
                      and destino not in p.parents)
    linhas = []
    print(f"{len(arquivos)} arquivos de musica encontrados. Lendo...", flush=True)
    for i, p in enumerate(arquivos, 1):
        if i % 25 == 0 or i == len(arquivos):
            print(f"  {i}/{len(arquivos)}", flush=True)
        pasta = p.parent.name
        t_art, t_tit, t_alb, t_faixa = (None,) * 4 if SEM_TAGS else tags(p)
        stem_orig, invertido = corrigir_ordem(p.stem)       # "Titulo - Artista" -> "Artista - Titulo"
        stem2, album_nome = tirar_album(stem_orig)           # "(Album)" no fim do nome
        r = ler_nome(stem2 + p.suffix, pasta, p.parent.parent.name if p.parent.parent != p.parent else None, None)
        artista = principal(t_art) if t_art else None
        artista_arq = artista
        titulo = limpar(t_tit) if t_tit else None
        album = limpar(t_alb) if t_alb else None
        faixa = t_faixa
        fonte = "tag" if artista and titulo else ""
        if not artista and r.artista and r.confianca in ("alta", "media"):
            artista, fonte = principal(r.artista), ("nome-invertido" if invertido else "nome")
            artista_arq = artista + ("".join(", " + limpar(c) for c in r.convidados) if r.convidados else "")
            titulo = titulo or limpar(r.titulo)
            if not album and album_nome:
                album = limpar(album_nome)
        if not titulo and r.titulo:
            titulo = limpar(r.titulo)
        if titulo and r.versao and not t_tit and r.versao.lower() not in titulo.lower():
            titulo = f"{titulo} ({limpar(r.versao).title()})"     # mantem "(Ao Vivo)", "(Remix)"...
        if titulo and not t_tit:
            titulo = limpar(normalizar_titulo(titulo))
        # album igual ao titulo = faixa avulsa (single): sem pasta de album
        if album and titulo and base_comparavel(album) == base_comparavel(titulo):
            album = None
        # pasta no formato "Artista - Album"
        m = PASTA_ARTISTA_ALBUM.match(pasta)
        if m:
            if not artista and chave(m.group(1)) and len(m.group(1)) <= 60:
                artista, fonte = principal(m.group(1)), "pasta"
                artista_arq = artista
            if not album and artista and chave(m.group(1)) == chave(artista):
                album = limpar(m.group(2))
        if faixa is None:
            n = re.match(r"^\s*(\d{1,3})\s*[-._)]?\s+\S", p.stem)
            if n and not re.fullmatch(r"\d+", p.stem.strip()):
                faixa = int(n.group(1))
        linhas.append({"origem": p, "artista": artista, "artista_arq": artista_arq or artista, "titulo": titulo,
                       "album": album, "faixa": faixa, "fonte": fonte, "confianca": r.confianca})

    # numeracao dentro de cada album: se faltar numero ou houver repetido (ex.: todos "01"), numera pela ordem do nome
    por_album = defaultdict(list)
    for l in linhas:
        if l["artista"] and l["album"]:
            por_album[(chave(l["artista"]), chave(l["album"]))].append(l)
    for grupo in por_album.values():
        nums = [l["faixa"] for l in grupo]
        if None in nums or len(set(nums)) != len(nums):
            for n, l in enumerate(sorted(grupo, key=lambda x: x["origem"].name.casefold()), 1):
                l["faixa"] = n

    ocupados = set()
    for l in linhas:
        ext = l["origem"].suffix.lower()
        if not (l["artista"] and l["titulo"]):
            l["destino"] = destino / "_Revisar" / l["origem"].name
            l["situacao"] = "revisar"
        else:
            art, tit = l["artista"], l["titulo"]
            arq = l["artista_arq"]
            if l["album"]:
                nome = f"{l['faixa']:02d} - {arq} - {tit}{ext}"
                l["destino"] = destino / limpar(art) / limpar(f"{art} - {l['album']}") / limpar(nome)
            else:
                l["destino"] = destino / limpar(art) / (limpar(f"{arq} - {tit}") + ext)
            l["situacao"] = "ok"
        # nome repetido: (2), (3)...
        d = l["destino"]
        n = 1
        while str(d).casefold() in ocupados or (d.exists() and d != l["origem"]):
            n += 1
            d = d.with_name(f"{l['destino'].stem} ({n}){l['destino'].suffix}")
        l["destino"] = d
        ocupados.add(str(d).casefold())
    return linhas


def gravar_log(pares):
    novo = not LOG.exists()
    with open(LOG, "a", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        if novo:
            w.writerow(["quando", "de", "para"])
        agora = datetime.now().isoformat(timespec="seconds")
        w.writerows([[agora, str(de), str(para)] for de, para in pares])


def desfazer():
    if not LOG.exists():
        sys.exit("Nenhum registro de organizacao.")
    linhas = list(csv.reader(open(LOG, newline="", encoding="utf-8-sig"), delimiter=";"))[1:]
    if not linhas:
        sys.exit("Nada para desfazer.")
    ultimo = linhas[-1][0]
    lote = [l for l in linhas if l[0] == ultimo]
    print(f"Desfazendo {len(lote)} arquivos de {ultimo}...")
    ok = 0
    for _, de, para in reversed(lote):
        de, para = Path(de), Path(para)
        if para.exists() and not de.exists():
            de.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(para), str(de))
            ok += 1
            pai = para.parent                       # limpa pastas que ficaram vazias
            while pai.exists() and not any(pai.iterdir()) and pai.name:
                pai.rmdir()
                pai = pai.parent
    resto = [l for l in linhas if l[0] != ultimo]
    with open(LOG, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["quando", "de", "para"])
        w.writerows(resto)
    print(f"Pronto: {ok} voltaram para o lugar de origem.")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("origem", nargs="?")
    ap.add_argument("--destino")
    ap.add_argument("--aplicar", action="store_true")
    ap.add_argument("--copiar", action="store_true")
    ap.add_argument("--desfazer", action="store_true")
    ap.add_argument("--sem-tags", action="store_true",
                    help="nao le as tags dos MP3 (rapido; use quando a pasta esta no Drive em nuvem)")
    ap.add_argument("--sem-internet", action="store_true",
                    help="nao consulta o Deezer para decidir 'Artista - Titulo' x 'Titulo - Artista'")
    a = ap.parse_args()
    global SEM_TAGS, ONLINE
    SEM_TAGS = a.sem_tags
    ONLINE = not a.sem_internet
    if a.desfazer:
        return desfazer()
    if not a.origem:
        ap.error("informe a pasta com as musicas")
    origem = Path(a.origem)
    if not origem.is_dir():
        sys.exit(f"Pasta nao encontrada: {origem}")
    destino = Path(a.destino) if a.destino else origem.with_name(origem.name + "_Organizadas")
    if mutagen is None:
        print("(aviso: 'mutagen' nao instalado - so vou usar o nome dos arquivos. "
              "Para ler as tags: py -m pip install mutagen)\n")

    carregar_conhecidos()
    print(f"({len(CONHECIDOS)} artistas conhecidos ajudam a decidir 'Artista - Titulo' x 'Titulo - Artista')\n")
    linhas = planejar(origem, destino)
    if not linhas:
        sys.exit("Nenhuma musica encontrada.")
    with open(PLANO, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["situacao", "fonte", "artista", "artista_conhecido", "album", "de", "para"])
        for l in linhas:
            w.writerow([l["situacao"], l["fonte"], l["artista"] or "",
                        "sim" if l["artista"] and chave(l["artista"]) in CONHECIDOS else "nao",
                        l["album"] or "", l["origem"], l["destino"]])

    c = Counter(l["situacao"] for l in linhas)
    artistas = {chave(l["artista"]) for l in linhas if l["artista"]}
    print(f"{len(linhas)} musicas | {c['ok']} identificadas ({len(artistas)} artistas) | {c['revisar']} para revisar")
    novos = sorted({l["artista"] for l in linhas if l["artista"] and chave(l["artista"]) not in CONHECIDOS})
    if novos:
        print(f"{len(novos)} artistas ainda desconhecidos pelo Sonora (confira se nao sao titulos): "
              + ", ".join(novos[:15]) + (" ..." if len(novos) > 15 else ""))
    print(f"Destino: {destino}\n")
    for l in linhas[:12]:
        print(f"  {l['origem'].name}\n    -> {l['destino'].relative_to(destino)}   [{l['fonte'] or '?'}]")
    if len(linhas) > 12:
        print(f"  ... e mais {len(linhas) - 12} (veja {PLANO.name})")

    if not a.aplicar:
        print(f"\nNada foi alterado. Confira {PLANO.name} e rode de novo com --aplicar.")
        return
    feitos = []
    for l in linhas:
        if l["situacao"] == "revisar":
            continue                      # nao identificado: fica na pasta de origem
        l["destino"].parent.mkdir(parents=True, exist_ok=True)
        if a.copiar:
            shutil.copy2(l["origem"], l["destino"])
        else:
            shutil.move(str(l["origem"]), str(l["destino"]))
        feitos.append((l["origem"], l["destino"]))
    gravar_log(feitos)
    print(f"\nPronto: {len(feitos)} arquivos {'copiados' if a.copiar else 'movidos'} para {destino}")
    if not a.copiar:
        print("Para voltar atras: py organizar_musicas.py --desfazer")
    if c["revisar"]:
        print(f"{c['revisar']} arquivo(s) NAO foram movidos (ficaram na pasta de origem): renomeie com renomear_musicas.py ou me mande a lista.")


if __name__ == "__main__":
    main()
