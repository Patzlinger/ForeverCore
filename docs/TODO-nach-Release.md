# To-do nach dem Release

Aufgaben für die Zeit nach dem Release. Erledigtes abhaken (`[x]`) oder entfernen.

**⚠ = kann Funktionen oder Darstellung im Spiel verändern** – danach im Spiel prüfen. Ohne Zeichen: keine
Auswirkung im Spiel.

## Geplant

- [ ] ⚠ **Markierungen über Blizzards Schnell-Ping-Menü:** Weltmarkierungen mit dem Ping-Rad verbinden; Zielmarkierungen
      (Totenkopf, Kreuz …) per Mouseover über Gegner ebenfalls über das Ping-Rad setzen (Addon klären, z. B. ForeverHelpers).
      Die frühere Markierungsleiste ist seit 2026-11-07 die Gruppenleiste; Markierungs-Tasten laufen bis dahin
      über unsichtbare Knöpfe weiter (ForeverBars, Bars.lua GetMarkButtons)
- [ ] ⚠ **Ablaufzeit von Questgegenständen** (ForeverQuests, Tracker): Restzeit auch anzeigen, wenn der Questgegenstand
      nur begrenzt haltbar ist (Gegenstand-Tooltip auslesen). Quests mit eigener Frist zeigen ihre Restzeit seit
      2026-11-07 (Tracker.lua GetQuestTimerEnd) – im Spiel noch bestätigen
- [ ] ⚠ **Essen/Trinken-Makro** (ForeverHelpers): Makro, das automatisch das beste Essen bzw. Getränk aus den Taschen
      nimmt
