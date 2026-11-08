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

### ForeverQuests: Taint „GetAuraDataByIndex … tainted by ForeverQuests“ im Bearbeitungsmodus (unbestätigt)
- **Was passiert:** BugSack, 3× am 2026-11-07 19:38 – also nach dem Fix `f3e1c27` (2026-11-06, Tracker wird nicht mehr
  versteckt/gezeigt, sondern über Deckkraft ausgeblendet). Möglich: Spiel lief noch mit altem Stand (kein Neustart).
- **Nächster Schritt:** Spiel neu starten, Bearbeitungsmodus öffnen/schließen, BugSack prüfen. Tritt es wieder auf:
  `SetAlpha(0)` auf `ObjectiveTrackerFrame` (Hub `UI.HideBlizzard`) als Ursache prüfen. Gefunden 2026-11-08.

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
