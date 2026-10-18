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

### ForeverBags: Bank zeigt zu viele Taschenplätze
- **Was passiert:** Im Bankfenster erscheinen deutlich mehr Plätze, als das Bankfach laut Blizzards eigener
  Oberfläche hat.
- **Erwartet:** genau die Plätze von Bankfach und gekauften Bankfächern/-taschen wie bei Blizzard.
- **Gemeldet:** 2026-10-19, Patzlinger

### ForeverQuests: Filter „Aktuelle Zone“ zeigt alles
- **Was passiert:** Mit dem Filter „nur aktuelle Zone“ zeigt der Tracker trotzdem alle Quests. Die meisten anderen
  Filter funktionieren.
- **Erwartet:** nur Quests der Zone, in der man gerade ist.
- **Gemeldet:** 2026-10-19, Patzlinger

## Erledigt

(noch nichts)
