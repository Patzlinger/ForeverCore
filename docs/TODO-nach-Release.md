# To-do nach dem Release

Aufgaben für die Zeit nach dem Release. Erledigtes abhaken (`[x]`) oder entfernen.

**⚠ = kann Funktionen oder Darstellung im Spiel verändern** – danach im Spiel prüfen. Ohne Zeichen: keine
Auswirkung im Spiel.

## Geplant

- [ ] ⚠ **Markierungen über Blizzards Schnell-Ping-Menü:** Weltmarkierungen mit dem Ping-Rad verbinden; Zielmarkierungen
      (Totenkopf, Kreuz …) per Mouseover über Gegner ebenfalls über das Ping-Rad setzen (Addon klären, z. B. ForeverHelpers).
      Die frühere Markierungsleiste ist seit 2026-11-07 die Gruppen- & Reiseleiste; Markierungs-Tasten laufen bis dahin
      über unsichtbare Knöpfe weiter (ForeverBars, Bars.lua GetMarkButtons)
- [ ] ⚠ **Timer für zeitbegrenzte Quests** (ForeverQuests, Tracker): Restzeit anzeigen, wenn auf der Quest ein Timer liegt
      oder der Questgegenstand nur begrenzt haltbar ist (Gegenstand mit Ablaufzeit); z. B. `C_QuestLog.GetTimeAllowed`/
      Gegenstands-Tooltip auslesen, im Tracker hinter dem Questnamen, bei wenig Zeit farbig
- [ ] ⚠ **Essen/Trinken-Makro** (ForeverHelpers): Makro, das automatisch das beste Essen bzw. Getränk aus den Taschen
      nimmt
