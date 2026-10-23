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

_Zurzeit keine._

## Erledigt

### ForeverQuests: Filter „Aktuelle Zone“ zeigt alles (behoben, bestätigt 2026-10-23)
- **Was passierte:** Mit dem Filter „nur aktuelle Zone“ zeigte der Tracker trotzdem alle Quests.
- **Stand:** laut Patzlinger behoben (im Spiel geprüft); gemeldet 2026-10-19.

### ForeverBags: Bank zeigt zu viele Taschenplätze (behoben 2026-10-20)
- **Ursache:** In diesem Client ist Behälter -1 der Schlüsselbund (nicht mehr das Bankfach), und ForeverBags las
  pauschal die Bankfächer 1–6 – auch nicht gekaufte, die trotzdem eine Größe melden.
- **Lösung:** nur die gekauften Fächer aus `C_Bank.FetchPurchasedBankTabData` (wie Blizzards Bankfenster); -1 nur
  noch, wenn es `Enum.BagIndex.Bank` gibt (klassische Bank).
