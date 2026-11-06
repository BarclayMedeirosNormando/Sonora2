import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
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

// ---------------------------------------------------------------------------
// Visual: cor dominante da foto, degrade de fundo, cor/icone por genero,
// barrinhas animadas e esqueleto de carregamento.
// ---------------------------------------------------------------------------
final Map<String, Color> _cacheCor = {};

/// Cor escura tirada da foto (para o fundo do player e da tela do artista).
Future<Color> corDominante(String? foto, String texto) async {
  final chave = foto ?? texto;
  final guardada = _cacheCor[chave];
  if (guardada != null) return guardada;
  Color cor = corDe(texto);
  if (foto != null && foto.startsWith('http')) {
    try {
      final pal = await PaletteGenerator.fromImageProvider(
          CachedNetworkImageProvider(foto),
          size: const Size(100, 100),
          maximumColorCount: 8);
      final base = pal.darkMutedColor?.color ??
          pal.dominantColor?.color ??
          pal.mutedColor?.color;
      if (base != null) {
        final h = HSLColor.fromColor(base);
        cor = h
            .withLightness(h.lightness.clamp(0.14, 0.30).toDouble())
            .withSaturation(h.saturation.clamp(0.25, 0.70).toDouble())
            .toColor();
      }
    } catch (_) {}
  }
  return _cacheCor[chave] = cor;
}

/// Fundo com degrade da cor da foto para o preto do app (muda suave de uma musica para outra).
class FundoDegrade extends StatefulWidget {
  final String? foto;
  final String texto;
  final Widget child;
  const FundoDegrade(
      {super.key, required this.foto, required this.texto, required this.child});
  @override
  State<FundoDegrade> createState() => _FundoDegradeState();
}

class _FundoDegradeState extends State<FundoDegrade> {
  late Color _cor = _cacheCor[widget.foto ?? widget.texto] ?? corDe(widget.texto);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant FundoDegrade old) {
    super.didUpdateWidget(old);
    if (old.foto != widget.foto || old.texto != widget.texto) _carregar();
  }

  Future<void> _carregar() async {
    final c = await corDominante(widget.foto, widget.texto);
    if (mounted && c != _cor) setState(() => _cor = c);
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: _cor),
        duration: const Duration(milliseconds: 600),
        builder: (_, cor, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cor ?? _cor, const Color(0xFF121212)],
              stops: const [0.0, 0.8],
            ),
          ),
          child: child,
        ),
        child: widget.child,
      );
}

const Map<String, List<Color>> _degradeGenero = {
  'Piseiro': [Color(0xFFE65100), Color(0xFF6B2B00)],
  'Forró': [Color(0xFFF9A825), Color(0xFF7A5200)],
  'Sertanejo': [Color(0xFF8D6E63), Color(0xFF3E2C26)],
  'Axé': [Color(0xFFD81B60), Color(0xFF6A0F32)],
  'Pagode/Samba': [Color(0xFF2E7D32), Color(0xFF123B16)],
  'MPB': [Color(0xFF6A1B9A), Color(0xFF2E0B47)],
  'Brega': [Color(0xFF00897B), Color(0xFF00342F)],
  'Gospel': [Color(0xFF3949AB), Color(0xFF151B52)],
  'Funk': [Color(0xFF7CB342), Color(0xFF33491A)],
  'Rap': [Color(0xFF455A64), Color(0xFF1B2327)],
  'Reggae': [Color(0xFFFF8F00), Color(0xFF6B3C00)],
  'Blues': [Color(0xFF1565C0), Color(0xFF0A2A55)],
  'Discoteca': [Color(0xFFAB47BC), Color(0xFF46154F)],
  'Rock': [Color(0xFFC62828), Color(0xFF4A0E0E)],
  'Pop': [Color(0xFF00ACC1), Color(0xFF00404A)],
  'Eletrônica': [Color(0xFF7C4DFF), Color(0xFF2A1A66)],
  'R&B/Soul': [Color(0xFF880E4F), Color(0xFF3B061F)],
  'Românticas': [Color(0xFFFF5252), Color(0xFF6D1414)],
  'Jazz': [Color(0xFF0277BD), Color(0xFF012B44)],
  'Clássica': [Color(0xFFA1887F), Color(0xFF4A3A33)],
  'K-Pop': [Color(0xFFFF4081), Color(0xFF7A1038)],
  'Outros': [Color(0xFF616161), Color(0xFF242424)],
};

/// Degrade (claro -> escuro) fixo de cada genero; generos novos usam a cor gerada do nome.
List<Color> gradienteDe(String genero) {
  final c = _degradeGenero[genero];
  if (c != null) return c;
  final b = corDe(genero);
  return [HSLColor.fromColor(b).withLightness(0.42).toColor(), b];
}

IconData iconeDe(String genero) => switch (genero) {
      'Rock' => Icons.bolt,
      'Pop' => Icons.star,
      'Piseiro' => Icons.celebration,
      'Forró' => Icons.wb_sunny,
      'Sertanejo' => Icons.landscape,
      'Axé' => Icons.beach_access,
      'Pagode/Samba' => Icons.groups,
      'MPB' => Icons.library_music,
      'Brega' => Icons.favorite,
      'Gospel' => Icons.volunteer_activism,
      'Funk' => Icons.local_fire_department,
      'Rap' => Icons.mic,
      'Reggae' => Icons.waves,
      'Blues' => Icons.album,
      'Discoteca' => Icons.nightlife,
      'Eletrônica' => Icons.graphic_eq,
      'R&B/Soul' => Icons.headphones,
      'Românticas' => Icons.favorite_border,
      'Jazz' => Icons.piano,
      'Clássica' => Icons.queue_music,
      'K-Pop' => Icons.auto_awesome,
      _ => Icons.music_note,
    };

/// Tres barrinhas verdes que dancam: indicam a musica que esta tocando.
class BarrasTocando extends StatefulWidget {
  const BarrasTocando({super.key});
  @override
  State<BarrasTocando> createState() => _BarrasTocandoState();
}

class _BarrasTocandoState extends State<BarrasTocando>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            double altura(double fase) =>
                0.25 + 0.75 * (0.5 + 0.5 * math.sin((_c.value + fase) * 2 * math.pi));
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final fase in const [0.0, 0.33, 0.66])
                  Container(
                    width: 4,
                    height: 18 * altura(fase),
                    decoration: BoxDecoration(
                        color: verde, borderRadius: BorderRadius.circular(2)),
                  ),
              ],
            );
          },
        ),
      );
}

/// Retangulos cinza que "respiram" enquanto a lista carrega.
class EsqueletoLista extends StatefulWidget {
  final int itens;
  const EsqueletoLista({super.key, this.itens = 8});
  @override
  State<EsqueletoLista> createState() => _EsqueletoListaState();
}

class _EsqueletoListaState extends State<EsqueletoLista>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final cor = Color.lerp(
              const Color(0xFF1E1E1E), const Color(0xFF2E2E2E), _c.value)!;
          Widget bloco(double w, double h) => Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                  color: cor, borderRadius: BorderRadius.circular(6)));
          return ListView(
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < widget.itens; i++)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(children: [
                    bloco(44, 44),
                    const SizedBox(width: 14),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bloco(180, 13),
                          const SizedBox(height: 8),
                          bloco(110, 10),
                        ]),
                  ]),
                ),
            ],
          );
        },
      );
}

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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(titulo,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
    );

/// Estrutura comum das telas internas: conteudo + mini-player fixo embaixo.
class Moldura extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget corpo;
  final bool atrasDaBarra; // corpo comeca atras da barra de cima (para fundos em degrade)
  const Moldura(
      {super.key, this.appBar, required this.corpo, this.atrasDaBarra = false});
  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: atrasDaBarra,
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
          child: GestureDetector(
            // arrastar o mini-player para cima abre o player
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -300) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const PlayerTela()));
              }
            },
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
                  Hero(
                      tag: 'capa-player',
                      child: capa(f.artista, tamanho: 40, foto: f.foto)),
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
              onTap: () {
                HapticFeedback.selectionClick();
                MinhaBiblioteca.i.alternarFavorito(f);
              },
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
              leading: const Icon(Icons.queue_play_next),
              title: const Text('Tocar a seguir'),
              onTap: () {
                PlayerService.instancia.tocarAProxima(f);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Adicionar à fila'),
              onTap: () {
                PlayerService.instancia.adicionarNaFila(f);
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
            if (tocandoEsta) ...[
              p.tocando
                  ? const BarrasTocando()
                  : const Icon(Icons.pause, size: 18, color: verde),
              const SizedBox(width: 8),
            ],
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
