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


### ForeverQuests: Filter „Aktuelle Zone“ zeigt alles
- **Was passiert:** Mit dem Filter „nur aktuelle Zone“ zeigt der Tracker trotzdem alle Quests. Die meisten anderen
  Filter funktionieren.
- **Erwartet:** nur Quests der Zone, in der man gerade ist.
- **Gemeldet:** 2026-10-19, Patzlinger

## Erledigt

### ForeverBags: Bank zeigt zu viele Taschenplätze (behoben 2026-10-20)
- **Ursache:** In diesem Client ist Behälter -1 der Schlüsselbund (nicht mehr das Bankfach), und ForeverBags las
  pauschal die Bankfächer 1–6 – auch nicht gekaufte, die trotzdem eine Größe melden.
- **Lösung:** nur die gekauften Fächer aus `C_Bank.FetchPurchasedBankTabData` (wie Blizzards Bankfenster); -1 nur
  noch, wenn es `Enum.BagIndex.Bank` gibt (klassische Bank).
