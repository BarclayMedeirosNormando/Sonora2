"""Gera o script do Apps Script que manda faixas para a LIXEIRA do Drive (recuperavel por 30 dias).

Uso (na pasta etapa1_nomes, depois de atualizar_musicas.ps1):

    py gerar_script_limpeza.py                          # so as duplicadas
    py gerar_script_limpeza.py --sem-foto aprovados.txt # duplicadas + faixas dos artistas listados

aprovados.txt: um nome de artista por linha, copiado de saida\\limpeza\\sem_foto_artistas.csv.
So entram artistas que voce escreveu nesse arquivo.

Saida: saida\\limpeza\\Limpeza.gs  (cole no projeto "Sonora" em script.google.com).
Nada e apagado aqui; o Drive so e alterado quando voce executa `lixeira` la.
"""
import argparse
import json
import sqlite3
import sys
from pathlib import Path

from nomes import chave

ap = argparse.ArgumentParser()
ap.add_argument("--saida", default="saida")
ap.add_argument("--sem-foto", help="txt com artistas aprovados para remover (um por linha)")
a = ap.parse_args()
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

saida = Path(a.saida)
db_path = saida / "catalogo.db"
if not db_path.exists():
    sys.exit(f"Nao achei {db_path}. Rode antes: .\\atualizar_musicas.ps1")
db = sqlite3.connect(db_path)

dups = [r[0] for r in db.execute("SELECT id FROM faixas WHERE principal = 0 AND dup_grupo IS NOT NULL")]
ids = list(dups)

n_sem_foto = 0
if a.sem_foto:
    nomes = {chave(l.strip()) for l in Path(a.sem_foto).read_text(encoding="utf-8-sig").splitlines()
             if l.strip() and not l.lstrip().startswith("#")}
    # seguranca: so artistas que realmente estao sem foto no catalogo
    for (k,) in db.execute("SELECT chave FROM artistas WHERE foto IS NULL OR foto = ''"):
        if k in nomes:
            for (fid,) in db.execute("SELECT id FROM faixas WHERE artista_chave = ?", (k,)):
                if fid not in ids:
                    ids.append(fid)
                    n_sem_foto += 1

codigo = """/** Limpeza do Sonora: manda faixas para a LIXEIRA do Drive (recupera ate 30 dias).
 *  1) Execute `conferir` (so conta, nao muda nada).  2) Execute `lixeira` (repita ate dizer FIM).
 *  Para desfazer: execute `restaurar`. */
const IDS = %s;

function conferir() {
  let ok = 0, ja = 0, erro = 0;
  IDS.forEach(id => {
    try { const f = DriveApp.getFileById(id); f.isTrashed() ? ja++ : ok++; } catch (e) { erro++; }
  });
  Logger.log('Total ' + IDS.length + ' | na biblioteca: ' + ok + ' | ja na lixeira: ' + ja + ' | nao acessiveis: ' + erro);
}

function lixeira() {
  const p = PropertiesService.getScriptProperties();
  let i = Number(p.getProperty('LIMPEZA_POS') || 0), feitos = 0, erros = 0;
  const ini = Date.now();
  for (; i < IDS.length && Date.now() - ini < 270000; i++) {
    try { const f = DriveApp.getFileById(IDS[i]); if (!f.isTrashed()) { f.setTrashed(true); feitos++; } }
    catch (e) { erros++; Logger.log('erro ' + IDS[i] + ': ' + e); }
  }
  p.setProperty('LIMPEZA_POS', String(i));
  Logger.log((i >= IDS.length ? 'FIM' : 'Execute `lixeira` de novo') + ' | posicao ' + i + '/' + IDS.length +
             ' | para a lixeira agora: ' + feitos + ' | erros: ' + erros);
}

function restaurar() {
  let n = 0;
  IDS.forEach(id => { try { const f = DriveApp.getFileById(id); if (f.isTrashed()) { f.setTrashed(false); n++; } } catch (e) {} });
  PropertiesService.getScriptProperties().deleteProperty('LIMPEZA_POS');
  Logger.log('Restauradas: ' + n);
}
""" % json.dumps(ids)

pasta = saida / "limpeza"
pasta.mkdir(exist_ok=True)
(pasta / "Limpeza.gs").write_text(codigo, encoding="utf-8")
print(f"Duplicadas: {len(dups)} | sem foto aprovadas: {n_sem_foto} | total no script: {len(ids)}")
print(f"Gerado: {(pasta / 'Limpeza.gs').resolve()}")
