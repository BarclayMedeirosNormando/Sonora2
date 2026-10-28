import 'package:flutter/material.dart';
import 'biblioteca_usuario.dart';
import 'downloads_tela.dart';
import 'catalogo.dart';
import 'player.dart';
import 'widgets.dart';

Future<String?> pedirNome(BuildContext context,
    {String titulo = 'Nova playlist', String inicial = ''}) {
  final c = TextEditingController(text: inicial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome da playlist'),
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Salvar')),
      ],
    ),
  );
}

/// Janela de baixo: marcar em quais playlists a musica entra.
void adicionarAPlaylist(BuildContext context, Faixa f) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: MinhaBiblioteca.i,
        builder: (_, __) {
          final lista = MinhaBiblioteca.i.playlists;
          return ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${f.tituloCompleto} · ${f.artista}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: cinzaTexto)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Adicionar à playlist',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add, color: verde),
                ),
                title: const Text('Nova playlist',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  final nome = await pedirNome(ctx);
                  if (nome == null) return;
                  final p = MinhaBiblioteca.i.criarPlaylist(nome);
                  MinhaBiblioteca.i.alternarNaPlaylist(p, f);
                },
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final p in lista)
                    ListTile(
                      leading: capa(p.nome, tamanho: 48, quadrada: true),
                      title: Text(p.nome),
                      subtitle: Text('${p.faixas.length} músicas'),
                      trailing: MinhaBiblioteca.i.estaNa(p, f.id)
                          ? const Icon(Icons.check_circle, color: verde)
                          : const Icon(Icons.radio_button_unchecked,
                              color: cinzaTexto),
                      onTap: () => MinhaBiblioteca.i.alternarNaPlaylist(p, f),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: verde,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Concluir'),
                ),
              ),
            ]),
          );
        },
      ),
    ),
  );
}

/// Aba "Playlists" da biblioteca.
class ListaPlaylists extends StatelessWidget {
  const ListaPlaylists({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: MinhaBiblioteca.i,
        builder: (context, _) {
          final lista = MinhaBiblioteca.i.playlists;
          return ListView(children: [
            ListTile(
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add, color: verde, size: 28),
              ),
              title: const Text('Nova playlist',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                final nome = await pedirNome(context);
                if (nome != null) MinhaBiblioteca.i.criarPlaylist(nome);
              },
            ),
            for (final p in lista)
              ListTile(
                leading: capa(p.nome, tamanho: 56, quadrada: true),
                title: Text(p.nome),
                subtitle: Text('${p.faixas.length} músicas'),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => TelaPlaylist(p))),
              ),
            if (lista.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                    'Você ainda não criou playlists.\nToque em "Nova playlist" ou use o menu ⋯ de qualquer música.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cinzaTexto)),
              ),
          ]);
        },
      );
}

/// Aba "Favoritas" da biblioteca.
class ListaFavoritas extends StatelessWidget {
  const ListaFavoritas({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: MinhaBiblioteca.i,
        builder: (context, _) {
          final favs = MinhaBiblioteca.i.favoritos;
          if (favs.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nenhuma favorita ainda.\nToque no ♥ no player ou no menu ⋯ de uma música.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cinzaTexto)),
            ));
          }
          return ListView(children: [
            BotoesTocar(
              aoTocar: () => PlayerService.instancia.tocarLista(favs, 0),
              aoAleatorio: () =>
                  PlayerService.instancia.tocarLista(favs, 0, aleatorio: true),
              extra: BotaoBaixarLote(favs, nome: 'suas favoritas'),
            ),
            for (var i = 0; i < favs.length; i++)
              LinhaFaixa(
                  faixa: favs[i],
                  onTap: () => PlayerService.instancia.tocarLista(favs, i)),
          ]);
        },
      );
}

class TelaPlaylist extends StatelessWidget {
  final Playlist playlist;
  const TelaPlaylist(this.playlist, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: MinhaBiblioteca.i,
        builder: (context, _) {
          final existe = MinhaBiblioteca.i.playlists.any((p) => p.id == playlist.id);
          if (!existe) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => Navigator.maybePop(context));
          }
          final fs = playlist.faixas;
          return Moldura(
            appBar: AppBar(
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'renomear') {
                      final nome = await pedirNome(context,
                          titulo: 'Renomear playlist', inicial: playlist.nome);
                      if (nome != null) MinhaBiblioteca.i.renomear(playlist, nome);
                    } else if (v == 'excluir') {
                      MinhaBiblioteca.i.excluir(playlist);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'renomear', child: Text('Renomear')),
                    PopupMenuItem(value: 'excluir', child: Text('Excluir playlist')),
                  ],
                ),
              ],
            ),
            corpo: ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(children: [
                  capa(playlist.nome, tamanho: 112, quadrada: true),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(playlist.nome,
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('Sua playlist · ${fs.length} músicas',
                              style: const TextStyle(
                                  fontSize: 13, color: cinzaTexto)),
                        ]),
                  ),
                ]),
              ),
              if (fs.isNotEmpty)
                BotoesTocar(
                  aoTocar: () => PlayerService.instancia.tocarLista(fs, 0),
                  aoAleatorio: () =>
                      PlayerService.instancia.tocarLista(fs, 0, aleatorio: true),
                  extra: BotaoBaixarLote(fs, nome: playlist.nome),
                ),
              for (var i = 0; i < fs.length; i++)
                LinhaFaixa(
                    faixa: fs[i],
                    daPlaylist: playlist,
                    onTap: () => PlayerService.instancia.tocarLista(fs, i)),
              if (fs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                      'Playlist vazia.\nUse o menu ⋯ de uma música e escolha "Adicionar à playlist".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cinzaTexto)),
                ),
            ]),
          );
        },
      );
}
