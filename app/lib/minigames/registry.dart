import 'package:mg_api/mg_api.dart';
import 'package:mg_sirky/mg_sirky.dart';
import 'package:shared_gen/shared_gen.dart';

/// Minigames this client implements; the Gallery greys out the rest.
const Map<MinigameId, Minigame> minigames = {MinigameId.sirky: SirkyGame()};
