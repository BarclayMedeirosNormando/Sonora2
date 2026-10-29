"""Leitor de nomes de arquivo do Sonora 2.0.

Recebe o nome de um arquivo MP3 (e, opcionalmente, o nome da pasta onde ele esta)
e devolve artista, titulo e uma nota de confianca. Usa so a biblioteca padrao.

Uso:
    from nomes import ler_nome
    r = ler_nome("03 - Akon - Beautiful.mp3", pasta="Hits")
    r.artista, r.titulo, r.confianca, r.origem
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

# Pastas que NAO dizem quem e o artista (genericas, de gênero ou de disco).
_PASTAS_GENERICAS = re.compile(
    r"^(cd\s*\d+|disc\s*\d+|disco\s*\d+|vol(ume)?\.?\s*\d+|playlists?|musicas?|m[uú]sicas?|"
    r"sonora|hits?|top\s*\d+|as melhores.*|o melhor.*|love songs.*|classicas?.*|"
    r"anos\s*\d+.*|flashback.*|download.*|novos?.*|diversos|varios|v[aá]rios)$",
    re.I,
)

# Marcas de "lixo" que vem do YouTube/rips e atrapalham a leitura.
_RUIDO = re.compile(
    r"[\(\[]\s*(official\s*(music\s*)?(video|audio|lyric\s*video|clip)|video\s*oficial|"
    r"clipe\s*oficial|lyric\s*video|lyrics?|audio\s*oficial|hd|hq|4k|"
    r"letra|legendado|com letra|download)\s*[\)\]]",
    re.I,
)
_VERSAO = re.compile(
    r"[\(\[]\s*(ao vivo[^\)\]]*|live[^\)\]]*|remaster(ed)?[^\)\]]*|acoustic[^\)\]]*|"
    r"ac[uú]stic[ao][^\)\]]*|radio edit[^\)\]]*|remix[^\)\]]*|vers[aã]o[^\)\]]*)\s*[\)\]]",
    re.I,
)
_FEAT = re.compile(r"\s+(?:feat\.?|ft\.?|featuring|part\.?|participa[cç][aã]o de)\s+", re.I)
_NUM_FAIXA = re.compile(r"^\s*(?:\d{1,3}\s*[-._)]\s*|(?:0\d{1,2}|\d{2,3})\s+)(?=\D)")
_SEP = re.compile(r"\s+[-–—]\s+")  # " - ", " – ", " — "


@dataclass
class Leitura:
    arquivo: str
    artista: str | None = None
    titulo: str | None = None
    versao: str | None = None      # "ao vivo", "remix"...
    artista_sugerido: str | None = None  # vindo da pasta, mas nao confirmado
    convidados: list[str] = field(default_factory=list)
    confianca: str = "nenhuma"      # alta | media | baixa | nenhuma
    origem: str = "-"               # arquivo | pasta | arquivo-sem-espaco | so-titulo
    chave_artista: str | None = None


def sem_acento(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


def chave(s: str) -> str:
    """Forma comparavel: sem acento, minuscula, so letras/numeros."""
    s = sem_acento(s).casefold().replace("&", " e ")
    s = re.sub(r"\b(the|os|as|o|a)\b", " ", s) if len(s) > 4 else s
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def _limpar_basico(txt: str) -> str:
    txt = unicodedata.normalize("NFKC", txt)  # ？ -> ?, etc.
    txt = re.sub(r"\.mp3$", "", txt, flags=re.I)
    # "Can_t", "MC_s", "I_m" -> apostrofo
    txt = re.sub(r"(?<=[A-Za-z])_(?=(t|s|ll|re|ve|d|m)\b)", "'", txt)
    txt = re.sub(r"(?<=\d)_(?=s\b)", "'", txt)       # 60_s -> 60's
    txt = re.sub(r"\b(feat|ft|jr|sr|dr|vol|part|pt)_", r"\1.", txt, flags=re.I)  # feat_ -> feat.
    txt = re.sub(r"(?<=[A-Z])_(?=[A-Z])", "/", txt)   # AC_DC -> AC/DC
    txt = re.sub(r"\s_\s", " / ", txt)               # "Bosco _ Vinicius" -> "Bosco / Vinicius"
    txt = txt.replace("_", " ")
    txt = re.sub(r"\s+", " ", txt).strip(" .-_")
    return txt


def _artista_valido(a: str | None) -> bool:
    if not a:
        return False
    a = a.strip()
    if len(a) < 2 or len(a) > 60:
        return False
    if not re.search(r"[A-Za-zÀ-ÿ]", a):
        return False
    if re.fullmatch(r"\d+", a):
        return False
    if re.search(r"[\(\)\[\]]", a):      # "Musica (feat. X)" e titulo, nao artista
        return False
    return not _PASTAS_GENERICAS.match(a)


def _artista_da_pasta(pasta: str | None) -> str | None:
    """'Pink Floyd - 1968 Germin ati' -> 'Pink Floyd'. Ignora pastas genericas."""
    if not pasta:
        return None
    p = _limpar_basico(pasta)
    if _PASTAS_GENERICAS.match(p):
        return None
    partes = _SEP.split(p, maxsplit=1)
    if len(partes) == 2 and _artista_valido(partes[0]):
        return partes[0].strip()
    return None


# Lado direito que descreve a versao (e nao um artista): "Live", "Mono", "Take 2-Master Version"...
_SO_VERSAO = re.compile(
    r"^(live|mono|stereo|ao vivo|with\s.*|remaster\w*|.*\b(version|edit|mix|demo|take\s*\d+|acoustic|single)\b.*)$",
    re.I)


def _sem_traco(nome):
    """'07 Titulo - Artista' (numero + espaco, sem traco depois do numero)."""
    t = _RUIDO.sub("", _limpar_basico(nome))
    return bool(re.match(r"^\d{1,3}\s+(?!-)\S", t)) and not re.match(r"^\d{1,3}\s*[-._)]", t)


def reparar_nomes(faixas, pastas, artistas_ok=None):
    """Corrige dois erros do leitor, olhando a biblioteca inteira.

    1) "50 Cent - Candy Shop": o "50 " NAO e numero de faixa, e parte do nome.
       (mesmo prefixo repetido em 3+ arquivos da mesma pasta)
    2) "18 Stars - Simply Red": ordem invertida (Titulo - Artista). So inverte quando
       o lado direito ja aparece como artista (lado esquerdo) em outros arquivos e o
       esquerdo so aparece nesse; ou quando a pasta inteira repete o lado direito
       (ex.: "Musica - DJefferSongs").

    Devolve (reparos, resumo): reparos = {id_faixa: (nome_para_ler, manter_numero)}.
    O nome real do arquivo nao e alterado, so o texto que o leitor recebe.
    """
    import collections

    pref = collections.Counter()
    for f in faixas:
        m = re.match(r"^\s*(\d{1,3}\s+[^-–—]+?)\s+[-–—]\s+\S", f["name"])
        if m:
            pref[(f["paiId"], chave(m.group(1)))] += 1
    num_artista = {k for (_, k), n in pref.items() if n >= 3}

    linhas = []  # (faixa, texto sem numero, esquerda, direita, manter_numero)
    for f in faixas:
        t = _RUIDO.sub("", _limpar_basico(f["name"]))
        manter = any(chave(t).startswith(k + " ") for k in num_artista) and \
            bool(re.match(r"^\s*\d", f["name"]))
        if not manter:
            t = _NUM_FAIXA.sub("", t).strip()
        partes = _SEP.split(_VERSAO.sub("", t).strip(" -"))
        if len(partes) == 2:
            linhas.append((f, t, partes[0].strip(), partes[1].strip(), manter))

    esq = collections.Counter(chave(a) for _, _, a, _, _ in linhas)
    por_pasta = collections.defaultdict(list)
    for f, _, a, b, _ in linhas:
        por_pasta[f["paiId"]].append((a, b))
    pastas_inv = set()
    for pid, lst in por_pasta.items():
        if len(lst) >= 6:
            dl = len({chave(a) for a, _ in lst})
            dr = len({chave(b) for _, b in lst})
            if dr <= 0.5 * len(lst) and dl >= 0.8 * len(lst):
                pastas_inv.add(pid)

    # 3) "07 Titulo - Artista": numero + espaco (sem traco) e o padrao de rips que gravam
    #    Titulo - Artista. Vale quando uma parte relevante da pasta usa esse padrao.
    tot_pasta = collections.Counter(f["paiId"] for f, _, _, _, _ in linhas)
    sem_traco = {f["id"] for f, _, _, _, m in linhas if not m and _sem_traco(f["name"])}
    n_st = collections.Counter(f["paiId"] for f, _, _, _, _ in linhas if f["id"] in sem_traco)
    pastas_st = {p for p, n in n_st.items() if n >= 4 and n >= 0.3 * tot_pasta[p]}

    reparos, n_inv, n_num = {}, 0, 0
    # Artistas "de confianca": lado esquerdo de arquivos no formato normal + os ja confirmados
    # na internet (artistas_ok). Pastas com "NN X - Y" sao MISTAS (parte X=artista, parte Y=artista),
    # entao a direcao e decidida arquivo por arquivo: so inverte quando o lado direito e um
    # artista conhecido e o esquerdo nao.
    conhecidos = {chave(a) for f, _, a, _, _ in linhas if f["id"] not in sem_traco} | set(artistas_ok or ())

    for f, t, a, b, manter in linhas:
        ka, kb = chave(a), chave(b)
        if f["id"] in sem_traco and f["paiId"] in pastas_st:
            if _SO_VERSAO.match(b):          # "Titulo - Live", "Titulo - Mono": nao ha artista no nome
                reparos[f["id"]] = (a, False)
                continue
            if kb in conhecidos and ka not in conhecidos:
                # "Titulo - Artista (ft. X)" -> "Artista feat. X - Titulo"
                m_ft = re.match(r"^(.*?)\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+(.*?)[\)\]]\s*$", b, re.I)
                b2 = f"{m_ft.group(1)} feat. {m_ft.group(2)}" if m_ft else b
                reparos[f["id"]] = (f"{b2} - {a}", False)
                n_inv += 1
                continue
            # sem evidencia (ou os dois lados conhecidos): deixa como esta e segue as outras regras
        inverter = f["paiId"] in pastas_inv or (esq[kb] >= 2 and esq[ka] == 1)
        if inverter:
            esq_txt, dir_txt = _SEP.split(t.strip(" -"), maxsplit=1)
            reparos[f["id"]] = (f"{dir_txt.strip()} - {esq_txt.strip()}", False)
            n_inv += 1
        elif manter:
            reparos[f["id"]] = (t, True)
            n_num += 1
    return reparos, {"invertidas": n_inv, "numero_no_nome": n_num,
                     "pastas_invertidas": [pastas[p]["name"] for p in pastas_inv if p in pastas]}


def ler_nome(arquivo: str, pasta: str | None = None, pasta_avo: str | None = None,
             conhecidos: set | None = None, manter_numero: bool = False) -> Leitura:
    r = Leitura(arquivo=arquivo)
    t = _limpar_basico(arquivo)
    t = _RUIDO.sub("", t)
    if not manter_numero:
        t = _NUM_FAIXA.sub("", t).strip()

    versoes = [m.group(1).strip().lower() for m in _VERSAO.finditer(t)]
    if versoes:
        r.versao = versoes[0]
    t_sem_versao = _VERSAO.sub("", t).strip(" -")
    t_sem_versao = re.sub(r"\s+", " ", t_sem_versao)

    partes = _SEP.split(t_sem_versao, maxsplit=1)
    artista = titulo = None
    if len(partes) == 2 and _artista_valido(partes[0]) and partes[1].strip():
        artista, titulo = partes[0].strip(), partes[1].strip()
        r.confianca, r.origem = "alta", "arquivo"
        if len(_SEP.split(t_sem_versao)) >= 3 and (conhecidos is None or chave(artista) not in conhecidos):
            r.confianca, r.origem = "media", "arquivo-3-partes"
    else:
        # Artista colado: "Marvin Gaye-Sexual Healing", "Public Enemy- WELCOME"
        m = re.fullmatch(r"(.+?)\s*-\s*(.+)|(.+?)\s+-\s*(.+)", t_sem_versao)
        if m and t_sem_versao.count("-") == 1:
            a, b = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(4))
            # "Whisky a Go-Go", "Meia-Noite": palavra composta, nao "Artista-Titulo"
            composta = re.search(r"\S-\S", t_sem_versao) and " " not in b.strip()
            if _artista_valido(a) and b.strip() and not composta:
                artista, titulo = a.strip(), b.strip()
                r.confianca, r.origem = "media", "arquivo-sem-espaco"
        if artista is None:
            a_pasta = _artista_da_pasta(pasta) or _artista_da_pasta(pasta_avo)
            titulo_so = t_sem_versao.strip()
            if a_pasta and titulo_so and conhecidos is not None and chave(a_pasta) in conhecidos:
                artista, titulo = a_pasta, titulo_so
                r.confianca, r.origem = "media", "pasta"
            elif titulo_so:
                r.artista_sugerido = a_pasta
                r.titulo = titulo_so
                r.confianca, r.origem = "baixa", "so-titulo"
                return r

    if artista:
        # separa convidados: "Artista feat. Outro"
        pa = _FEAT.split(artista, maxsplit=1)
        artista = pa[0].strip().replace(" / ", " & ")
        if len(pa) == 2:
            r.convidados = [c.strip() for c in re.split(r"\s*(?:,|&| e )\s*", pa[1]) if c.strip()]
        pt = _FEAT.split(titulo or "", maxsplit=1)
        if len(pt) == 2:
            titulo = pt[0].strip()
            r.convidados += [c.strip(" )]") for c in re.split(r"\s*(?:,|&| e )\s*", pt[1]) if c.strip(" )]")]
    # "Gustavo Mioto, Anitta" -> artista principal + convidado (exceto "Earth, Wind & Fire")
    if artista and "," in artista and not re.search(r",\s*wind\b", artista, re.I):
        partes_v = [x.strip() for x in artista.split(",") if x.strip()]
        if len(partes_v) >= 2 and _artista_valido(partes_v[0]):
            artista = partes_v[0]
            r.convidados = partes_v[1:] + r.convidados
    r.artista, r.titulo = artista, titulo
    r.chave_artista = chave(artista) if artista else None
    return r
