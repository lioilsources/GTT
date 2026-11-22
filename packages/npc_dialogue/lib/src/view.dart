import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';
import 'session.dart';

/// Loads content/npc.json (written by `metro sync`) from the app bundle.
Future<NpcPack> loadNpcPack(AssetBundle bundle, {String shared = 'assets/shared/'}) async =>
    NpcPack.fromJson(jsonDecode(await bundle.loadString('${shared}content/npc.json')) as Map<String, Object?>);

/// The app-wide session of the current city (its state is restored from that city's save).
DialogueSession? dialogueSession;
String? _sessionCity;
NpcPack? _pack;

/// Loads the content once and creates the app-wide session; a different city (specs/cities.md)
/// gets a fresh session, skits are picked by `city`.
Future<DialogueSession> ensureDialogueSession(Tuning tuning, {String city = 'nyc', int? seed}) async {
  final existing = dialogueSession;
  if (existing != null && _sessionCity == city) return existing;
  final pack = _pack ??= await loadNpcPack(rootBundle);
  final again = dialogueSession;
  if (again != null && _sessionCity == city) return again;
  _sessionCity = city;
  return dialogueSession = DialogueSession(pack, tuning.npc, city, seed ?? DateTime.now().microsecondsSinceEpoch);
}

/// The opponent for a minigame result screen (MinigameContext.opponentId), or null.
MinigameOpponent? opponentFor(DialogueSession? session, String? characterId, int seed, String locale) {
  final c = characterId == null ? null : session?.character(characterId);
  if (c == null) return null;
  return MinigameOpponent(
    id: c.id,
    name: c.name,
    portrait: c.portrait,
    line: (winner) => quipOf(c, winner, seed, locale),
  );
}

const _toneKeys = {'flirt': MessageKey.npcToneFlirt, 'joke': MessageKey.npcToneJoke, 'dry': MessageKey.npcToneDry};

const contextKeys = {
  'street': MessageKey.npcCtxStreet,
  'bar': MessageKey.npcCtxBar,
  'shop': MessageKey.npcCtxShop,
  'minigame_win': MessageKey.npcCtxMinigameWin,
  'minigame_lose': MessageKey.npcCtxMinigameLose,
  'crash': MessageKey.npcCtxCrash,
  'car_owner': MessageKey.npcCtxCarOwner,
};

/// Placeholder portrait: initials on a token-coloured circle (manga portraits come later via ComfyUI).
class NpcPortrait extends StatelessWidget {
  const NpcPortrait({super.key, required this.name, required this.index, this.size = 56});

  final String name;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    const colors = Tokens.colorNpcPortraits;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Color(colors[index % colors.length]),
      child: Text(
        initials(name),
        style: TextStyle(
          color: const Color(Tokens.colorNpcPortraitText),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Shows the dialogue of a skit [session] has already started ([DialogueSession.startSkit]):
/// speech bubbles, three reply buttons, walk away. [onClose] is called once.
class DialogueView extends StatefulWidget {
  const DialogueView({super.key, required this.session, required this.locale, required this.onClose});

  final DialogueSession session;
  final String locale;
  final VoidCallback onClose;

  /// Street chat entry for other features: starts a skit and pushes the dialogue as a route.
  /// Returns false when no skit fits the character and context.
  static bool startSkit(
    BuildContext context,
    DialogueSession session,
    String characterId,
    String npcContext,
    String locale,
  ) {
    if (!session.startSkit(characterId, npcContext)) return false;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => DialogueView(session: session, locale: locale, onClose: () => Navigator.of(route).pop()),
      ),
    );
    return true;
  }

  @override
  State<DialogueView> createState() => _DialogueViewState();
}

class _Line {
  const _Line(this.mine, this.text, [this.tag]);
  final bool mine;
  final String text;
  final String? tag;
}

class _DialogueViewState extends State<DialogueView> {
  final List<_Line> _log = [];
  final ScrollController _scroll = ScrollController();
  late final String _charId = widget.session.state.character;
  bool _closed = false;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => tr(widget.locale, k, a);
  String x(NpcText text) => npcText(text, widget.locale);

  @override
  void initState() {
    super.initState();
    final b = widget.session.beat;
    if (b != null) _log.add(_Line(false, x(b.npc)));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _pick(String tone) {
    final s = widget.session;
    final beat = s.beat;
    if (beat == null) return;
    setState(() {
      _log.add(_Line(true, x(toneText(beat.replies, tone)), t(_toneKeys[tone]!)));
      s.reply(tone);
      _log.add(_Line(false, x(toneText(beat.reactions, tone))));
      final next = s.beat;
      if (next != null) _log.add(_Line(false, x(next.npc)));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.session.leave();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final ch = s.character(_charId)!;
    final max = s.tuning.vibeMax;
    final vibe = s.vibe(_charId);
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: 13);
    final beat = s.beat;
    final r = s.result();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Material(
        color: const Color(Tokens.colorUiBackground),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    NpcPortrait(name: ch.name, index: ch.portrait),
                    const SizedBox(width: Tokens.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(MessageKey.npcNameAge, {'name': ch.name, 'age': ch.age}),
                            style: const TextStyle(color: Color(Tokens.colorBrandAccent), fontWeight: FontWeight.w700),
                          ),
                          Text(x(ch.bio), style: muted),
                          const SizedBox(height: Tokens.spaceXs),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: max <= 0 ? 0 : vibe / max,
                                    minHeight: 6,
                                    color: const Color(Tokens.colorNpcVibe),
                                    backgroundColor: const Color(Tokens.colorNpcVibeTrack),
                                  ),
                                ),
                              ),
                              const SizedBox(width: Tokens.spaceSm),
                              Text(t(MessageKey.npcVibe, {'vibe': vibe, 'max': max}), style: muted),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: Tokens.spaceMd),
                    children: [for (final l in _log) _Bubble(line: l)],
                  ),
                ),
                if (beat != null) ...[
                  for (final tone in tones)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tokens.spaceSm),
                      child: Material(
                        color: const Color(Tokens.colorNpcReply),
                        borderRadius: BorderRadius.circular(Tokens.radiusButton),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Tokens.radiusButton),
                          onTap: () => _pick(tone),
                          child: Padding(
                            padding: const EdgeInsets.all(Tokens.spaceMd),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t(_toneKeys[tone]!).toUpperCase(),
                                  style: const TextStyle(color: Color(Tokens.colorUiTextFaint), fontSize: 10),
                                ),
                                Text(
                                  x(toneText(beat.replies, tone)),
                                  style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  OutlinedButton(onPressed: _close, child: Text(t(MessageKey.npcLeave))),
                ] else ...[
                  Text(
                    r?.newContact == true
                        ? t(MessageKey.npcNewContact, {'name': ch.name})
                        : r?.contact == true
                        ? t(MessageKey.npcIsContact, {'name': ch.name})
                        : t(MessageKey.npcNoContact),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(r?.newContact == true ? Tokens.colorNpcContact : Tokens.colorUiTextMuted),
                      fontWeight: r?.newContact == true ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: Tokens.spaceSm),
                  FilledButton(onPressed: _close, child: Text(t(MessageKey.npcDone))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.line});

  final _Line line;

  @override
  Widget build(BuildContext context) {
    final mine = line.mine;
    final fg = Color(mine ? Tokens.colorNpcPlayerText : Tokens.colorNpcBubbleText);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.85,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: Tokens.spaceSm),
            padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
            decoration: BoxDecoration(
              color: Color(mine ? Tokens.colorNpcPlayer : Tokens.colorNpcBubble),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (line.tag != null)
                  Text(line.tag!.toUpperCase(), style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 10)),
                Text(line.text, style: TextStyle(color: fg, height: 1.35)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Debug list of skits (specs/dialogue.md "Ladění"): every character × context; a row starts the
/// skit through the same [DialogueView.startSkit] other features use.
class SkitsScreen extends StatefulWidget {
  const SkitsScreen({super.key, required this.session, required this.locale});

  final DialogueSession session;
  final String locale;

  @override
  State<SkitsScreen> createState() => _SkitsScreenState();
}

class _SkitsScreenState extends State<SkitsScreen> {
  String t(MessageKey k, [Map<String, Object> a = const {}]) => tr(widget.locale, k, a);

  void _open(String characterId, String npcContext) {
    final s = widget.session;
    if (!s.startSkit(characterId, npcContext)) return;
    debugPrint('[metro skit] ${s.state.skit}');
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (route) => DialogueView(
              session: s,
              locale: widget.locale,
              onClose: () {
                debugPrint('[metro skit] ${s.result()?.toJson()}');
                Navigator.of(route).pop();
              },
            ),
          ),
        )
        .then((_) => mounted ? setState(() {}) : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: 13);
    return Scaffold(
      backgroundColor: const Color(Tokens.colorUiBackground),
      appBar: AppBar(
        backgroundColor: const Color(Tokens.colorUiBackground),
        foregroundColor: const Color(Tokens.colorUiText),
        title: Text(t(MessageKey.npcSkits), style: const TextStyle(color: Color(Tokens.colorBrandAccent))),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.spaceMd),
        children: [
          Text(t(MessageKey.npcSkitsHint), style: muted),
          Text(t(MessageKey.npcContacts, {'n': s.state.contacts.length}), style: muted),
          for (final c in s.pack.characters) ...[
            const SizedBox(height: Tokens.spaceMd),
            Row(
              children: [
                NpcPortrait(name: c.name, index: c.portrait, size: 32),
                const SizedBox(width: Tokens.spaceSm),
                Expanded(
                  child: Text(
                    '${t(MessageKey.npcNameAge, {'name': c.name, 'age': c.age})} · '
                    '${t(MessageKey.npcVibe, {'vibe': s.vibe(c.id), 'max': s.tuning.vibeMax})}'
                    '${s.state.contacts.contains(c.id) ? ' ✓' : ''}',
                    style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            Text(npcText(c.bio, widget.locale), style: muted),
            for (final x in npcContexts)
              ListTile(
                dense: true,
                enabled: s.rules.candidates(c.id, x).isNotEmpty,
                title: Text(t(contextKeys[x]!), style: const TextStyle(color: Color(Tokens.colorUiText))),
                trailing: Text('${s.rules.candidates(c.id, x).length}', style: muted),
                onTap: () => _open(c.id, x),
              ),
          ],
        ],
      ),
    );
  }
}
