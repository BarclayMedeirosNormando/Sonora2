import 'package:flutter/material.dart';
import 'biblioteca_usuario.dart';
import 'player.dart';
import 'playlists.dart';
import 'widgets.dart';

String _fmt(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class PlayerTela extends StatelessWidget {
  const PlayerTela({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PlayerService.instancia;
    return ListenableBuilder(
      listenable: Listenable.merge([p, MinhaBiblioteca.i]),
      builder: (context, _) {
        final f = p.atual;
        if (f == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => Navigator.maybePop(context));
          return const Scaffold();
        }
        final fav = MinhaBiblioteca.i.ehFavorito(f.id);
        final lado = (MediaQuery.of(context).size.width - 64).clamp(180.0, 340.0);
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
                tooltip: 'Fechar',
                icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                onPressed: () => Navigator.pop(context)),
            centerTitle: true,
            title: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('TOCANDO DE',
                  style: TextStyle(
                      fontSize: 11, letterSpacing: 1, color: cinzaTexto)),
              Text(f.artista,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
            actions: [
              IconButton(
                  tooltip: 'Mais opções',
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => menuFaixa(context, f)),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(children: [
                const SizedBox(height: 16),
                capa(f.artista, tamanho: lado, quadrada: true, foto: f.foto),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.tituloCompleto,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(p.erro ?? f.artista,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: p.erro != null
                                      ? Colors.redAccent
                                      : cinzaTexto)),
                        ]),
                  ),
                  IconButton(
                      tooltip: fav ? 'Remover dos favoritos' : 'Favoritar',
                      iconSize: 28,
                      icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                          color: fav ? verde : null),
                      onPressed: () => MinhaBiblioteca.i.alternarFavorito(f)),
                ]),
                const _Barra(),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                          tooltip: 'Embaralhar',
                          icon: Icon(Icons.shuffle,
                              color: p.embaralhar ? verde : cinzaTexto),
                          onPressed: p.alternarEmbaralhar),
                      IconButton(
                          tooltip: 'Anterior',
                          iconSize: 38,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: p.anterior),
                      Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: IconButton(
                            tooltip: p.tocando ? 'Pausar' : 'Tocar',
                            iconSize: 36,
                            color: Colors.black,
                            icon: Icon(p.tocando ? Icons.pause : Icons.play_arrow),
                            onPressed: p.alternar),
                      ),
                      IconButton(
                          tooltip: 'Próxima',
                          iconSize: 38,
                          icon: const Icon(Icons.skip_next),
                          onPressed: p.proxima),
                      IconButton(
                          tooltip: 'Repetir',
                          icon: Icon(
                              p.repetir == 2 ? Icons.repeat_one : Icons.repeat,
                              color: p.repetir == 0 ? cinzaTexto : verde),
                          onPressed: p.alternarRepetir),
                    ]),
                const SizedBox(height: 8),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                          tooltip: 'Timer para dormir',
                          icon: Icon(Icons.bedtime_outlined,
                              color: p.sonoAte != null ? verde : cinzaTexto),
                          onPressed: () => _sono(context)),
                      IconButton(
                          tooltip: 'Adicionar à playlist',
                          icon: const Icon(Icons.playlist_add, color: cinzaTexto),
                          onPressed: () => adicionarAPlaylist(context, f)),
                      IconButton(
                          tooltip: 'Fila',
                          icon: const Icon(Icons.queue_music, color: cinzaTexto),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const TelaFila()))),
                    ]),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        );
      },
    );
  }

  void _sono(BuildContext context) {
    final p = PlayerService.instancia;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
              title: Text('Timer para dormir',
                  style: TextStyle(fontWeight: FontWeight.w700))),
          for (final m in [15, 30, 45, 60])
            ListTile(
              title: Text('$m minutos'),
              onTap: () {
                p.agendarSono(Duration(minutes: m));
                Navigator.pop(ctx);
              },
            ),
          if (p.sonoAte != null)
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Desativar timer'),
              onTap: () {
                p.agendarSono(null);
                Navigator.pop(ctx);
              },
            ),
        ]),
      ),
    );
  }
}

/// Barra de progresso com tempo atual e total.
class _Barra extends StatefulWidget {
  const _Barra();
  @override
  State<_Barra> createState() => _BarraState();
}

class _BarraState extends State<_Barra> {
  double? _arrastando;

  @override
  Widget build(BuildContext context) {
    final p = PlayerService.instancia;
    return StreamBuilder<Duration?>(
      stream: p.duracao,
      builder: (_, ds) {
        final total = ds.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        return StreamBuilder<Duration>(
          stream: p.posicao,
          builder: (_, ps) {
            final pos = ps.data ?? Duration.zero;
            final topo = max > 0 ? max : 1.0;
            final v = (_arrastando ?? pos.inMilliseconds.toDouble())
                .clamp(0.0, topo)
                .toDouble();
            return Column(children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF444444),
                    thumbColor: Colors.white,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7)),
                child: Slider(
                  value: v,
                  max: topo,
                  onChanged: max > 0 ? (x) => setState(() => _arrastando = x) : null,
                  onChangeEnd: (x) {
                    p.ir(Duration(milliseconds: x.round()));
                    setState(() => _arrastando = null);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(Duration(milliseconds: v.round())),
                          style: const TextStyle(
                              fontSize: 12, color: cinzaTexto)),
                      Text(_fmt(total),
                          style: const TextStyle(
                              fontSize: 12, color: cinzaTexto)),
                    ]),
              ),
            ]);
          },
        );
      },
    );
  }
}

class TelaFila extends StatelessWidget {
  const TelaFila({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PlayerService.instancia;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final fila = p.fila;
        return Scaffold(
          appBar: AppBar(title: const Text('Fila')),
          body: fila.isEmpty
              ? const Center(
                  child: Text('A fila está vazia.',
                      style: TextStyle(color: cinzaTexto)))
              : ReorderableListView.builder(
                  itemCount: fila.length,
                  onReorder: p.reordenar,
                  itemBuilder: (_, i) {
                    final f = fila[i];
                    final atual = i == p.indice;
                    return ListTile(
                      key: ObjectKey(f),
                      leading: capa(f.artista,
                          tamanho: 44, quadrada: true, foto: f.foto),
                      title: Text(f.tituloCompleto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: atual ? verde : null)),
                      subtitle: Text(atual ? 'Tocando agora · ${f.artista}' : f.artista,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.drag_handle, color: cinzaTexto),
                      onTap: () => p.tocarIndice(i),
                    );
                  },
                ),
        );
      },
    );
  }
}
