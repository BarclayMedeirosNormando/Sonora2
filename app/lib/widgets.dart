import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'biblioteca_usuario.dart';
import 'catalogo.dart';
import 'downloads.dart';
import 'downloads_tela.dart';
import 'player.dart';
import 'player_tela.dart';
import 'playlists.dart';

const verde = Color(0xFF1DB954);
const cinzaTexto = Color(0xFFB3B3B3);

/// Cor estavel gerada a partir de um texto (usada quando nao ha foto).
Color corDe(String s) {
  final h = s.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xFFFFFF);
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.45, 0.32).toColor();
}

String inicial(String s) =>
    s.isEmpty ? '♪' : String.fromCharCode(s.runes.first).toUpperCase();

/// Foto do artista (se existir) ou um quadrado/circulo colorido com a inicial.
Widget capa(String texto,
    {double tamanho = 48, bool quadrada = false, String? foto}) {
  final raio = quadrada ? tamanho * 0.12 : tamanho / 2;
  final reserva = Container(
    width: tamanho,
    height: tamanho,
    alignment: Alignment.center,
    color: corDe(texto),
    child: Text(inicial(texto),
        style: TextStyle(
            color: Colors.white,
            fontSize: tamanho * 0.38,
            fontWeight: FontWeight.w600)),
  );
  final Widget conteudo = foto == null
      ? reserva
      : foto.startsWith('http')
          ? CachedNetworkImage(
              imageUrl: foto,
              width: tamanho,
              height: tamanho,
              fit: BoxFit.cover,
              memCacheWidth: tamanho.isFinite ? (tamanho * 2).round() : null,
              placeholder: (_, __) => reserva,
              errorWidget: (_, __, ___) => reserva)
          : Image.asset('assets/catalogo/fotos/$foto',
              width: tamanho,
              height: tamanho,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => reserva);
  return ClipRRect(borderRadius: BorderRadius.circular(raio), child: conteudo);
}

Widget secao(String titulo) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(titulo,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    );

/// Estrutura comum das telas internas: conteudo + mini-player fixo embaixo.
class Moldura extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget corpo;
  const Moldura({super.key, this.appBar, required this.corpo});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: appBar,
        body: corpo,
        bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      );
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) {
    final p = PlayerService.instancia;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final f = p.atual;
        if (f == null) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF242424),
          child: InkWell(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    fullscreenDialog: true, builder: (_) => const PlayerTela())),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              StreamBuilder<Duration>(
                stream: p.posicao,
                builder: (_, ps) => StreamBuilder<Duration?>(
                  stream: p.duracao,
                  builder: (_, ds) {
                    final total = (ds.data?.inMilliseconds ?? 0).toDouble();
                    final pos = (ps.data?.inMilliseconds ?? 0).toDouble();
                    return LinearProgressIndicator(
                        value: total > 0 ? (pos / total).clamp(0.0, 1.0) : null,
                        minHeight: 2,
                        color: verde,
                        backgroundColor: const Color(0xFF444444));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                child: Row(children: [
                  capa(f.artista, tamanho: 40, foto: f.foto),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.tituloCompleto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                          Text(p.erro ?? f.artista,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: p.erro != null
                                      ? Colors.redAccent
                                      : cinzaTexto)),
                        ]),
                  ),
                  IconButton(
                      tooltip: 'Anterior',
                      icon: const Icon(Icons.skip_previous),
                      onPressed: p.anterior),
                  IconButton(
                      tooltip: p.tocando ? 'Pausar' : 'Tocar',
                      iconSize: 30,
                      icon: Icon(p.tocando ? Icons.pause : Icons.play_arrow),
                      onPressed: p.alternar),
                  IconButton(
                      tooltip: 'Proxima',
                      icon: const Icon(Icons.skip_next),
                      onPressed: p.proxima),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Menu "..." de uma musica: favoritar, adicionar a playlist, remover da playlist.
void menuFaixa(BuildContext context, Faixa f, {Playlist? daPlaylist}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([MinhaBiblioteca.i, DownloadService.i]),
        builder: (_, __) {
          final fav = MinhaBiblioteca.i.ehFavorito(f.id);
          final dl = DownloadService.i;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: capa(f.artista, tamanho: 44, quadrada: true, foto: f.foto),
              title: Text(f.tituloCompleto,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(f.artista),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(fav ? Icons.favorite : Icons.favorite_border,
                  color: fav ? verde : null),
              title: Text(fav ? 'Remover dos favoritos' : 'Favoritar'),
              onTap: () => MinhaBiblioteca.i.alternarFavorito(f),
            ),
            if (dl.suportado)
              if (dl.estaBaixada(f.id))
                ListTile(
                  leading: const Icon(Icons.download_done, color: verde),
                  title: const Text('Baixada · remover do aparelho'),
                  onTap: () {
                    dl.remover(f.id);
                    Navigator.pop(ctx);
                  },
                )
              else if (dl.estaNaFila(f.id))
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancelar download'),
                  onTap: () {
                    dl.cancelar(f.id);
                    Navigator.pop(ctx);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('Baixar para ouvir offline'),
                  onTap: () {
                    dl.baixar(f);
                    Navigator.pop(ctx);
                  },
                ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Adicionar à playlist'),
              onTap: () {
                Navigator.pop(ctx);
                adicionarAPlaylist(context, f);
              },
            ),
            if (daPlaylist != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Remover desta playlist'),
                onTap: () {
                  MinhaBiblioteca.i.removerDaPlaylist(daPlaylist, f);
                  Navigator.pop(ctx);
                },
              ),
          ]);
        },
      ),
    ),
  );
}

/// Linha de musica reutilizada em artista, favoritas e playlists.
class LinhaFaixa extends StatelessWidget {
  final Faixa faixa;
  final VoidCallback onTap;
  final Playlist? daPlaylist;
  const LinhaFaixa(
      {super.key, required this.faixa, required this.onTap, this.daPlaylist});

  @override
  Widget build(BuildContext context) {
    final p = PlayerService.instancia;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final tocandoEsta = p.atual?.id == faixa.id;
        return ListTile(
          leading:
              capa(faixa.artista, tamanho: 44, quadrada: true, foto: faixa.foto),
          title: Text(faixa.tituloCompleto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tocandoEsta ? verde : null)),
          subtitle: Text(faixa.artista,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconeDownload(faixa.id),
            IconButton(
                tooltip: 'Mais opções',
                icon: const Icon(Icons.more_horiz, color: cinzaTexto),
                onPressed: () =>
                    menuFaixa(context, faixa, daPlaylist: daPlaylist)),
          ]),
          onTap: onTap,
        );
      },
    );
  }
}

/// Botoes "Tocar" e "Aleatorio".
class BotoesTocar extends StatelessWidget {
  final VoidCallback aoTocar;
  final VoidCallback aoAleatorio;
  final Widget? extra;
  const BotoesTocar(
      {super.key, required this.aoTocar, required this.aoAleatorio, this.extra});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: verde,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(44)),
              onPressed: aoTocar,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Tocar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: Color(0xFF444444), width: 2)),
              onPressed: aoAleatorio,
              icon: const Icon(Icons.shuffle),
              label: const Text('Aleatório'),
            ),
          ),
          if (extra != null) ...[const SizedBox(width: 12), extra!],
        ]),
      );
}
