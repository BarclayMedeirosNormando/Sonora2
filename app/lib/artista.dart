import 'package:flutter/material.dart';
import 'catalogo.dart';
import 'downloads_tela.dart';
import 'player.dart';
import 'widgets.dart';

class TelaArtista extends StatelessWidget {
  final Catalogo cat;
  final ArtistaResumo artista;
  const TelaArtista(this.cat, this.artista, {super.key});

  @override
  Widget build(BuildContext context) => Moldura(
        appBar: AppBar(),
        corpo: FutureBuilder<List<Faixa>>(
          future: cat.faixasDe(artista),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final faixas = snap.data!;
            final p = PlayerService.instancia;
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(children: [
                  capa(artista.nome, tamanho: 148, foto: artista.foto),
                  const SizedBox(height: 16),
                  Text(artista.nome,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${artista.genero} · ${faixas.length} músicas',
                      style: const TextStyle(fontSize: 13, color: cinzaTexto)),
                ]),
              ),
              BotoesTocar(
                aoTocar: () => p.tocarLista(faixas, 0),
                aoAleatorio: () => p.tocarLista(faixas, 0, aleatorio: true),
                extra: BotaoBaixarLote(faixas, nome: artista.nome),
              ),
              secao('Músicas'),
              for (var i = 0; i < faixas.length; i++)
                LinhaFaixa(faixa: faixas[i], onTap: () => p.tocarLista(faixas, i)),
            ]);
          },
        ),
      );
}

class TelaGenero extends StatelessWidget {
  final Catalogo cat;
  final Genero genero;
  const TelaGenero(this.cat, this.genero, {super.key});

  Future<void> _aleatorio() async {
    final artistas = cat.doGenero(genero.nome)..shuffle();
    final faixas = <Faixa>[];
    for (final a in artistas.take(25)) {
      faixas.addAll(await cat.faixasDe(a));
    }
    faixas.shuffle();
    await PlayerService.instancia.tocarLista(faixas, 0);
  }

  @override
  Widget build(BuildContext context) {
    final artistas = cat.doGenero(genero.nome);
    return Moldura(
      appBar: AppBar(title: Text(genero.nome)),
      corpo: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: corDe(genero.nome),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.library_music, size: 40),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gênero',
                        style: TextStyle(fontSize: 13, color: cinzaTexto)),
                    const SizedBox(height: 4),
                    Text('${genero.artistas} artistas · ${genero.faixas} músicas',
                        style: const TextStyle(fontSize: 15)),
                  ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: verde,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(44)),
            onPressed: _aleatorio,
            icon: const Icon(Icons.shuffle),
            label: const Text('Tocar aleatório'),
          ),
        ),
        ListaDeArtistas(cat, artistas, rolavel: false),
      ]),
    );
  }
}

/// Lista de artistas (foto, nome, genero e quantidade de musicas).
class ListaDeArtistas extends StatelessWidget {
  final Catalogo cat;
  final List<ArtistaResumo> artistas;
  final bool rolavel;
  const ListaDeArtistas(this.cat, this.artistas,
      {super.key, this.rolavel = true});

  @override
  Widget build(BuildContext context) => ListView.builder(
        shrinkWrap: !rolavel,
        physics: rolavel ? null : const NeverScrollableScrollPhysics(),
        itemCount: artistas.length,
        itemBuilder: (_, i) {
          final a = artistas[i];
          return ListTile(
            leading: capa(a.nome, tamanho: 48, foto: a.foto),
            title: Text(a.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${a.genero} · ${a.faixas} músicas'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => TelaArtista(cat, a))),
          );
        },
      );
}

/// Grade 2 colunas de generos.
class GradeGeneros extends StatelessWidget {
  final Catalogo cat;
  const GradeGeneros(this.cat, {super.key});

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7),
        itemCount: cat.generos.length,
        itemBuilder: (_, i) {
          final g = cat.generos[i];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => TelaGenero(cat, g))),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: corDe(g.nome), borderRadius: BorderRadius.circular(10)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.nome,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${g.artistas} artistas',
                        style: const TextStyle(fontSize: 12)),
                  ]),
            ),
          );
        },
      );
}
