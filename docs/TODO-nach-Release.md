# To-do nach dem Release

Aufgaben für die Zeit nach dem Release. Erledigtes abhaken (`[x]`) oder entfernen.

**⚠ = kann Funktionen oder Darstellung im Spiel verändern** – danach im Spiel prüfen. Ohne Zeichen: keine
Auswirkung im Spiel.

## Geplant

- [ ] ⚠ **Markierungen über Blizzards Schnell-Ping-Menü:** Weltmarkierungen mit dem Ping-Rad verbinden; Zielmarkierungen
      (Totenkopf, Kreuz …) per Mouseover über Gegner ebenfalls über das Ping-Rad setzen (Addon klären, z. B. ForeverHelpers).
      Die frühere Markierungsleiste ist seit 2026-11-07 die Gruppenleiste; Markierungs-Tasten laufen bis dahin
      über unsichtbare Knöpfe weiter (ForeverBars, Bars.lua GetMarkButtons).
      **Prototyp seit 2026-11-10:** `ForeverHelpers/Marks.lua`, Befehl `/fmarks` (eigenes Rad, kein Blizzard-Ping-Rad –
      das lässt sich nicht erweitern); Grenzen: nur außerhalb des Kampfs, keine Einstellungsseite im Hub
- [ ] ⚠ **Ablaufzeit von Questgegenständen** (ForeverQuests, Tracker): Restzeit auch anzeigen, wenn der Questgegenstand
      nur begrenzt haltbar ist (Gegenstand-Tooltip auslesen). Quests mit eigener Frist zeigen ihre Restzeit seit
      2026-11-07 (Tracker.lua GetQuestTimerEnd) – im Spiel noch bestätigen
- [ ] ⚠ **Essen/Trinken-Makro** (ForeverHelpers): Makro, das automatisch das beste Essen bzw. Getränk aus den Taschen
      nimmt
- [ ] ⚠ **Suche nach Gruppe: nach Rolle filtern** (Tank, Heiler, Schaden): in der Gruppensuche die Ergebnisse nach der
      gesuchten Rolle filtern können (Addon noch klären)
- [ ] ⚠ **Sprachauswahl der Gruppensuche** (ForeverHelpers/Languages.lua, seit 2026-11-13): Knopf „Sprachen: …“ unter
      „Durchsuchen“ mit Häkchen je Sprache (Blizzards Sprachfilter, C_LFGList.SaveLanguageSearchFilter). Im Spiel
      noch nicht bestätigt; bis dahin in `release/exclude-from-release.txt`, danach dort streichen + Changelog-Eintrag
