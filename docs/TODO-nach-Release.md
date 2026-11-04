# To-do nach dem Release

Aufgaben für die Zeit nach dem Release. Erledigtes abhaken (`[x]`) oder entfernen.

**⚠ = kann Funktionen oder Darstellung im Spiel verändern** – danach im Spiel prüfen. Ohne Zeichen: keine
Auswirkung im Spiel.

## Geplant

- [ ] ⚠ **Restliche Fenster überarbeiten** (ForeverSkin, Darstellung) – noch offen:
  - Große Fenster: Soziales nur noch „Freunde von Freunden“, eigenes Schlachtzug-Fenster (RaidParentFrame) und
    Raid-Info; Transmogrifizierer samt „Set bearbeiten“, Bearbeitungsmodus, Layout-Dialoge des
    Abklingzeiten-Managers (Neu/Umbenennen/Import), Gildenränge und Gilden-Unterfenster (Gildenlog, News-Filter,
    Gildeninfo-Text, Avatar-Auswahl), Auktionshaus, Kalender, PvP-Punktetafel und -Ergebnis
  - Kleine Fenster: Buch-/Brieftexte, Gildenurkunde/-gründung/-einladung/-umbenennung, Rollenabfrage,
    Gruppeneinladung, PvP-Bereitschaft, Farbauswahl, Quest-Details-Popup, Modellvorschau, Auswahlfenster,
    Beuteverlauf, Währung übertragen, Spieler melden, Schnelltastenbelegung, Uhr, Sprechkopf, Sockeln (falls vorhanden)
  - Abgleich im Spiel: `/fskin fenster` (listet alle großen Fenster, umgestaltet `+` oder nicht `-`)
- [ ] ⚠ **Questlog im Dungeonfenster** (ForeverQuests): die Quests des gewählten Dungeons direkt im Dungeonfenster als
      Questlog anzeigen
- [ ] ⚠ **Alle Addons über `/f move` verschieben** (alle Forever-Addons): ein gemeinsamer Verschiebe-Modus statt der
      einzelnen `move`-Befehle; Rechtsklick auf einen Rahmen öffnet direkt die passende Seite im Einstellungsmenü
- [ ] ⚠ **Eigenen Bearbeitungsmodus bei Kampfbeginn beenden** (ForeverCore/alle Addons): offener Verschiebe-Modus
      schließt sich automatisch, sobald der Kampf beginnt
- [ ] ⚠ **ForeverFrames:**
  - Option für einen Trennbalken zwischen Lebens- und Ressourcenleiste
  - Mana- und Energie-Regeneration anzeigbar machen
  - Mana zusätzlich in % anzeigbar
- [ ] ⚠ **ForeverCast:** Länge der Sofortzauber-Punkte (Instant-Dots) einstellbar machen – Standardwert bleibt wie er ist
- [ ] ⚠ **ForeverBars:** neue Zauberränge standardmäßig **nicht** mehr automatisch in die Leiste legen (als Option
      behalten, Standard aus)
- [ ] ⚠ **ForeverAlts:** Charakterübersicht (Ausrüstung wie im Charakterfenster) für andere Charaktere anzeigen
- [ ] ⚠ **Markierungen über Blizzards Schnell-Ping-Menü:** Weltmarkierungen mit dem Ping-Rad verbinden; Zielmarkierungen
      (Totenkopf, Kreuz …) per Mouseover über Gegner ebenfalls über das Ping-Rad setzen (Addon klären, z. B. ForeverHelpers)
- [ ] ⚠ **Essen/Trinken-Makro** (ForeverHelpers): Makro, das automatisch das beste Essen bzw. Getränk aus den Taschen
      nimmt
- [ ] ⚠ **ForeverBags:** Taschen nach Kategorien filterbar machen
- [ ] ⚠ **Aufschlüsselung der Werte** (Charakterfenster/Tooltip): je Klasse/Spezialisierung/Talenten zeigen, was ein
      Punkt bringt (z. B. 1 Angriffskraft = …, 1 Stärke = …)
- [ ] ⚠ **ForeverPlates:** Bedrohungs-/Aggro-Anzeige überarbeiten
- [ ] ⚠ **Erster Start:** kurzer Einrichtungsassistent im Hub, der die wichtigsten Schalter einmal abfragt (neues
      Fenster beim ersten Login)
- [ ] **Kampf-Sicherheit prüfen:** ForeverSkin hängt sich an viele Blizzard-Fenster – gezielt durchsehen, ob im Kampf
      „Aktion blockiert“ entstehen kann (geschützte Knöpfe, Verschieben von Fenstern mit geschützten Teilen). Die
      Prüfung selbst ändert nichts; ⚠ gefundene Fehler zu beheben schon

## Verschoben (erst testen können, wenn der Server läuft)

- [ ] ⚠ **ForeverSkin, Menüs:** Untermenüs gezielter finden statt fünfmal je Sekunde alle Rahmen zu durchsuchen (nur
      bei offenem Menü, kann aber kurz ruckeln) – Darstellung der Untermenüs kann sich ändern; danach
      Rechtsklick-Menü mit Untermenü prüfen
- [ ] **Messbefehl** `/forever leistung`: Leistung je Forever-Addon im Chat (über `C_AddOnProfiler`, falls der
      Forever-Client es anbietet) – liest nur, ändert nichts
- [ ] ⚠ **Doppelten Code zusammenlegen** (ForeverSkin): Anker verschieben, Grafiken dauerhaft unsichtbar halten,
      Plus/Minus erkennen, flache Suchleiste, Schlüssel finden – gemeinsam in `Core.lua`; `Character.lua` aufteilen.
      Soll nichts ändern, betrifft aber viele Fenster – alle umgestalteten Fenster danach durchsehen
- [ ] ⚠ **`ForeverHubDB` nur noch in ForeverCore:** steht heute zusätzlich in der .toc von 13 Addons (Übergang seit
      0.41b) – das Spiel speichert dieselben Hub-Einstellungen 14-mal, und die Kopie eines länger ausgeschalteten
      Addons kann beim Einloggen neuere Einstellungen (Sprache, Fenstergrößen …) überschreiben. Eintrag bei allen
      außer ForeverCore streichen; Lua-Code bleibt gleich (alle nutzen dieselbe Tabelle). Kein Datenumzug nötig, da
      ForeverCore sie seit 0.41b selbst speichert – nur wer direkt von vor 0.41b springt, verliert Hub-Einstellungen.
      Betrifft Patzlingers Addons (vorher absprechen); danach Neustart, Test: Hub-Einstellung ändern, aus-/einloggen
- [ ] ⚠ **Überstand am Bildschirmrand:** wo unsere Fläche über Blizzards Fenster hinausreicht (Charakterfenster oben,
      Handel), hält das Spiel nur Blizzards Fenster im Bildschirm – ggf. selbst nachziehen (Lage der Fenster)
