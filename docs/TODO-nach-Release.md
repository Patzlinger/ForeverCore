# To-do nach dem Release

Aufgaben für die Zeit nach dem Release. Erledigtes abhaken (`[x]`) oder entfernen.

**⚠ = kann Funktionen oder Darstellung im Spiel verändern** – danach im Spiel prüfen. Ohne Zeichen: keine
Auswirkung im Spiel.

## Geplant

- [ ] ⚠ **Restliche Fenster überarbeiten** (ForeverSkin, Darstellung) – noch offen:
  - Im Spiel noch prüfen (Entwurf fertig, nur bei echtem Anlass): Bereitschaftscheck, Gildeneinladung, Rollenabfrage, Beute-Meldung
    ("Ihr habt erhalten"), PvP-Punktetafel und -Ergebnis, Todesursache, Rollenabfrage fürs Schlachtfeld und weitere
    PvP-Hinweise (PVPRoleCheckPopup, PVPReadyPopup, PVPFramePopup), Battle.net-Einladung, GM-Ticket-Hinweis
  - Entwurf, gleich prüfbar: Stapel teilen (Shift-Klick auf Stapel), Gold-Betrag (Klick auf Gold beim Handel),
    Klickbelegung samt Info-Fenster
  - Abgleich im Spiel: `/fskin fenster` (listet alle großen Fenster, umgestaltet `+` oder nicht `-`)
- [ ] ⚠ **Markierungen über Blizzards Schnell-Ping-Menü:** Weltmarkierungen mit dem Ping-Rad verbinden; Zielmarkierungen
      (Totenkopf, Kreuz …) per Mouseover über Gegner ebenfalls über das Ping-Rad setzen (Addon klären, z. B. ForeverHelpers)
- [ ] ⚠ **Timer für zeitbegrenzte Quests** (ForeverQuests, Tracker): Restzeit anzeigen, wenn auf der Quest ein Timer liegt
      oder der Questgegenstand nur begrenzt haltbar ist (Gegenstand mit Ablaufzeit); z. B. `C_QuestLog.GetTimeAllowed`/
      Gegenstands-Tooltip auslesen, im Tracker hinter dem Questnamen, bei wenig Zeit farbig
- [ ] ⚠ **Essen/Trinken-Makro** (ForeverHelpers): Makro, das automatisch das beste Essen bzw. Getränk aus den Taschen
      nimmt
