# Design, Sprache und Verschieben

Ausgelagert aus CLAUDE.md (alte Abschnitte 7, 8, 10). **Lesen, bevor ein Fenster, eine Anzeige oder ein verschiebbarer
Rahmen gebaut oder umgebaut wird, und bei jedem neuen sichtbaren Text.** Maße der Einstellungsfenster: **Menues.md**.
Umgestaltete Blizzard-Fenster (ForeverSkin): **Fenster-Stil.md**.

## 7. Design (verbindlich für alle Fenster)
Vorbild ist der flache Stil aus ForeverQuests; `ForeverHub.UI` und `Style.lua` (ForeverQuests/ForeverBars) setzen ihn
identisch um. Neue Oberflächen nutzen eine dieser beiden – keine dritten Stile.
- **Einstellungen = Seite im zentralen Fenster** (Hub v45, „3c“ in ForeverHub.lua): `UI.SettingsPanel(name, titel, w, h,
  { key = Addonname, group = UI.SETTINGS_GROUPS.frames|bars|nav|comfort|helpers, label, kind = nil|"menu" })` statt
  `UI.Window`/`Style.CreateWindow`/`UI.MenuWindow`. Feste Fenstergröße 176 + 720 × 832 (größtes Einzelfenster
  ForeverBars). Die Seite bringt ihre alte Titelleiste mit (26 bzw. 40 hoch) und verhält sich wie das alte Fenster
  (`:Show/:Hide/:SetShown/:IsShown` öffnen bzw. schließen das große Fenster auf dieser Seite). Wer sein Fenster erst
  beim ersten Öffnen baut, meldet beim Laden `UI.RegisterSettingsLink({ key, group, label, open })` an. Inhalt 1:1
  (siehe Menues.md, Lehren).
- **Eine Quelle für Farben:** `Style.COLOR` in ForeverBars/ForeverQuests IST die Tabelle `UI.COLOR` aus ForeverCore
  (seit 2026-10-18; das Dungeonfenster ergänzt nur eigene Kartenfarben per Metatabelle). Farbtöne nur im Hub ändern,
  die Tabelle nie aus einem Addon heraus verändern. Fenster, Positionen und Menüs der Addons bleiben eigenständig.
- Farben (`UI.COLOR` = `ns.Style.COLOR`):
  | Name | RGBA | Verwendung |
  |---|---|---|
  | background | 0.07 0.07 0.09 0.97 | Fenster |
  | header | 0.11 0.11 0.14 1 | Titelleiste, aktiver Reiter |
  | panel | 0.10 0.10 0.12 0.95 | Abschnitts-Kästen, Listen |
  | border | 0.22 0.22 0.26 1 | 1-px-Ränder |
  | input | 0.06 0.06 0.08 1 | Eingabefelder, Häkchen-Kästchen |
  | button / buttonHover | 0.16 0.16 0.20 / 0.22 0.22 0.27 | Knöpfe |
  | accent (Gold) | 1 0.82 0 | **einzige Akzentfarbe**: Hover-Rand, Häkchen, Regler, Titellinie, Überschriften |
- Fenster: flach und dunkel, 1-px-Rand, Titelleiste mit Logo + Titel + Schließen-Kreuz und goldener Linie unten,
  verschiebbar an der Titelleiste, mit Escape schließbar (`UISpecialFrames`).
- **Fenster-Stapel**: Jedes Fenster meldet sich mit `UI.RegisterWindow(f)` an (`UI.Window`/`UI.MenuWindow` tun das
  selbst, `Style.CreateWindow` in ForeverQuests/ForeverBars ebenfalls). Das zuletzt geöffnete oder angeklickte
  Forever-Fenster liegt dann über allen anderen – addonübergreifend, ohne dass sich Bedienelemente verzahnen. Eigene
  Fenster nicht per `SetFrameLevel` festnageln (sonst greift der Stapel nicht).
- **Fenstergröße mit der Maus**: jedes benannte `UI.Window` bekommt automatisch einen Griff unten rechts (Skalieren
  60–160 %, Rechtsklick = Standard, gespeichert in `ForeverHubDB.windows`). Fenster, deren Inhalt mitwachsen kann
  (z. B. ForeverSpellbook), nutzen `UI.MakeResizable(f, { mode = "size", minW, minH, maxW, maxH })` und ordnen ihren
  Inhalt bei `OnSizeChanged` neu an. Die untere rechte Ecke (ca. 16 px) frei lassen.
- Platz für Deutsch einplanen: deutsche Texte sind oft 30–40 % länger als englische – Spalten und Beschriftungen mit
  der deutschen Fassung prüfen, nicht mit der englischen.
- Einstellungen in Abschnitte gliedern: goldene Überschrift + dezenter Kasten darum; Reiter, wenn es viele sind.
- Bedienelemente: flache Knöpfe (Hover = goldener Rand), Häkchen als kleines Kästchen mit goldener Füllung (Klick auf
  den Text zählt mit), Regler als dünne Leiste mit goldenem Griff, Auswahllisten als flache Liste mit Pfeil.
- Tooltips kurz; eigene Tooltips im gleichen Stil (dunkel, goldene Linie oben).
- Minimap-Knopf: runder Standard-Look (31 px, Tracking-Rand), ziehbar um die Minimap.
- Anzeigen im Spiel (Leisten, Balken, Symbole): dezent, eher klein, halbtransparente dunkle Flächen, keine
  Blizzard-Schnörkel.
- Chat-Ausgabe: `Addonname: Text`, Name in Gold `|cffffcc00` (wie `UI.Chat`), sparsam (nur Bestätigungen und
  Fehlerhinweise).
- Schrift: Standardschriften des Clients (`STANDARD_TEXT_FONT`, `GameFont*`); Zeichen siehe Technical-Pitfalls.md,
  Abschnitt 1 („→“ nicht verwenden).

## 8. Sprache
- Jede sichtbare Zeichenkette zweisprachig: **Deutsch und Englisch**.
- **Eine Sprachwahl für alle** (im Hub-Fenster `/forever`, gespeichert in `ForeverHubDB.language`): Deutsch gibt es nur
  auf einem deutschen Client, dort kann man auf Englisch umstellen; sonst immer Englisch. Abfrage: `UI.GetLanguage()`
  → `"deDE"`/`"enUS"`. Wirkt nach `/reload` (ForeverQuests wechselt sofort).
  - Für die Anzeigesprache fragt kein Addon `GetLocale()` selbst ab, sondern den Hub (`UI.T`, `UI.GetLanguage`);
    `GetLocale()` nur dort, wo es um die Sprache der Spieldaten geht (z. B. Questnamen vergleichen).
  - Eigene Sprachauswahl in einem Addon-Menü (wie bei ForeverQuests) muss in `ForeverHubDB.language` schreiben.
- Zwei erlaubte Wege für Texte: `T("Deutsch", "English")` aus dem Hub (Patzlingers Addons) oder `Locales.lua` mit
  Schlüsseln und `ns.L("KEY")` (flowfys Addons), das die Sprache über `UI.GetLanguage()` bestimmt. Innerhalb eines
  Addons nur einen Weg nutzen.
- Kommentare im Code auf Deutsch, kurz, erklären das *Warum*; Umlaute in Kommentaren sind erlaubt.

## 10. Verschieben und Positionen
- Alle Rahmen starten **gesperrt**; entsperren per Menü, Rechtsklick auf den Minimap-Knopf oder `/fmove`.
- Entsperrt: sichtbarer Griff mit Namen, Ziehen mit Raster/Einrasten, **Shift = frei schieben**; X/Y-Felder im Menü.
- Positionen relativ zu einem festen Bezugspunkt (Bildschirmmitte oder -rand) speichern und auf ganze Pixel runden.
- **Einrasten gilt für ALLE verschiebbaren Forever-Fenster** (seit Hub v36) und über Addons hinweg:
  - Jeder Rahmen, an dem andere einrasten sollen, meldet sich mit `UI.AddMover(frame)` an (nur sichtbare zählen).
  - Beim Ziehen `UI.BeginDrag(frame, { snap, grid, edges })`, am Ende `local dx, dy = UI.EndDrag()` und die Position um
    (dx, dy) verschieben (Muster: ForeverCast, ForeverBuffs, ForeverLoot). Rahmen, die sich beim Ziehen selbst
    nachführen (ForeverBars), holen den Versatz live mit `UI.SnapOffset()` (Halter vorher auf die Mausposition setzen).
  - Umschalt beim Ziehen = nicht einrasten; globaler Schalter: Übersicht „Einrasten beim Verschieben“ bzw.
    `/fmove snap` (`ForeverHubDB.noSnap`, `UI.SnapEnabled()`); zusätzlich hat ein Addon ggf. eine eigene Option `snap`.
  - Neue verschiebbare Fenster **müssen** das einbauen; Minimap und Hauptchat (Bearbeitungsmodus) sind nur Ziele.
