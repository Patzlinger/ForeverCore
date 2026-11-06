# To-do nach dem Release

Aufgaben für die Zeit nach dem Release. Erledigtes abhaken (`[x]`) oder entfernen.

**⚠ = kann Funktionen oder Darstellung im Spiel verändern** – danach im Spiel prüfen. Ohne Zeichen: keine
Auswirkung im Spiel.

## Geplant

- [ ] ⚠ **Restliche Fenster überarbeiten** (ForeverSkin, Darstellung) – noch offen:
  - Große Fenster: PvP-Punktetafel und -Ergebnis
  - Kleine Fenster: Bereitschaftscheck (ReadyCheckFrame),
    Set bearbeiten beim Transmogrifizieren (WardrobeCustomSetEditFrame), weitere
    PvP-Abfragen (PVPReadyPopup, PVPRoleCheckPopup, PVPFramePopup)
  - Im Spiel noch prüfen (Entwurf fertig, nur bei echtem Anlass): Gildeneinladung, Rollenabfrage, PvP-Bereitschaft,
    Beute-Meldung ("Ihr habt erhalten")
  - Abgleich im Spiel: `/fskin fenster` (listet alle großen Fenster, umgestaltet `+` oder nicht `-`)
- [ ] ⚠ **Markierungen über Blizzards Schnell-Ping-Menü:** Weltmarkierungen mit dem Ping-Rad verbinden; Zielmarkierungen
      (Totenkopf, Kreuz …) per Mouseover über Gegner ebenfalls über das Ping-Rad setzen (Addon klären, z. B. ForeverHelpers)
- [ ] ⚠ **Timer für zeitbegrenzte Quests** (ForeverQuests, Tracker): Restzeit anzeigen, wenn auf der Quest ein Timer liegt
      oder der Questgegenstand nur begrenzt haltbar ist (Gegenstand mit Ablaufzeit); z. B. `C_QuestLog.GetTimeAllowed`/
      Gegenstands-Tooltip auslesen, im Tracker hinter dem Questnamen, bei wenig Zeit farbig
- [ ] ⚠ **Essen/Trinken-Makro** (ForeverHelpers): Makro, das automatisch das beste Essen bzw. Getränk aus den Taschen
      nimmt
- [ ] ⚠ **Integration für Leatrix Plus bauen** (Umfang noch klären): bisher fragt der Hub nur bei doppelten Funktionen,
      welches Addon laufen soll („Andere Addons …“)
