/**
 * Sonora 2.0 - Controle de acesso + painel (Google Apps Script, 100% gratis).
 *
 * Este script fica DENTRO de uma Planilha Google (Extensoes > Apps Script) e guarda tudo nela:
 *   aba "Aparelhos": quem usa o app e se esta Liberado / Bloqueado / Aguardando
 *   aba "Plays":     o que cada aparelho ouviu (musica, artista, genero, hora)
 *   aba "Config":    a chave do painel
 *
 * Passo a passo: veja LEIA-ME.md nesta pasta.
 */

const FUSO = 'America/Sao_Paulo';
const OFFSET_MS = -3 * 3600 * 1000;       // Brasilia (sem horario de verao desde 2019)
const ABA_APARELHOS = 'Aparelhos';
const ABA_PLAYS = 'Plays';
const ABA_CONFIG = 'Config';
const STATUS_LIBERADO = 'Liberado';
const STATUS_BLOQUEADO = 'Bloqueado';
const STATUS_AGUARDANDO = 'Aguardando';
const STATUS_VALIDOS = [STATUS_LIBERADO, STATUS_BLOQUEADO, STATUS_AGUARDANDO];
const CAB_APARELHOS = ['App_ID', 'Status', 'Nome', 'Plataforma', 'Versao', 'Primeiro_Acesso',
  'Ultimo_Acesso', 'Total_Plays', 'Ultimo_Play', 'Ultima_Musica'];
const CAB_PLAYS = ['Quando', 'App_ID', 'Faixa_ID', 'Titulo', 'Artista', 'Genero'];
const MAX_EVENTOS = 100;
const ONLINE_MIN = 10;                    // "ouvindo agora" = play nos ultimos 10 min

// ============================================================ configuracao inicial

/** Rode UMA vez no editor (botao Executar). Cria as abas e gera a chave do painel. */
function configurar() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  abaOuCria_(ss, ABA_APARELHOS, CAB_APARELHOS);
  abaOuCria_(ss, ABA_PLAYS, CAB_PLAYS);
  const cfg = abaOuCria_(ss, ABA_CONFIG, ['Item', 'Valor']);
  const props = PropertiesService.getScriptProperties();
  let chave = props.getProperty('PAINEL_CHAVE');
  if (!chave) {
    chave = Utilities.getUuid().replace(/-/g, '').slice(0, 20);
    props.setProperty('PAINEL_CHAVE', chave);
  }
  cfg.getRange(2, 1, 1, 2).setValues([['Chave do painel', chave]]);
  Logger.log('Pronto. Chave do painel: ' + chave);
  return chave;
}

function abaOuCria_(ss, nome, cabecalho) {
  let sh = ss.getSheetByName(nome);
  if (!sh) sh = ss.insertSheet(nome);
  if (sh.getLastRow() === 0) {
    sh.getRange(1, 1, 1, cabecalho.length).setValues([cabecalho]);
    sh.setFrozenRows(1);
    sh.getRange(1, 1, 1, cabecalho.length).setFontWeight('bold');
  }
  return sh;
}

function aba_(nome) {
  const sh = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(nome);
  if (!sh) throw new Error('Aba "' + nome + '" nao existe. Rode configurar() uma vez.');
  return sh;
}

function chavePainel_() {
  return PropertiesService.getScriptProperties().getProperty('PAINEL_CHAVE') || '';
}

function verificarChave_(chave) {
  const certa = chavePainel_();
  if (!certa || String(chave || '') !== certa) throw new Error('Acesso negado');
}

// ============================================================ entradas web

function doGet(e) {
  const p = (e && e.parameter) || {};
  try {
    if (p.page === 'painel') {
      const certa = chavePainel_();
      if (!certa || p.chave !== certa) {
        return HtmlService.createHtmlOutput('<h3 style="font-family:sans-serif">Acesso negado</h3>');
      }
      const t = HtmlService.createTemplateFromFile('Painel');
      t.chave = p.chave;
      return t.evaluate()
        .setTitle('Sonora 2.0 - Painel')
        .addMetaTag('viewport', 'width=device-width, initial-scale=1')
        .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
    }
    if (p.action === 'validar') return json_(validar_(p));
    if (p.action === 'versao') return json_(versao_(p));
    return json_({ ok: true, servico: 'Sonora 2.0' });
  } catch (err) {
    return json_({ ok: false, erro: String(err && err.message || err) });
  }
}

function doPost(e) {
  try {
    const corpo = JSON.parse(e.postData.contents);
    if (corpo.action === 'plays') return json_(receberPlays_(corpo));
    return json_({ ok: false, erro: 'acao desconhecida' });
  } catch (err) {
    return json_({ ok: false, erro: String(err && err.message || err) });
  }
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

// ============================================================ utilidades

function idValido_(id) {
  id = String(id || '');
  return /^[A-Za-z0-9-]{8,64}$/.test(id) ? id : null;
}

/** Texto seguro para a planilha: sem quebras e sem virar formula. */
function limpar_(s, max) {
  s = String(s == null ? '' : s).replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max || 120);
  if (/^[=+\-@]/.test(s)) s = "'" + s;
  return s;
}

/** id -> [linha, status], guardado 2 min em cache para nao ler a planilha a cada chamada. */
function lerMapa_() {
  const cache = CacheService.getScriptCache();
  const c = cache.get('mapa');
  if (c) {
    try { return JSON.parse(c); } catch (e) { /* refaz */ }
  }
  const sh = aba_(ABA_APARELHOS);
  const n = sh.getLastRow() - 1;
  const mapa = {};
  if (n > 0) {
    const v = sh.getRange(2, 1, n, 2).getValues();
    for (let i = 0; i < v.length; i++) mapa[String(v[i][0])] = [i + 2, String(v[i][1])];
  }
  try { cache.put('mapa', JSON.stringify(mapa), 120); } catch (e) { /* mapa grande demais: segue sem cache */ }
  return mapa;
}

function limparMapa_() {
  CacheService.getScriptCache().remove('mapa');
}

/** Linha do aparelho, conferindo que a planilha nao mudou por baixo do cache. */
function linhaDe_(id) {
  for (let tentativa = 0; tentativa < 2; tentativa++) {
    const reg = lerMapa_()[id];
    if (reg && String(aba_(ABA_APARELHOS).getRange(reg[0], 1).getValue()) === id) return reg[0];
    limparMapa_();
  }
  return 0;
}

// ============================================================ liberacao de aparelhos

function validar_(p) {
  const id = idValido_(p.id);
  if (!id) return { ok: false, erro: 'id invalido' };
  const agora = new Date();
  const cache = CacheService.getScriptCache();
  let reg = lerMapa_()[id];

  if (!reg) {
    const lock = LockService.getScriptLock();
    lock.waitLock(15000);
    try {
      limparMapa_();
      reg = lerMapa_()[id];
      if (!reg) {
        aba_(ABA_APARELHOS).appendRow([id, STATUS_AGUARDANDO, limpar_(p.nome, 60), limpar_(p.plataforma, 20),
          limpar_(p.versao, 20), agora, agora, 0, '', '']);
        limparMapa_();
        return { ok: true, status: STATUS_AGUARDANDO };
      }
    } finally {
      lock.releaseLock();
    }
  }

  // aparelho ja conhecido: atualiza ultimo acesso (no maximo a cada 10 min) e nome, se veio um novo
  const sh = aba_(ABA_APARELHOS);
  const linha = linhaDe_(id);
  if (linha) {
    if (p.nome && !String(sh.getRange(linha, 3).getValue())) sh.getRange(linha, 3).setValue(limpar_(p.nome, 60));
    if (!cache.get('ua_' + id)) {
      sh.getRange(linha, 7).setValue(agora);
      if (p.versao) sh.getRange(linha, 5).setValue(limpar_(p.versao, 20));
      cache.put('ua_' + id, '1', 600);
    }
  }
  return { ok: true, status: reg[1] };
}

// ============================================================ atualizacao do app

/** Numero depois do "+" em "0.6.0+6" (e o que decide se um aparelho esta desatualizado). */
function build_(v) {
  const m = /\+(\d+)/.exec(String(v || ''));
  return m ? Number(m[1]) : 0;
}

function infoAtualizacao_() {
  const pr = PropertiesService.getScriptProperties();
  return { versao: pr.getProperty('ATUAL_VERSAO') || '', apkId: pr.getProperty('ATUAL_APK_ID') || '',
    notas: pr.getProperty('ATUAL_NOTAS') || '' };
}

/** O app pergunta se existe versao nova. So aparelhos Liberados recebem o link do APK. */
function versao_(p) {
  const id = idValido_(p.id);
  if (!id) return { ok: false, erro: 'id invalido' };
  const reg = lerMapa_()[id];
  const info = infoAtualizacao_();
  const r = { ok: true, status: reg ? reg[1] : STATUS_AGUARDANDO, versao: info.versao, build: build_(info.versao) };
  if (r.status === STATUS_LIBERADO && info.apkId) {
    r.url = 'https://drive.usercontent.google.com/download?id=' + info.apkId + '&export=download&confirm=t';
    r.notas = info.notas;
  }
  return r;
}

function lerAtualizacao(chave) {
  verificarChave_(chave);
  const info = infoAtualizacao_();
  return { versao: info.versao, link: info.apkId ? 'https://drive.google.com/file/d/' + info.apkId + '/view' : '', notas: info.notas };
}

/** versao no formato 0.6.0+6; link = link de compartilhamento do APK no Drive (ou so o ID). */
function publicarAtualizacao(chave, versao, link, notas) {
  verificarChave_(chave);
  versao = String(versao || '').trim();
  if (!/^\d+\.\d+\.\d+\+\d+$/.test(versao)) throw new Error('Versao deve ser como 0.6.0+6');
  const m = /[-\w]{25,}/.exec(String(link || ''));
  if (!m) throw new Error('Link do APK invalido');
  const pr = PropertiesService.getScriptProperties();
  pr.setProperty('ATUAL_VERSAO', versao);
  pr.setProperty('ATUAL_APK_ID', m[0]);
  pr.setProperty('ATUAL_NOTAS', limpar_(notas, 300));
  return { ok: true };
}

function removerAtualizacao(chave) {
  verificarChave_(chave);
  const pr = PropertiesService.getScriptProperties();
  ['ATUAL_VERSAO', 'ATUAL_APK_ID', 'ATUAL_NOTAS'].forEach(function (k) { pr.deleteProperty(k); });
  return { ok: true };
}

// ============================================================ recebimento de plays

function receberPlays_(corpo) {
  const id = idValido_(corpo.id);
  if (!id) return { ok: false, erro: 'id invalido' };
  const reg = lerMapa_()[id];
  if (!reg) return { ok: false, status: 'Desconhecido' };
  if (reg[1] !== STATUS_LIBERADO) return { ok: false, status: reg[1] };

  const cache = CacheService.getScriptCache();
  const lote = limpar_(corpo.lote, 80);
  if (lote && cache.get('lote_' + id + lote)) return { ok: true, status: STATUS_LIBERADO, repetido: true };

  const eventos = Array.isArray(corpo.eventos) ? corpo.eventos.slice(0, MAX_EVENTOS) : [];
  const agora = Date.now();
  const linhas = [];
  for (let i = 0; i < eventos.length; i++) {
    const e = eventos[i] || {};
    let t = Number(e.t);
    if (!isFinite(t) || t > agora + 300000 || t < agora - 7 * 86400000) t = agora;
    const titulo = limpar_(e.ti, 120);
    if (!titulo) continue;
    linhas.push([new Date(t), id, limpar_(e.f, 64), titulo, limpar_(e.ar, 80), limpar_(e.g, 40) || 'Outros']);
  }
  if (!linhas.length) return { ok: true, status: STATUS_LIBERADO, recebidos: 0 };

  const lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try {
    const plays = aba_(ABA_PLAYS);
    plays.getRange(plays.getLastRow() + 1, 1, linhas.length, CAB_PLAYS.length).setValues(linhas);
    const linha = linhaDe_(id);
    if (linha) {
      const ap = aba_(ABA_APARELHOS);
      const total = Number(ap.getRange(linha, 8).getValue()) || 0;
      const ult = linhas[linhas.length - 1];
      ap.getRange(linha, 7).setValue(new Date());
      ap.getRange(linha, 8, 1, 3).setValues([[total + linhas.length, ult[0], ult[3] + ' - ' + ult[4]]]);
    }
    if (lote) cache.put('lote_' + id + lote, '1', 21600);
  } finally {
    lock.releaseLock();
  }
  return { ok: true, status: STATUS_LIBERADO, recebidos: linhas.length };
}

// ============================================================ painel: aparelhos

function listarAparelhos(chave) {
  verificarChave_(chave);
  const sh = aba_(ABA_APARELHOS);
  const n = sh.getLastRow() - 1;
  if (n < 1) return [];
  const v = sh.getRange(2, 1, n, CAB_APARELHOS.length).getValues();
  const ms = function (d) { return d instanceof Date ? d.getTime() : 0; };
  const lista = v.map(function (r) {
    return { id: String(r[0]), status: String(r[1]), nome: String(r[2] || ''), plataforma: String(r[3] || ''),
      versao: String(r[4] || ''), primeiro: ms(r[5]), ultimo: ms(r[6]), total: Number(r[7]) || 0,
      ultPlay: ms(r[8]), ultMusica: String(r[9] || ''), desatualizado: false };
  });
  const buildAtual = build_(infoAtualizacao_().versao);
  if (buildAtual) lista.forEach(function (a) { a.desatualizado = build_(a.versao) < buildAtual; });
  const ordem = {};
  ordem[STATUS_AGUARDANDO] = 0; ordem[STATUS_LIBERADO] = 1; ordem[STATUS_BLOQUEADO] = 2;
  lista.sort(function (a, b) {
    return (ordem[a.status] - ordem[b.status]) || (b.ultimo - a.ultimo);
  });
  return lista;
}

function definirStatus(chave, id, status) {
  verificarChave_(chave);
  id = idValido_(id);
  if (!id || STATUS_VALIDOS.indexOf(status) < 0) throw new Error('dados invalidos');
  const lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try {
    const linha = linhaDe_(id);
    if (!linha) throw new Error('aparelho nao encontrado');
    aba_(ABA_APARELHOS).getRange(linha, 2).setValue(status);
    limparMapa_();
  } finally {
    lock.releaseLock();
  }
  return { ok: true };
}

function definirNome(chave, id, nome) {
  verificarChave_(chave);
  id = idValido_(id);
  if (!id) throw new Error('dados invalidos');
  const linha = linhaDe_(id);
  if (!linha) throw new Error('aparelho nao encontrado');
  aba_(ABA_APARELHOS).getRange(linha, 3).setValue(limpar_(nome, 60));
  return { ok: true };
}

// ============================================================ painel: dados e graficos

function lerPlays_() {
  const sh = aba_(ABA_PLAYS);
  const n = sh.getLastRow() - 1;
  return n < 1 ? [] : sh.getRange(2, 1, n, CAB_PLAYS.length).getValues();
}

function diaLocal_(ms) {
  return new Date(ms + OFFSET_MS).toISOString().slice(0, 10);
}

function inicioDoDia_(ms) {
  return Date.parse(diaLocal_(ms) + 'T00:00:00-03:00');
}

function topo_(mapa, n) {
  return Object.keys(mapa).map(function (k) { return mapa[k]; })
    .sort(function (a, b) { return b.plays - a.plays; }).slice(0, n)
    .map(function (x) { return { nome: x.nome, extra: x.extra, genero: x.genero, plays: x.plays, ouvintes: Object.keys(x.ids).length }; });
}

function somar_(mapa, chave, nome, extra, genero, id) {
  let x = mapa[chave];
  if (!x) { x = mapa[chave] = { nome: nome, extra: extra, genero: genero, plays: 0, ids: {} }; }
  x.plays++;
  x.ids[id] = 1;
}

/** Rankings de um conjunto de plays (linhas da aba Plays). */
function rankings_(plays, minT, soId) {
  const musicas = {}, artistas = {}, generos = {};
  const hora = []; for (let h = 0; h < 24; h++) hora.push(0);
  for (let i = 0; i < plays.length; i++) {
    const r = plays[i];
    const t = r[0] instanceof Date ? r[0].getTime() : 0;
    if (t < minT) continue;
    const id = String(r[1]);
    if (soId && id !== soId) continue;
    const titulo = String(r[3]), artista = String(r[4]), genero = String(r[5] || 'Outros');
    somar_(musicas, titulo + '|' + artista, titulo, artista, genero, id);
    somar_(artistas, artista || '(sem artista)', artista || '(sem artista)', genero, genero, id);
    somar_(generos, genero, genero, '', genero, id);
    hora[new Date(t + OFFSET_MS).getUTCHours()]++;
  }
  return { musicas: topo_(musicas, 15), artistas: topo_(artistas, 15), generos: topo_(generos, 30), porHora: hora };
}

/** Tudo que a tela "Visao geral / Rankings" precisa. dias = 0 significa "desde o inicio". */
function dadosPainel(chave, dias) {
  verificarChave_(chave);
  dias = Number(dias) || 0;
  const cache = CacheService.getScriptCache();
  const ck = 'painel_' + dias;
  const guardado = cache.get(ck);
  if (guardado) { try { return JSON.parse(guardado); } catch (e) { /* refaz */ } }

  const agora = Date.now();
  const hoje0 = inicioDoDia_(agora);
  const aparelhos = listarAparelhos(chave);
  const plays = lerPlays_();
  const nomePor = {};
  aparelhos.forEach(function (a) { nomePor[a.id] = a.nome || ('Aparelho ' + a.id.slice(0, 6)); });

  const kpi = { liberados: 0, aguardando: 0, bloqueados: 0, online: 0, ativosHoje: 0, ativos7d: 0,
    playsHoje: 0, plays7d: 0, plays30d: 0, playsTotal: plays.length, ouvintesHoje: 0 };
  const ouvindoAgora = [];
  aparelhos.forEach(function (a) {
    if (a.status === STATUS_LIBERADO) kpi.liberados++;
    else if (a.status === STATUS_BLOQUEADO) kpi.bloqueados++;
    else kpi.aguardando++;
    if (a.ultimo >= hoje0) kpi.ativosHoje++;
    if (a.ultimo >= agora - 7 * 86400000) kpi.ativos7d++;
    if (a.ultPlay && a.ultPlay >= agora - ONLINE_MIN * 60000) {
      kpi.online++;
      ouvindoAgora.push({ id: a.id, nome: nomePor[a.id], musica: a.ultMusica, quando: a.ultPlay });
    }
  });

  // plays por dia nos ultimos 30 dias
  const porDiaMapa = {};
  const hojeIds = {};
  for (let i = 0; i < plays.length; i++) {
    const t = plays[i][0] instanceof Date ? plays[i][0].getTime() : 0;
    if (!t) continue;
    if (t >= hoje0) { kpi.playsHoje++; hojeIds[String(plays[i][1])] = 1; }
    if (t >= agora - 7 * 86400000) kpi.plays7d++;
    if (t >= agora - 30 * 86400000) {
      kpi.plays30d++;
      const d = diaLocal_(t);
      const x = porDiaMapa[d] || (porDiaMapa[d] = { plays: 0, ids: {} });
      x.plays++; x.ids[String(plays[i][1])] = 1;
    }
  }
  kpi.ouvintesHoje = Object.keys(hojeIds).length;
  const porDia = [];
  for (let k = 29; k >= 0; k--) {
    const d = diaLocal_(agora - k * 86400000);
    const x = porDiaMapa[d];
    porDia.push({ dia: d, plays: x ? x.plays : 0, ouvintes: x ? Object.keys(x.ids).length : 0 });
  }

  const minT = dias > 0 ? agora - dias * 86400000 : 0;
  const rk = rankings_(plays, minT, null);

  const recentes = plays.slice(-300).map(function (r) {
    return { t: r[0] instanceof Date ? r[0].getTime() : 0, quem: nomePor[String(r[1])] || String(r[1]).slice(0, 6),
      titulo: String(r[3]), artista: String(r[4]), genero: String(r[5]) };
  }).sort(function (a, b) { return b.t - a.t; }).slice(0, 40);

  const res = { gerado: agora, kpi: kpi, porDia: porDia, porHora: rk.porHora, topMusicas: rk.musicas,
    topArtistas: rk.artistas, topGeneros: rk.generos, ouvindoAgora: ouvindoAgora, recentes: recentes };
  try { cache.put(ck, JSON.stringify(res), 60); } catch (e) { /* grande demais: sem cache */ }
  return res;
}

/** O que um aparelho especifico ouviu. */
function detalheAparelho(chave, id, dias) {
  verificarChave_(chave);
  id = idValido_(id);
  if (!id) throw new Error('dados invalidos');
  dias = Number(dias) || 0;
  const plays = lerPlays_();
  const minT = dias > 0 ? Date.now() - dias * 86400000 : 0;
  const rk = rankings_(plays, minT, id);
  const ultimos = [];
  for (let i = plays.length - 1; i >= 0 && ultimos.length < 30; i--) {
    if (String(plays[i][1]) !== id) continue;
    ultimos.push({ t: plays[i][0] instanceof Date ? plays[i][0].getTime() : 0, titulo: String(plays[i][3]),
      artista: String(plays[i][4]), genero: String(plays[i][5]) });
  }
  return { topMusicas: rk.musicas.slice(0, 10), topArtistas: rk.artistas.slice(0, 10),
    topGeneros: rk.generos.slice(0, 10), ultimos: ultimos };
}

// ============================================================ manutencao

/**
 * Apaga da aba Plays o que for mais antigo que [dias] (padrao 180), para a planilha nao encher
 * (limite de 10 milhoes de celulas). Pode ser rodado a mao ou por gatilho mensal.
 */
function limparPlaysAntigos(dias) {
  dias = Number(dias) || 180;
  const sh = aba_(ABA_PLAYS);
  const n = sh.getLastRow() - 1;
  if (n < 1) return 0;
  const corte = Date.now() - dias * 86400000;
  const col = sh.getRange(2, 1, n, 1).getValues();
  let k = 0;
  while (k < col.length && col[k][0] instanceof Date && col[k][0].getTime() < corte) k++;
  if (k > 0) sh.deleteRows(2, k);
  return k;
}
