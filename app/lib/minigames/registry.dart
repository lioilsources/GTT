import 'package:mg_api/mg_api.dart';
import 'package:mg_cara/mg_cara.dart';
import 'package:mg_dama/mg_dama.dart';
import 'package:mg_desetitisic/mg_desetitisic.dart';
import 'package:mg_koulena/mg_koulena.dart';
import 'package:mg_kulicky/mg_kulicky.dart';
import 'package:mg_nohejbal/mg_nohejbal.dart';
import 'package:mg_oko/mg_oko.dart';
import 'package:mg_sipky/mg_sipky.dart';
import 'package:mg_sirky/mg_sirky.dart';
import 'package:mg_strelnice/mg_strelnice.dart';
import 'package:shared_gen/shared_gen.dart';

import '../taxi/taxi_hud.dart' show TaxiGame;

/// Minigames this client implements; the Gallery greys out the rest.
const Map<MinigameId, Minigame> minigames = {
  MinigameId.sirky: SirkyGame(),
  MinigameId.oko: OkoGame(),
  MinigameId.dama: DamaGame(),
  MinigameId.desetitisic: DesetitisicGame(),
  MinigameId.sipky: SipkyGame(),
  MinigameId.strelnice: StrelniceGame(),
  MinigameId.koulena: KoulenaGame(),
  MinigameId.kulicky: KulickyGame(),
  MinigameId.cara: CaraGame(),
  MinigameId.nohejbal: NohejbalGame(),
  // World minigame: the Gallery card starts the shift in the city (specs/minigames/taxi.md).
  MinigameId.taxi: TaxiGame(),
};
