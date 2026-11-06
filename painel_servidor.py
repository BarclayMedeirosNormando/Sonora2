#!/usr/bin/env python3
"""Servidor local do painel de artistas: abre o painel no navegador e deixa o botao
'Salvar e publicar' gravar no correcoes.csv e rodar o atualizar_musicas.ps1 sozinho.

Uso:  py painel_servidor.py          (ou duplo clique em abrir_painel.bat)
So aceita conexoes deste computador (127.0.0.1). Ctrl+C para fechar.
"""
import argparse
import json
import re
import subprocess
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

RAIZ = Path(__file__).resolve().parent
PAINEL = RAIZ / "painel_artistas.html"
_SAIDA = RAIZ / "etapa1_nomes" / "saida"
# o painel usa a lista completa (com artistas sem foto) quando existe; senao cai no indice do app
BASE = _SAIDA / "painel" if (_SAIDA / "painel" / "indice.json").exists() else _SAIDA / "app"
INDICE = BASE / "indice.json"
CORRECOES = RAIZ / "etapa1_nomes" / "correcoes.csv"
PS1 = RAIZ / "atualizar_musicas.ps1"

LINHA_OK = re.compile(r"^(genero;[^;]+;[^;]+|unir;[^;]+;[^;]+|titulo;[\w-]+;[^;]+|foto;[^;]+;(-|https?://\S+))$")
trava = threading.Lock()
job = {"rodando": False, "linhas": [], "codigo": None}
COMANDO = None   # para testes: lista de argumentos que substitui o PowerShell


def comando():
    if COMANDO:
        return COMANDO
    return ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(PS1), "-SoCorrecoes"]


def validar(texto):
    """Devolve (linhas_validas, rejeitadas). Aceita so genero, unir (renomear), titulo (musica) e foto"""
    ok, ruins = [], []
    for ln in texto.replace("\r", "").split("\n"):
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        (ok if LINHA_OK.match(ln) else ruins).append(ln)
    return ok, ruins


def gravar(linhas):
    from datetime import datetime
    dados = CORRECOES.read_bytes() if CORRECOES.exists() else b""
    if dados and not dados.endswith(b"\n"):
        dados += b"\r\n"
    bloco = ["# --- painel_artistas (%s) ---" % datetime.now().strftime("%d/%m/%Y %H:%M")] + linhas
    CORRECOES.write_bytes(dados + ("\r\n".join(bloco) + "\r\n").encode("utf-8"))


def rodar():
    job.update(rodando=True, linhas=[], codigo=None)
    try:
        p = subprocess.Popen(comando(), cwd=str(RAIZ), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for bruta in p.stdout:
            for enc in ("utf-8", "cp850", "cp1252"):
                try:
                    t = bruta.decode(enc)
                    break
                except UnicodeDecodeError:
                    continue
            t = t.rstrip("\r\n")
            if t.strip():
                job["linhas"].append(t)
        job["codigo"] = p.wait()
    except Exception as e:  # noqa: BLE001
        job["linhas"].append("Erro ao iniciar: %s" % e)
        job["codigo"] = -1
    finally:
        job["rodando"] = False


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _host_ok(self):
        h = (self.headers.get("Host") or "").split(":")[0]
        return h in ("127.0.0.1", "localhost")

    def _json(self, obj, code=200):
        b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if not self._host_ok():
            return self._json({"ok": False}, 403)
        u = urlparse(self.path)
        if u.path in ("/", "/index.html"):
            b = PAINEL.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)
        elif u.path == "/api/indice":
            if not INDICE.exists():
                return self._json({"ok": False, "erro": "indice.json nao existe; rode .\\atualizar_musicas.ps1 antes"}, 404)
            b = INDICE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)
        elif u.path.startswith("/api/artista/"):
            aid = u.path[len("/api/artista/"):]
            arq = BASE / "artistas" / (aid + ".json")
            if not re.fullmatch(r"\w+", aid) or not arq.exists():
                return self._json({"ok": False}, 404)
            b = arq.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)
        elif u.path == "/api/status":
            desde = int((parse_qs(u.query).get("desde") or ["0"])[0] or 0)
            self._json({"ok": True, "rodando": job["rodando"], "codigo": job["codigo"],
                        "total": len(job["linhas"]), "linhas": job["linhas"][desde:]})
        else:
            self._json({"ok": False}, 404)

    def do_POST(self):
        if not self._host_ok() or self.headers.get("X-Sonora") != "1":
            return self._json({"ok": False, "erro": "pedido recusado"}, 403)
        if urlparse(self.path).path != "/api/publicar":
            return self._json({"ok": False}, 404)
        n = int(self.headers.get("Content-Length") or 0)
        if n > 2_000_000:
            return self._json({"ok": False, "erro": "pedido grande demais"}, 413)
        texto = self.rfile.read(n).decode("utf-8", "replace")
        with trava:
            if job["rodando"]:
                return self._json({"ok": False, "erro": "ja existe uma atualizacao em andamento"}, 409)
            linhas, ruins = validar(texto)
            if not linhas:
                return self._json({"ok": False, "erro": "nenhuma correcao valida", "rejeitadas": ruins}, 400)
            gravar(linhas)
            job.update(rodando=True, linhas=[], codigo=None)
            threading.Thread(target=rodar, daemon=True).start()
        self._json({"ok": True, "gravadas": len(linhas), "rejeitadas": ruins})


def main():
    global COMANDO
    ap = argparse.ArgumentParser()
    ap.add_argument("--porta", type=int, default=8765)
    ap.add_argument("--sem-navegador", action="store_true")
    ap.add_argument("--comando-teste", nargs="+", help=argparse.SUPPRESS)
    a = ap.parse_args()
    COMANDO = a.comando_teste
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", a.porta), H)
    except OSError:
        sys.exit("A porta %d ja esta em uso (o painel ja esta aberto?). Tente http://127.0.0.1:%d" % (a.porta, a.porta))
    url = "http://127.0.0.1:%d/" % a.porta
    print("Painel de artistas rodando em %s\nDeixe esta janela aberta enquanto usa o painel. Ctrl+C para fechar." % url)
    if not a.sem_navegador:
        webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nPainel fechado.")


if __name__ == "__main__":
    main()
