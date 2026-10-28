import 'package:flutter/material.dart';
import 'artista.dart';
import 'biblioteca_usuario.dart';
import 'catalogo.dart';
import 'downloads_tela.dart';
import 'player.dart';
import 'playlists.dart';
import 'widgets.dart';

/// Estrutura principal: 3 abas (Inicio, Buscar, Biblioteca) + mini-player.
class Shell extends StatefulWidget {
  final Catalogo cat;
  const Shell(this.cat, {super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _aba = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: IndexedStack(index: _aba, children: [
            AbaInicio(widget.cat),
            AbaBuscar(widget.cat),
            AbaBiblioteca(widget.cat),
          ]),
        ),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _aba,
            onDestinationSelected: (i) => setState(() => _aba = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Início'),
              NavigationDestination(
                  icon: Icon(Icons.search), label: 'Buscar'),
              NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: 'Biblioteca'),
            ],
          ),
        ]),
      );
}

class AbaInicio extends StatelessWidget {
  final Catalogo cat;
  const AbaInicio(this.cat, {super.key});

  String get _saudacao {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    final generos = cat.generos.where((g) => g.nome != 'Outros').take(6).toList();
    final destaques = cat.artistas.take(12).toList();
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Row(children: [
          Expanded(
            child: Text(_saudacao,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          const Text('v0.4.0+4',
              style: TextStyle(fontSize: 12, color: cinzaTexto)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 56),
          itemCount: generos.length,
          itemBuilder: (_, i) {
            final g = generos[i];
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TelaGenero(cat, g))),
              child: Container(
                decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(6)),
                clipBehavior: Clip.antiAlias,
                child: Row(children: [
                  Container(width: 56, color: corDe(g.nome)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(g.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600))),
                ]),
              ),
            );
          },
        ),
      ),
      ListenableBuilder(
        listenable: MinhaBiblioteca.i,
        builder: (context, _) {
          final rec = MinhaBiblioteca.i.recentes;
          if (rec.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            secao('Tocadas recentemente'),
            SizedBox(
              height: 178,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: rec.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => InkWell(
                  onTap: () => PlayerService.instancia.tocarLista(rec, i),
                  child: SizedBox(
                    width: 120,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          capa(rec[i].artista,
                              tamanho: 120, quadrada: true, foto: rec[i].foto),
                          const SizedBox(height: 8),
                          Text(rec[i].tituloCompleto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                          Text(rec[i].artista,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: cinzaTexto)),
                        ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
      secao('Artistas para você'),
      SizedBox(
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: destaques.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final a = destaques[i];
            return InkWell(
              borderRadius: BorderRadius.circular(48),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TelaArtista(cat, a))),
              child: SizedBox(
                width: 96,
                child: Column(children: [
                  capa(a.nome, tamanho: 96, foto: a.foto),
                  const SizedBox(height: 8),
                  Text(a.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13)),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 16),
    ]);
  }
}

class AbaBuscar extends StatefulWidget {
  final Catalogo cat;
  const AbaBuscar(this.cat, {super.key});
  @override
  State<AbaBuscar> createState() => _AbaBuscarState();
}

class _AbaBuscarState extends State<AbaBuscar> {
  final _c = TextEditingController();
  List<Faixa> _faixas = [];
  int _seq = 0;

  Future<void> _buscarFaixas(String q) async {
    final meu = ++_seq;
    final r = q.length < 2 ? <Faixa>[] : await widget.cat.buscarFaixas(q);
    if (mounted && meu == _seq) setState(() => _faixas = r);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _c.text.trim().toLowerCase();
    final artistas = q.length < 2
        ? <ArtistaResumo>[]
        : widget.cat.artistas
            .where((a) => a.nome.toLowerCase().contains(q))
            .take(50)
            .toList();
    final generos = q.length < 2
        ? <Genero>[]
        : widget.cat.generos
            .where((g) => g.nome.toLowerCase().contains(q))
            .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text('Buscar',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: TextField(
          controller: _c,
          onChanged: (v) {
            setState(() {});
            _buscarFaixas(v.trim());
          },
          decoration: InputDecoration(
            hintText: 'Músicas, artistas ou gêneros',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(_c.clear);
                      _buscarFaixas('');
                    }),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: q.length < 2
            ? GradeGeneros(widget.cat)
            : ListView(children: [
                if (generos.isNotEmpty) secao('Gêneros'),
                for (final g in generos)
                  ListTile(
                    leading: const Icon(Icons.library_music, color: verde),
                    title: Text(g.nome),
                    subtitle: Text('${g.artistas} artistas'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TelaGenero(widget.cat, g))),
                  ),
                if (artistas.isNotEmpty) secao('Artistas'),
                for (final a in artistas)
                  ListTile(
                    leading: capa(a.nome, tamanho: 48, foto: a.foto),
                    title: Text(a.nome),
                    subtitle: Text(a.genero),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TelaArtista(widget.cat, a))),
                  ),
                if (_faixas.isNotEmpty) secao('Músicas'),
                for (var i = 0; i < _faixas.length; i++)
                  LinhaFaixa(
                      faixa: _faixas[i],
                      onTap: () =>
                          PlayerService.instancia.tocarLista(_faixas, i)),
                if (artistas.isEmpty && generos.isEmpty && _faixas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Nada encontrado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cinzaTexto)),
                  ),
              ]),
      ),
    ]);
  }
}

class AbaBiblioteca extends StatefulWidget {
  final Catalogo cat;
  const AbaBiblioteca(this.cat, {super.key});
  @override
  State<AbaBiblioteca> createState() => _AbaBibliotecaState();
}

class _AbaBibliotecaState extends State<AbaBiblioteca> {
  int _sel = 0;
  static const _nomes = ['Artistas', 'Gêneros', 'Favoritas', 'Playlists', 'Baixadas'];

  @override
  Widget build(BuildContext context) {
    final Widget corpo = switch (_sel) {
      0 => ListaDeArtistas(widget.cat, widget.cat.artistas),
      1 => GradeGeneros(widget.cat),
      2 => const ListaFavoritas(),
      3 => const ListaPlaylists(),
      _ => const ListaBaixadas(),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text('Biblioteca',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          itemCount: _nomes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ChoiceChip(
            label: Text(_nomes[i]),
            selected: _sel == i,
            showCheckmark: false,
            selectedColor: verde,
            labelStyle: TextStyle(
                color: _sel == i ? Colors.black : null,
                fontWeight: FontWeight.w600),
            shape: const StadiumBorder(),
            onSelected: (_) => setState(() => _sel = i),
          ),
        ),
      ),
      Expanded(child: corpo),
    ]);
  }
}
