# To-do nach dem Release

Aufgaben für die Zeit nach dem Release. Erledigtes abhaken (`[x]`) oder entfernen.

**⚠ = kann Funktionen oder Darstellung im Spiel verändern** – danach im Spiel prüfen. Ohne Zeichen: keine
Auswirkung im Spiel.

## Geplant

- [ ] ⚠ **Restliche Fenster überarbeiten** (ForeverSkin, Darstellung) – noch offen:
  - Große Fenster: Soziales nur noch „Freunde von Freunden“, eigenes Schlachtzug-Fenster (RaidParentFrame) und
    Raid-Info; Transmogrifizierer samt „Set bearbeiten“, Gildenränge und Gilden-Unterfenster (Gildenlog, News-Filter,
    Gildeninfo-Text, Avatar-Auswahl), Auktionshaus-Feinschliff (Geld-Eingaben, Gegenstands-Platz beim Verkaufen,
    Taschen von ForeverBags andocken), PvP-Punktetafel und -Ergebnis
  - Kleine Fenster: Buch-/Brieftexte, Gildenurkunde/-gründung/-einladung/-umbenennung, Rollenabfrage,
    Gruppeneinladung, PvP-Bereitschaft, Farbauswahl, Quest-Details-Popup, Modellvorschau, Auswahlfenster,
    Beuteverlauf, Währung übertragen, Spieler melden, Schnelltastenbelegung, Sprechkopf, Sockeln (falls vorhanden)
  - Abgleich im Spiel: `/fskin fenster` (listet alle großen Fenster, umgestaltet `+` oder nicht `-`)
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

- [ ] ⚠ **Doppelten Code zusammenlegen** (ForeverSkin), Rest: Grafiken dauerhaft unsichtbar halten und Plus/Minus
      erkennen (je Fenster leicht verschieden gebaut) gemeinsam in `Core.lua`; `Character.lua` aufteilen. Erledigt
      (2026-11-05): flache Suchleiste (`ns.SkinSearchBox`), Anker setzen (`ns.Anchor`), Schlüssel finden (`ns.KeyOf`).
      Soll nichts ändern, betrifft aber viele Fenster – alle umgestalteten Fenster danach durchsehen
