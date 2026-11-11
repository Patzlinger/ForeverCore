# Bekannte Fehler (Known Bugs)

Offene Fehler, die im Spiel aufgefallen sind, aber noch nicht behoben wurden.
**Wer gerade nichts Bestimmtes entwickelt oder fragt, was es noch zu tun gibt: hier anfangen.**

Ablauf:
- Neuer Fehler: unten bei „Offen“ eintragen – Addon, was passiert, was eigentlich passieren sollte, wie man es
  nachstellt (soweit bekannt), Datum und wer ihn gefunden hat.
- Behoben: Eintrag mit Datum und kurzer Ursache nach „Erledigt“ verschieben (nicht löschen – hilft bei Rückfällen).
- Fehler aus BugSack (`WTF\Account\*\SavedVariables\!BugGrabber.lua`) gehören nur hierher, wenn sie nicht sofort
  behoben werden.

## Offen

### ForeverQuests: „blocked from an action only available to the Blizzard UI“ nach Questmarker-Klick (Fix wartet auf Bestätigung)
- **Was passiert:** Quest im Tracker anklicken → Weltkarte → dunkelroten „?“-Marker anklicken (gelb, Super-Tracking) →
  Karte schließen → ADDON_ACTION_BLOCKED, Spieler muss ForeverQuests abschalten. Gemeldet 2026-11-09 auf CurseForge
  (noXceptionz).
- **Vermutete Ursache:** Karte durch ForeverQuests-Code „berührt“ (Taint): freie Kartengröße schrieb Blizzards
  `minimizedWidth/-Height` und rief `OnFrameSizeChanged`; eigenes Kreuz löste `close:Click()` aus; `maximize:Hide()`,
  `Minimize()`, `SetHighlightedQuestID`, `pin:Hide()` (mit Questie) aus Addon-Code.
- **Stand:** alles davon entfernt bzw. taint-frei umgebaut (`5b47c72`, 2026-11-10). Prüfen: Ablauf oben mit
  `/console taintLog 1`, je ohne/mit Leatrix Maps und Questie, Schließen per Kreuz, M und Escape.

### Entzaubern per Gamepad-Aktionsknopf: Mausklick auf Taschenplatz tut nichts (offen, ungeklärt)
- **Was passiert:** Entzaubern vom Berufsfenster auf die Gamepad-Leiste gezogen; Knopf drücken → Tasche geht auf →
  Links-/Rechtsklick auf Gegenstand bewirkt nichts. Aus dem Berufsfenster heraus geht es. Gemeldet 2026-11-09 (noXceptionz).
- **Stand:** Blizzards Klick-Code (`ContainerFrameItemButton_OnClick`, Zweig forever) ruft bei `SpellCanTargetItem()`
  `UseContainerItem` – nichts von uns fängt den Klick ab. Behoben (Hub v83, `6ab0ba8`): nach Schließen mit B schluckte
  das nächste Forever-Fenster den ersten Gamepad-Druck; im Kampf `SetPropagateKeyboardInput` (gesperrt). Weitere
  Vermutung: Gamepad-Zielmodus des Clients (`GamePadCursorForTargeting`) ignoriert echte Mausklicks – nicht von uns.
- **Nächster Schritt:** Spieler fragen: BugSack-Text? Geht es mit A/virtuellem Cursor statt Maus? Mit „Blizzards
  Taschenfenster ersetzen“ aus? Selbst testen, sobald ein Controller dranhängt.
- **Bewusst nicht geändert:** ForeverBags `NoItemContext` (`Bags.lua`, `Bank.lua`) legt eine eigene
  `GetItemContextMatchResult` an Blizzards Taschenknopf (Verstoß gegen die Taint-Regel). Blizzard ruft sie nur in
  `UpdateItemContextMatching` (Abdunklung), nicht beim Klick – daher wohl nicht die Ursache. Umbau (Hook auf
  `UpdateItemContextOverlay`, `ItemContextOverlay` per Deckkraft) erst mit Test im Spiel: ohne die Funktion waren
  Bankplätze früher dunkel und nicht klickbar.

### ForeverQuests: Taint „GetAuraDataByIndex … tainted by ForeverQuests“ im Bearbeitungsmodus (unbestätigt)
- **Was passiert:** BugSack, 3× am 2026-11-07 19:38 – also nach dem Fix `f3e1c27` (2026-11-06, Tracker wird nicht mehr
  versteckt/gezeigt, sondern über Deckkraft ausgeblendet). Möglich: Spiel lief noch mit altem Stand (kein Neustart).
- **Nächster Schritt:** Spiel neu starten, Bearbeitungsmodus öffnen/schließen, BugSack prüfen. Tritt es wieder auf:
  `SetAlpha(0)` auf `ObjectiveTrackerFrame` (Hub `UI.HideBlizzard`) als Ursache prüfen. Gefunden 2026-11-08.

### Handel in einer Instanz: Fenster schließt sofort, Gegenstand bleibt gesperrt (offen, ungeklärt)
- **Was passiert:** In einer Instanz schließt sich das Handelsfenster direkt nach dem Handelsversuch; der Gegenstand,
  der darin lag, bleibt in der Tasche gesperrt („stuck“). Gefunden 2026-11-11 (flowfy).
- **Stand:** BugSack ohne Fehler dazu. Kein Forever-Code schließt den Handel: ForeverSkin (`Extra.lua`, nur Aussehen
  + Ablegen per `ClickTradeButton`), ForeverBags (`Bags.lua`, öffnet/dockt Taschen bei `TRADE_SHOW`), ForeverCore
  `Movers.lua` (verschiebbar). Nichts davon ist instanzabhängig. Vermutung: Abbruch durch das Spiel (Abstand > ~10 m)
  + Blizzards Sperre nach Abbruch.
- **Nächster Schritt:** Chatmeldung beim Schließen? Zeitpunkt (Hineinlegen / „Handeln“ / Aktion des anderen)? Frisch
  erbeuteter seelengebundener Gegenstand? Nach `/reload` noch grau? Wenn nach `/reload` frei: ForeverBags aktualisiert
  die Sperre (`ITEM_LOCK_CHANGED`/`TRADE_CLOSED`) nicht – dort ansetzen.

## Erledigt

### BugSack-Fehler vom 5.–7.11.2026 (behoben, per Zeitstempel gegen Commits geprüft, 2026-11-08)
- Bars.lua `ManaNow` gesperrtes Mana (25×) → `Readable()` (2026-11-05); Units.lua `PlaceCombat` und Hub `GuidOf`
  (gesperrter Wert in Rechnung/Test) → `IsSecret`/`Secret` (`5336baab`, 2026-11-07); Zauberbuch `PickupSpell` im
  Kampf (`f3e1c27`, 2026-11-06). Fremde Fehler (Details, Auctionator, Blizzard-Auktionshaus) nicht von uns.

### ForeverPlates: „nur entfernbare (Purge)“ wirkte nicht bei ausgeschalteten Stärkungen (behoben 2026-11-08)
- **Lösung:** Option wird ausgegraut, solange „Stärkungen anzeigen“ aus ist (Options.lua).


### ForeverQuests: Filter „Aktuelle Zone“ zeigt alles (behoben, bestätigt 2026-10-23)
- **Was passierte:** Mit dem Filter „nur aktuelle Zone“ zeigte der Tracker trotzdem alle Quests.
- **Stand:** laut Patzlinger behoben (im Spiel geprüft); gemeldet 2026-10-19.

### ForeverBags: Bank zeigt zu viele Taschenplätze (behoben 2026-10-20)
- **Ursache:** In diesem Client ist Behälter -1 der Schlüsselbund (nicht mehr das Bankfach), und ForeverBags las
  pauschal die Bankfächer 1–6 – auch nicht gekaufte, die trotzdem eine Größe melden.
- **Lösung:** nur die gekauften Fächer aus `C_Bank.FetchPurchasedBankTabData` (wie Blizzards Bankfenster); -1 nur
  noch, wenn es `Enum.BagIndex.Bank` gibt (klassische Bank).
