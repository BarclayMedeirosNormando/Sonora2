import 'package:flutter/material.dart';
import 'catalogo.dart';
import 'downloads.dart';
import 'player.dart';
import 'widgets.dart';

/// Pergunta e poe uma lista de faixas na fila de download.
Future<void> baixarLote(BuildContext context, List<Faixa> faixas,
    {String nome = 'estas músicas'}) async {
  final dl = DownloadService.i;
  final msg = ScaffoldMessenger.of(context);
  if (!dl.suportado) {
    msg.showSnackBar(const SnackBar(
        content: Text('Downloads funcionam só no app do celular.')));
    return;
  }
  final pendentes =
      faixas.where((f) => !dl.estaBaixada(f.id) && !dl.estaNaFila(f.id)).toList();
  if (pendentes.isEmpty) {
    msg.showSnackBar(
        const SnackBar(content: Text('Tudo isso já está baixado ou na fila.')));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Baixar para ouvir offline?'),
      content: Text('${pendentes.length} músicas de $nome '
          '(cerca de ${pendentes.length * 5} MB, estimativa). '
          'Use Wi-Fi se puder.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Baixar')),
      ],
    ),
  );
  if (ok != true) return;
  final n = dl.baixarVarias(pendentes);
  msg.showSnackBar(SnackBar(
      content: Text('Baixando $n músicas. Acompanhe em Biblioteca › Baixadas.')));
}

/// Botao "baixar tudo" para ficar ao lado de Tocar/Aleatorio.
class BotaoBaixarLote extends StatelessWidget {
  final List<Faixa> faixas;
  final String nome;
  const BotaoBaixarLote(this.faixas, {super.key, this.nome = 'estas músicas'});

  @override
  Widget build(BuildContext context) {
    if (!DownloadService.i.suportado) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: DownloadService.i,
      builder: (context, _) {
        final dl = DownloadService.i;
        final tudo = faixas.isNotEmpty && faixas.every((f) => dl.estaBaixada(f.id));
        return IconButton.outlined(
          tooltip: tudo ? 'Tudo baixado' : 'Baixar tudo para ouvir offline',
          style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              side: const BorderSide(color: Color(0xFF444444), width: 2)),
          icon: Icon(tudo ? Icons.download_done : Icons.download_for_offline_outlined,
              color: tudo ? verde : null),
          onPressed: faixas.isEmpty ? null : () => baixarLote(context, faixas, nome: nome),
        );
      },
    );
  }
}

/// Mini-icone de estado do download de uma faixa (baixada / baixando).
class IconeDownload extends StatelessWidget {
  final String faixaId;
  const IconeDownload(this.faixaId, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!DownloadService.i.suportado) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: DownloadService.i,
      builder: (context, _) {
        final dl = DownloadService.i;
        if (dl.estaBaixada(faixaId)) {
          return const Icon(Icons.download_done, size: 18, color: verde);
        }
        if (dl.estaNaFila(faixaId)) {
          return SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, value: dl.progresso(faixaId)));
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Aba "Baixadas" da biblioteca.
class ListaBaixadas extends StatelessWidget {
  const ListaBaixadas({super.key});

  @override
  Widget build(BuildContext context) {
    final dl = DownloadService.i;
    if (!dl.suportado) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
            'Downloads para ouvir offline funcionam só no app do celular.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cinzaTexto)),
      ));
    }
    return ListenableBuilder(
      listenable: dl,
      builder: (context, _) {
        final faixas = dl.faixasBaixadas;
        final andamento = dl.emAndamento;
        final falhas = dl.falhas;
        final p = PlayerService.instancia;
        return ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
                faixas.isEmpty
                    ? 'Nenhuma música baixada ainda.'
                    : '${faixas.length} músicas · ${formatarBytes(dl.totalBytes)} no aparelho',
                style: const TextStyle(color: cinzaTexto)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Modo offline'),
            subtitle: const Text('Ao tocar, usa só as músicas baixadas'),
            value: dl.modoOffline,
            activeColor: verde,
            onChanged: dl.definirModoOffline,
          ),
          if (andamento.isNotEmpty) ...[
            secao('Baixando (${andamento.length})'),
            for (final f in andamento)
              ListTile(
                dense: true,
                title: Text(f.tituloCompleto,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: dl.estaNaFila(f.id) && dl.progresso(f.id) != null
                      ? LinearProgressIndicator(
                          value: dl.progresso(f.id), color: verde)
                      : Text(f.artista,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                trailing: IconButton(
                    tooltip: 'Cancelar',
                    icon: const Icon(Icons.close),
                    onPressed: () => dl.cancelar(f.id)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: dl.cancelarTodos,
                  child: const Text('Cancelar todos')),
            ),
          ],
          if (falhas.isNotEmpty) ...[
            secao('Falharam (${falhas.length})'),
            for (final f in falhas)
              ListTile(
                dense: true,
                title: Text(f.tituloCompleto,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(dl.motivoFalha[f.id] ?? 'erro',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            Row(children: [
              TextButton(
                  onPressed: dl.tentarNovamente,
                  child: const Text('Tentar de novo')),
              TextButton(
                  onPressed: dl.limparFalhas, child: const Text('Limpar')),
            ]),
          ],
          if (faixas.isNotEmpty) ...[
            BotoesTocar(
              aoTocar: () => p.tocarLista(faixas, 0),
              aoAleatorio: () => p.tocarLista(faixas, 0, aleatorio: true),
            ),
            secao('Músicas baixadas'),
            for (var i = 0; i < faixas.length; i++)
              LinhaFaixa(faixa: faixas[i], onTap: () => p.tocarLista(faixas, i)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover todas as baixadas'),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remover todas?'),
                      content: Text(
                          'Apaga ${faixas.length} músicas do aparelho (${formatarBytes(dl.totalBytes)}).'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Remover')),
                      ],
                    ),
                  );
                  if (ok == true) await dl.removerTodas();
                },
              ),
            ),
          ],
        ]);
      },
    );
  }
}
