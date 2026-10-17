# Forever Core – gemeinsames Grundgerüst

Dieses Dokument gilt für alle, die an diesem Repository arbeiten (Menschen und Claude). Es beschreibt
Philosophie, Regeln, Design und Abläufe. Wenn etwas hier nicht steht: am bestehenden Code orientieren und nachfragen.
Änderungen an diesen Regeln immer hier eintragen (nicht nur lokal), damit alle denselben Stand haben.

## 1. Projekt und Philosophie
- **Forever Core**: schlanke, modulare Addons für *World of Warcraft: Forever*
- Leitsatz: **"Less clutter. More control. Just the essentials."**
  - Jedes Addon löst eine Aufgabe gut, funktioniert allein und passt sich optisch nahtlos in die Suite ein
  - Unaufdringlich: wenig Bildschirmfläche, kein Blinken, keine Spielereien; Infos bei Bedarf (Mouseover/Tooltip)
  - Sinnvolle Standardwerte: ein Addon muss ohne jede Einstellung brauchbar sein
  - Ersetzen statt überlagern: wenn ein Addon einen Blizzard-Teil ersetzt, wird der Blizzard-Teil taint-frei ausgeblendet
- Zielgruppe: Spieler, keine Programmierer – Texte kurz, klar, ohne Fachbegriffe
- Mitarbeiter sprechen teils kein Lua: **Änderungen immer kurz auf Deutsch erklären** (was, warum, was testen)

## 2. Team und Zuständigkeiten
| Addon | Verantwortlich | Status |
|---|---|---|
| ForeverFrames, ForeverUnits, ForeverCast, ForeverLoot, ForeverXP, ForeverBuffs, ForeverVendor | Patzlinger | im Release |
| ForeverSpellbook | Patzlinger | im Release (seit 0.32b) |
| ForeverChat | Patzlinger | im Release (seit 0.32b) |
| ForeverMinimap | Patzlinger | Prototyp (seit 2026-10-17) |
| ForeverCore (Hauptaddon: `ForeverHub.lua` = Hub und Stil-Bibliothek; Abhängigkeit aller Addons) | gemeinsam | im Release (seit 0.41b) |
| ForeverQuests | flowfy | im Repository, noch nicht im Release |
| ForeverBars | flowfy | im Repository, noch nicht im Release |
| `tools/`, `release/` | gemeinsam | – |

- Alle Addons gehören zum gemeinsamen Paket; beide dürfen jedes Addon bearbeiten (Zusammenarbeit auf Augenhöhe).
  Größere funktionale Änderungen am Addon des anderen vorher kurz absprechen und im Commit klar benennen.
- Wer ein Addon verantwortet, entscheidet über dessen Funktionen und Lizenz.
- **Eine Version für alle**: seit 0.41b tragen alle Forever-Addons (auch ForeverQuests/ForeverBars und ForeverCore)
  dieselbe Suite-Version (`## Version: 0.41b`); Versionssprünge gemeinsam in allen .toc
- Entscheidungen, die alle Addons betreffen (Hub, Design, Regeln hier), gemeinsam treffen.

## 3. Zielclient und API
- WoW: Forever, `## Interface: 16001`; Basis ist die **Mainline/Retail-API (Stand 12.1.5)**, NICHT die Classic-API
  - Neue Namensräume nutzen (`C_AddOns`, `C_Spell`, `C_SpellBook`, `C_Container`, `C_CVar` …), mit Rückfall auf alte Funktionen, wo sinnvoll
- Midnight-Restriktionen ("secret values" im Kampf): keine Rechnungen/Vergleiche mit gesperrten Werten,
  Werte nur direkt weiterreichen (z. B. an StatusBars, Aura-Container); **keine Rotationslogik**
  - Auch scheinbar harmlose Werte sind im Kampf gesperrt, z. B. `GetUnitSpeed("player")` (Fehler "attempt to compare
    a secret number value"). Lieber Ereignisse nutzen (Bewegung: `PLAYER_STARTED_MOVING`/`PLAYER_STOPPED_MOVING`)
    und in `OnUpdate`/Tickern nie gesperrte Werte vergleichen – dort entstehen sonst Fehler in jedem Bild
- SavedVariables funktionieren normal (wir gehen vom Live-Betrieb aus): Einstellungen werden gespeichert und beim
  Login geladen. Standardwerte trotzdem sinnvoll wählen (erster Start, neue Einstellungen nach einem Update)
- Forever-Namen haben Vor- und Nachnamen: Chat liefert evtl. "Vorname Nachname", die Gruppenliste nur den Vornamen –
  Namen abgleichen statt direkt vergleichen
- WoW-Schrift kennt "→" nicht (wird zum Kasten): in Anzeige-Texten "»" oder "–" verwenden; "≈ · – … —" funktionieren
- Namensplaketten sind "restricted regions": GetCenter/GetPoint usw. darauf sind verboten (Fehler + taint); Namen lesen geht
- Anvisieren (TargetUnit, /target) und SetRaidTarget nur über sichere Knöpfe auf Tastendruck, nie automatisch
- Geschützte Rahmen (Aktionsknöpfe, Einheitenrahmen, sichere Knöpfe) nur außerhalb des Kampfes anlegen, verschieben,
  vergrößern oder belegen: vorher `InCombatLockdown()` prüfen, Änderungen sonst bis `PLAYER_REGEN_ENABLED` aufschieben
- Fehler suchen: BugSack/BugGrabber, Datei `WTF\Account\*\SavedVariables\!BugGrabber.lua`

## 4. Taint vermeiden (wichtig!)
- Blizzard-Rahmen **nie** mit `:Hide()`, `:SetParent()` oder `:SetScript()` verändern ("taint" blockiert sonst z. B.
  Raid-Symbole im Menü oder geschützte Aktionen). Stattdessen:
  - `UnregisterAllEvents()` + `RegisterStateDriver(frame, "visibility", "hide")`, oder
  - unsichtbar machen: `SetAlpha(0)` und mit `hooksecurefunc(frame, "SetAlpha", …)` gegen Zurücksetzen absichern
    (so macht es ForeverXP mit der XP-Leiste – Platz und Anordnung der Blizzard-Leisten bleiben dabei erhalten)
- Blizzard-Funktionen nur mit `hooksecurefunc` bzw. `frame:HookScript` erweitern, nie überschreiben
- Dokumentierte Ausnahmen (bewusst so, nicht "reparieren" ohne Absprache):
  - **ForeverBars** setzt Blizzards Aktionsknöpfe und Leisten per `SetParent` in eigene Halter – das ist für ein
    Leisten-Addon nötig (Bartender4 macht es genauso); nur außerhalb des Kampfes, Sichtbarkeit über State-Driver
  - **ForeverQuests** blendet den Blizzard-Questtracker mit `:Hide()` aus (außerhalb des Kampfes, mit OnShow-Hook,
    Wiederholung nach dem Kampf über `UI.AfterCombat`). `UI.HideBlizzard` passt hier NICHT: der Tracker enthält
    geschützte Questgegenstand-Knöpfe, die unsichtbar anklickbar blieben. Falls Taint-Meldungen auftauchen:
    `RegisterStateDriver(ObjectiveTrackerFrame, "visibility", "hide")` im Spiel testen
- Zwei Addons dürfen nicht denselben Blizzard-Teil "besitzen". Bekannte Berührungspunkte siehe Abschnitt 14.

## 5. Aufbau eines Addons
- Jedes Addon in eigenem Ordner im Repository-Wurzelverzeichnis, **.toc-Name = Ordnername**, Name `Forever<Name>`
- GUI in Lua bauen (`CreateFrame`, Retail-Templates), **kein XML** – einzige Ausnahme: `Bindings.xml` für Tastenkürzel
  (die verlangt WoW so)
- Pflicht in der .toc (Vorlage):
  ```
  ## Interface: 16001
  ## Title: ForeverName |cff8a8a8a(Beta)|r
  ## Notes: English description
  ## Notes-deDE: Deutsche Beschreibung
  ## IconTexture: Interface\AddOns\ForeverName\Media\ForeverCore
  ## Category: Forever Core
  ## Author: <Name>
  ## Version: 0.41b
  ## Dependencies: ForeverCore
  ## Group: ForeverCore
  ## SavedVariables: ForeverNameDB, ForeverHubDB

  ... eigene Dateien ...
  ```
  - `## Group: ForeverCore`: in Blizzards Addon-Liste eingerückt unter "Forever Core" (wie AtlasLoot); Blizzard setzt das
    nur bei gleichem Namensanfang automatisch, deshalb ausdrücklich eintragen
  - `## Dependencies: ForeverCore`: ForeverCore lädt garantiert vorher, `ForeverHub.UI` steht ab der ersten Zeile bereit.
    **Keine eigene Kopie von `ForeverHub.lua`** mehr ins Addon legen
  - `ForeverHubDB` steht vorerst weiter in den SavedVariables jedes Addons (Übergang: so übernehmen Spieler ihre
    Hub-Einstellungen aus den alten Speicherständen; kann später auf ForeverCore allein reduziert werden)
  - Der Titel trägt den dezenten Beta-Hinweis (nur in der Addon-Liste sichtbar)
  - `Media\ForeverCore.tga` (Logo) liegt in jedem Addon (Kopie z. B. aus ForeverXP)
  - Release-Addons zusätzlich: `## X-License: MIT`, `## X-Curse-Project-ID: 1743753`, `LICENSE.txt`
- Datei-Aufteilung frei; bewährt: `Core.lua` (Defaults, Start, Chatbefehl), `Locales.lua`, `Options.lua`, Funktionsdateien
- Neues Addon zusätzlich: in `ForeverCore/ForeverHub.lua` in die Liste `KNOWN` eintragen (Name + Minimap-Knopf) und
  einmal `tools/link-addons.ps1` ausführen

## 6. ForeverHub (gemeinsame Bibliothek)
- Der Hub liegt **nur einmal**: `ForeverCore/ForeverHub.lua` im Hauptaddon ForeverCore (seit 0.41b; vorher Kopie in
  jedem Addon – Stand davor: Git-Markierung `snapshot-vor-core-abhaengigkeit`). Bei Änderungen `VERSION` erhöhen
- Gemeinsames (Stil, Sprache, Hilfsfunktionen, Begrüßung, Platzhalter …) gehört in den Hub, nicht in einzelne Addons
- Erweiterungen müssen abwärtskompatibel sein (andere Addons rufen die Funktionen auf); Funktionen bei Bedarf mit
  `if UI.Funktion then … end` aufrufen
- Was der Hub kann:
  1. **Stil-Bibliothek** `ForeverHub.UI` (Zugriff: `local UI = ForeverHub.UI`):
     `T(de, en)`, `Chat(addon, text)`, `Window(name, title, w, h)`, `Header(parent, x, y, text, width)` (mit
     automatischem Abschnitts-Kasten), `Hint`, `Text(parent, "label"|"field", text)`, `Button(parent, text, w, onClick)`,
     `AddArrow`, `Check(parent, x, y, label, onClick)`, `Slider(...)`, `StyleSlider`, `EditBox`, `Number` (Zahlenfeld mit –/+),
     `ShowMenu`/`HideMenu`/`ChoiceMenu` (flache Auswahllisten), `MinimapButton(o)`, `Hud`, `Box`, `SetFlat`,
     `Grid`, `AddMover`, `BeginDrag`/`EndDrag` (Raster + Einrasten), `Round`, `CenterOffset`, `COLOR`, `LOGO`, `NAME`
  2. **Sammelknopf**: ab zwei Forever-Addons werden deren Minimap-Knöpfe ausgeblendet und in einer Liste am
     Forever-Core-Knopf gesammelt (Klick wird an den Original-Knopf weitergereicht)
  3. **Hub-Fenster** `/forever` (`/fhub`, Ebene `HIGH`, bleibt beim Öffnen eines Addons im Hintergrund offen):
     alle installierten Forever-Addons mit Chatbefehl und "Öffnen"-Knopf ins jeweilige Menü,
     "Alle verschieben", Minimap-Knopf ein/aus, **Sprache für alle Forever-Addons**; `/forever reset` holt Knöpfe zurück.
     **Addons ein-/ausschalten** (ab v26): Häkchen je Addon, "Alle an/aus", "nur dieser Charakter"
     (`ForeverHubDB.perCharacter`, sonst alle Charaktere) über `C_AddOns.EnableAddOn/DisableAddOn` + `SaveAddOns`;
     wirkt erst nach "Neu laden" (kein Nachladen zur Laufzeit – Rahmen müssen beim Laden entstehen, siehe Abschnitt 14).
     **Begrüßung**: beim allerersten Start öffnet sich das Fenster einmal (`ForeverHubDB.welcomeDone`, accountweit;
     wird sofort beim Anzeigen gesetzt, damit es nie wieder aufpoppt). ForeverCore selbst steht nicht in `KNOWN`
     (ohne ForeverCore lädt kein Forever-Addon); Hub, Optionsmenü und Addon-Menü-Eintrag bleiben, auch wenn alle anderen aus sind
  4. **Gemeinsamer Verschiebe-Modus** `/fmove`: entsperrt/sperrt alle angemeldeten Addons auf einmal
  5. **Blizzard-Optionsmenü** (Esc » Optionen » Reiter "AddOns"): Eintrag "Forever Core" mit Übersicht und je
     Forever-Addon eine Unterseite mit "Einstellungen öffnen" (öffnet das eigene Fenster, Optionsmenü schließt sich).
     Automatisch für jedes Addon aus `KNOWN`, dessen Minimap-Knopf existiert; `/forever options` springt dorthin.
     Die eigentlichen Einstellungen bleiben in den eigenen Fenstern (keine zweite Einstellungs-Oberfläche bauen)
  6. **Addon-Menü an der Minimap**: ein einziger Eintrag "Forever Core" (Links: Hub-Fenster, Rechts: alle verschieben)
  7. **Gemeinsame Helfer** – statt eigener Kopien in jedem Addon benutzen:
     - `UI.ReportError(addon, stelle, fehler)` / `UI.Safe(addon, stelle, fn)`: Fehler einmal pro Stelle im Chat, immer an
       BugSack; `UI.ErrorCount(addon)`
     - `UI.AfterCombat("Addon:schlüssel", fn, addon)`: sofort oder nach dem Kampf (gleicher Schlüssel = letzter Auftrag)
     - `UI.HideBlizzard(frame, { when, children, noMouse })` / `UI.ShowBlizzard(frame)`: Blizzard-Teil taint-frei
       unsichtbar halten (Alpha 0 + Absicherung). Nicht für Rahmen mit geschützten, anklickbaren Knöpfen
       (z. B. Questgegenstände im Questtracker) – die blieben unsichtbar anklickbar
- **Übergang von alten Kopien**: Addons bis 0.32b brachten eine eigene Hub-Kopie mit. Hat ein Spieler noch so ein
  altes Addon neben dem neuen ForeverCore, übernimmt trotzdem die neueste Version (Versionsprüfung am Dateianfang,
  gemeinsamer Zustand `ForeverHub.shared`, Umleitung älterer UI-Tabellen). Neuer gemeinsamer Zustand gehört deshalb
  weiter in `SHARED`; diese Übergangs-Technik kann entfallen, wenn keine 0.32b-Stände mehr im Umlauf sind
- Damit ein Addon voll eingebunden ist:
  - Minimap-Knopf **immer über `UI.MinimapButton({...})`** bauen, globaler Name `Forever<Name>MinimapButton`,
    **Linksklick öffnet das Menü**, Rechtsklick frei (meist: entsperren/sperren bzw. ein-/ausblenden); in `KNOWN`
    eintragen (Name, Knopf, Chatbefehl `cmd`) – damit erscheint es in Sammelknopf, Hub-Fenster und Blizzard-Optionsmenü.
    Die Vorlage bringt Aussehen, Ziehen um die Minimap und den Tooltip-Hinweis "Ziehen" mit
  - für `/fmove`: `UI.RegisterMovable("ForeverName", isLocked, setLocked)` – `isLocked()` liefert true/false,
    `setLocked(locked)` sperrt bzw. entsperrt (inkl. Menü aktualisieren). Addons mit eigener Stil-Datei melden sich
    in einer kleinen `HubLink.lua` an (siehe ForeverQuests/ForeverBars)

## 7. Design (verbindlich für alle Fenster)
Vorbild ist der flache Stil aus ForeverQuests; `ForeverHub.UI` und `Style.lua` (ForeverQuests/ForeverBars) setzen
ihn identisch um. Neue Oberflächen nutzen eine dieser beiden – keine dritten Stile.
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
  verschiebbar an der Titelleiste, mit Escape schließbar (`UISpecialFrames`)
- **Fenster-Stapel**: Jedes Fenster meldet sich mit `UI.RegisterWindow(f)` an (`UI.Window`/`UI.MenuWindow` tun das
  selbst, `Style.CreateWindow` in ForeverQuests/ForeverBars ebenfalls). Das zuletzt geöffnete oder angeklickte
  Forever-Fenster liegt dann über allen anderen – addonübergreifend, ohne dass sich Bedienelemente verzahnen.
  Eigene Fenster nicht per `SetFrameLevel` festnageln (sonst greift der Stapel nicht)
- **Fenstergröße mit der Maus**: jedes benannte `UI.Window` bekommt automatisch einen Griff unten rechts
  (Skalieren 60–160 %, Rechtsklick = Standard, gespeichert in `ForeverHubDB.windows`). Fenster, deren Inhalt
  mitwachsen kann (z. B. ForeverSpellbook), nutzen `UI.MakeResizable(f, { mode = "size", minW, minH, maxW, maxH })`
  und ordnen ihren Inhalt bei `OnSizeChanged` neu an. Die untere rechte Ecke (ca. 16 px) frei lassen
- Platz für Deutsch einplanen: deutsche Texte sind oft 30–40 % länger als englische – Spalten und Beschriftungen
  mit der deutschen Fassung prüfen, nicht mit der englischen
- Einstellungen in Abschnitte gliedern: goldene Überschrift + dezenter Kasten darum; Reiter, wenn es viele sind
- Bedienelemente: flache Knöpfe (Hover = goldener Rand), Häkchen als kleines Kästchen mit goldener Füllung
  (Klick auf den Text zählt mit), Regler als dünne Leiste mit goldenem Griff, Auswahllisten als flache Liste mit Pfeil
- Tooltips kurz; eigene Tooltips im gleichen Stil (dunkel, goldene Linie oben)
- Minimap-Knopf: runder Standard-Look (31 px, Tracking-Rand), ziehbar um die Minimap
- Anzeigen im Spiel (Leisten, Balken, Symbole): dezent, eher klein, halbtransparente dunkle Flächen, keine Blizzard-Schnörkel
- Chat-Ausgabe: `Addonname: Text`, Name in Gold `|cffffcc00` (wie `UI.Chat`), sparsam (nur Bestätigungen und Fehlerhinweise)
- Schrift: Standardschriften des Clients (`STANDARD_TEXT_FONT`, `GameFont*`); Zeichen siehe Abschnitt 3

### 7.1 Menü-Aufbau im Detail (Maße aus dem ForeverQuests-Menü)
**Umsetzung im Hub (ab v23):** `UI.MenuWindow(name, titel, untertitel, w, h)`, `UI.MenuPanel(parent, titel)`,
`UI.MenuCheck(parent, x, y, text, get, set, tooltip)`, `UI.MenuSlider(parent, x, y, text, min, max, step, get, set)`,
`UI.MenuDropdown(parent, x, y, text, liste, get, set)`, `UI.MenuNumber(parent, x, y, text, get, set)`,
`UI.MenuButton(parent, text, w, h, onClick, tooltip)`, `UI.MenuSidebar(parent, x, y, bereiche, onSelect)`,
`UI.GetTooltip()`, Maße in `UI.MENU`. Alle Bedienelemente haben `:Refresh()` und werden beim Öffnen des Fensters
automatisch aktualisiert (`fenster:RefreshAll()`). Noch nutzt kein Menü diese Bausteine (ein Versuch mit ForeverVendor
wurde auf Wunsch zurückgenommen). Ergänzung: Der Schließen-Knopf der Fußleiste sitzt 16 px weiter innen, weil unten
rechts der Größen-Griff liegt.

Damit alle Einstellungsfenster gleich aussehen, gelten diese Maße. Quelle: `ForeverQuests/Options.lua` und
`ForeverQuests/Style.lua` (`ForeverBars/Style.lua` ist identisch). Alle Angaben in Pixeln, y nach unten negativ.

**Fenster** (`Style.CreateWindow` bzw. `UI.Window`)
- Größe nach Inhalt (ForeverQuests: 680 × 620), Mitte des Bildschirms, Ebene `DIALOG`, am Bildschirm festgehalten,
  Hintergrund `background`, 1-px-Rand `border`
- Titelleiste: 40 hoch, 1 px innerhalb des Rands, Farbe `header`, unten 1-px-Linie in Gold (Deckkraft 0.6);
  Titel `GameFontNormalLarge` (gold) 16 px vom linken Rand, senkrecht mittig; dahinter Untertitel (Addon-Name)
  `GameFontDisableSmall`, 10 px Abstand, 1 px tiefer; Schließen-Kreuz `UIPanelCloseButton` 6 px vom rechten Rand
- Nur die Titelleiste verschiebt das Fenster; Escape schließt es

**Felder (Abschnitte)** (`Style.CreatePanel(parent, titel)`)
- Fläche `panel`, 1-px-Rand `border`
- Überschrift `GameFontNormal` (gold) bei x 14 / y −12; darunter Trennlinie 1 px, Weiß mit Deckkraft 0.08,
  bei y −30 von x 12 bis 12 px vor dem rechten Rand
- Anordnung: 12 px Abstand zum Fensterrand und zwischen Feldern; erstes Feld bei y −52 (12 px unter der Titelleiste).
  ForeverQuests: zwei Spalten à 322 breit (12 + 322 + 12 + 322 + 12 = 680), darunter ein breites Feld über beide Spalten
- Inhalt beginnt bei x 14 / y −44 (erste Zeile unter der Trennlinie)

**Raster im Feld**
- Häkchen-Zeilen: 24 px Abstand
- Regler: 46 px pro Regler (Beschriftung + Leiste), in ForeverQuests 42–46
- Auswahlfelder: 28–30 px pro Zeile
- Hinweistext unter einem Element: `GameFontDisableSmall`, linksbündig, Breite = Feldbreite − 28

**Bedienelemente**
- Häkchen (`Style.CreateCheckbox`): Kästchen 16 × 16, Fläche `input`, 1-px-Rand; angehakt = goldene Fläche mit
  3 px Innenabstand. Beschriftung `GameFontHighlight` 8 px rechts daneben; die Beschriftung ist mit anklickbar.
  Hover: goldener Rand (Deckkraft 0.9)
- Regler (`Style.CreateSlider` + Beschriftung + Zahlenfeld): Beschriftung `GameFontHighlightSmall` in Grau
  (0.75 0.75 0.75), 18 px darunter die Leiste (Breite 230 in einer 322er-Spalte): Spur 4 px hoch (0.25 0.25 0.30),
  Anteil bis zum Griff Gold mit Deckkraft 0.5, Griff 8 × 16 Gold. Rechts daneben (12 px) ein Zahlenfeld 50 × 20,
  zentriert, nur Zahlen; Enter übernimmt (auf Grenzen begrenzt), Escape verwirft
- Auswahlfeld (`Style.CreateDropdown` + `Style.ShowMenu`): Beschriftung `GameFontHighlight` links, Knopf 136 px
  weiter rechts (`DROPDOWN_X` 150 − 14), 158 × 22; Text linksbündig (8 px Innenabstand), rechts ein grauer Pfeil
  (10 × 10, `ChatFrameExpandArrow`, gedreht). Die Liste öffnet 4 px unter dem Knopf linksbündig: Fläche `background`,
  Zeilen 22 hoch, Hover Weiß mit Deckkraft 0.06, gewählter Eintrag = goldenes Kästchen 12 × 12. Klick daneben,
  Escape oder ein zweiter Klick auf den Knopf schließen sie. Keine Blizzard-Dropdowns
- Knopf (`Style.CreateButton`): Fläche `button`, 1-px-Rand, Text `GameFontHighlightSmall` mittig; Hover = `buttonHover`
  und goldener Rand; Tooltip im eigenen Stil. Höhe 22 im Feld, 26 in der Fußleiste
- Eingabefeld (`Style.CreateEditBox`): Fläche `input`, 1-px-Rand, `GameFontHighlightSmall`, 6 px Innenabstand;
  mit Fokus goldener Rand. Platzhaltertext in `GameFontDisableSmall`, solange das Feld leer ist
- Tooltip (`Style.GetTooltip`): eigener GameTooltip, Fläche `background`, graue 1-px-Ränder, oben eine goldene Linie
  (Deckkraft 0.7), Blizzards verzierter Rand (`NineSlice`) ausgeblendet

**Fußleiste**
- Knöpfe 150 × 26, 12 px vom unteren Rand; links eine Aktion (z. B. „Zurücksetzen“), rechts immer „Schließen“;
  weitere Knöpfe (z. B. „Entsperren“) dazwischen

**Verhalten**
- Jede Änderung wirkt sofort; alle Bedienelemente haben `Refresh()` und werden beim Öffnen auf die aktuellen Werte gesetzt
- Beim Schließen: Entsperren beenden (falls das Menü es gestartet hat), offene Auswahlliste schließen
- Eigene Fenster eines Addons nicht übereinander offen lassen (ForeverQuests: Menü und Dungeon-Fenster schließen sich
  gegenseitig)
- Sprachwechsel: Fenster mit den neuen Texten neu aufbauen

**Große Menüs** (Erweiterung aus ForeverBars, im selben Stil)
- Links eine Liste der Bereiche (200 breit, Einträge 20 hoch im 22er-Raster); der gewählte Eintrag hat goldene
  Schrift und goldenen Rand
- Rechts das Feld des Bereichs; mehrere Seiten als Reiter oben rechts im Feld (Knöpfe 96–110 × 20, 4–6 px Abstand,
  aktiver Reiter goldene Schrift und goldener Rand)
- Suche in der Titelleiste rechts (Eingabefeld 200 × 22, 40 px vom rechten Rand): Trefferliste darunter
  („Bereich » Einstellung“); ein Klick springt hin und die Einstellung leuchtet 1,5 s mit goldenem Rahmen auf

**Umbau bestehender Fenster auf diese Bausteine – Lehren aus dem ForeverVendor-Versuch (zurückgenommen)**
- Der Versuch hat die Variante "Große Menüs" (Bereichsliste links) für ein kleines Menü genommen: Inhalte verschwanden
  in Unterpunkten, man musste suchen. **Bereichsliste nur, wenn der Inhalt nicht auf eine Seite passt** (Faustregel:
  mehr als ca. 6 Felder, z. B. ForeverBars, ForeverFrames); sonst alle Felder auf einer Seite in zwei Spalten
- Er hat Inhalte neu sortiert und umbenannt. **Umbau = 1:1**: gleiche Abschnitte, gleiche Reihenfolge, gleiche Texte –
  nur die Bausteine tauschen. Umsortieren ist eine eigene, abgesprochene Änderung
- Das neue Fenster war kleiner als das alte (322er-Spalten), alles wirkte gedrängt. **Nie kleiner als vorher**: die
  322 px stammen aus ForeverQuests und sind kein Muss – Spaltenbreite nach dem längsten deutschen Text wählen,
  Fensterbreite = Spalten + Ränder; Standard-Skalierung 100 %
- Vorgehen: ein Addon nach dem anderen, Vorher-/Nachher-Bild im Spiel vergleichen (Nutzer), erst dann das nächste
- Beispiel für ein Fenster nach diesen Regeln: "Profile" im Hub (`/forever profile`): ein breites Feld oben, zwei
  Felder darunter, Fußleiste – alles auf einen Blick, keine Unterpunkte
## 8. Sprache
- Jede sichtbare Zeichenkette zweisprachig: **Deutsch und Englisch**
- **Eine Sprachwahl für alle** (im Hub-Fenster `/forever`, gespeichert in `ForeverHubDB.language`):
  Deutsch gibt es nur auf einem deutschen Client, dort kann man auf Englisch umstellen; sonst immer Englisch.
  Abfrage: `UI.GetLanguage()` → `"deDE"`/`"enUS"`. Wirkt nach `/reload` (ForeverQuests wechselt sofort)
  - Für die Anzeigesprache fragt kein Addon `GetLocale()` selbst ab, sondern den Hub (`UI.T`, `UI.GetLanguage`);
    `GetLocale()` nur dort, wo es um die Sprache der Spieldaten geht (z. B. Questnamen vergleichen)
  - Eigene Sprachauswahl in einem Addon-Menü (wie bei ForeverQuests) muss in `ForeverHubDB.language` schreiben
- Zwei erlaubte Wege für Texte: `T("Deutsch", "English")` aus dem Hub (Patzlingers Addons) oder `Locales.lua` mit
  Schlüsseln und `ns.L("KEY")` (flowfys Addons), das die Sprache über `UI.GetLanguage()` bestimmt. Innerhalb eines
  Addons nur einen Weg nutzen
- Kommentare im Code auf Deutsch, kurz, erklären das *Warum*; Umlaute in Kommentaren sind erlaubt

## 9. Einstellungen
- **Gemeinsame Verwaltung (ab Hub v28, 0.41b)**: jedes Addon meldet seine SavedVariable einmal an –
  `UI.RegisterSettings({ addon, sv, defaults, version, migrate, global, keepOnReset, reset, legacy })` (am Ende der
  Datei mit den Standardwerten). Der Hub übernimmt damit für alle gleich:
  - **Profile je Charakter**: jeder Charakter nutzt das gemeinsame Profil ("Standard") oder ein eigenes;
    Fenster `/forever profile` (auch im Hub-Fenster). Wechseln, Zurücksetzen und Importieren gelten nach dem
    Neuladen – beim Laden (`ADDON_LOADED`, vor dem Addon) schreibt der Hub das richtige Profil **in dieselbe Tabelle**.
    Das Addon liest seine Einstellungen also wie bisher aus `Forever<Name>DB` und braucht keinen Umschalt-Code
  - **Versionen**: `version` erhöhen, wenn sich der Aufbau ändert; `migrate(data, alteVersion)` rechnet ältere Profile um
  - **Export/Import**: ein Text für die ganze Oberfläche (`/forever export` bzw. `import`, "FC1:" + CBOR, komprimiert,
    Base64 über `C_EncodingUtil`); nur Daten, kein Code; Typen werden gegen `defaults` geprüft; Import = neues Profil
  - Regeln dafür: Schlüssel, die mit `_` beginnen, sind reserviert (`_fc` = Profile, nie ins Profil);
    `global = { … }` für Werte, die für alle Profile gelten (Minimap-Winkel immer); die Tabelle **nie ersetzen oder
    komplett leeren** (`wipe(db)`, `Forever<Name>DB = {}`) – sonst sind alle Profile weg; beim eigenen Zurücksetzen
    `_`-Schlüssel stehen lassen. Charakter-Daten (Lehrerlisten, XP-Verlauf …) gehören in `…CharDB`, nicht ins Profil
  - ForeverBars nutzt die Verwaltung seit 0.41b (frühere eigene Profile wurden übernommen; das bisher aktive
    wurde das gemeinsame Profil); sein Menü ruft dieselben Funktionen auf (`Profiles.lua`)
- Eine SavedVariable pro Addon (`Forever<Name>DB`), bei Bedarf zusätzlich pro Charakter (`…CharDB`)
- Defaults in einer Tabelle; beim Laden (`ADDON_LOADED`) fehlende Werte ergänzen (auch verschachtelt), Tabellen
  kopieren (`CopyTable`) – so bekommen auch Spieler mit älteren gespeicherten Einstellungen neue Optionen
- Gespeicherte Werte erst nach `ADDON_LOADED` lesen (beim Ausführen der Addon-Dateien sind sie noch nicht da)
- Ändert sich die Bedeutung einer Einstellung, alte Werte beim Laden umrechnen statt sie stillschweigend zu verwerfen
  (Beispiel: ForeverBars wandelt die frühere Sichtbarkeit "MOUSEOVER" um)
- Einstellungen wirken sofort (kein "Übernehmen"-Knopf), ein "Zurücksetzen" pro Bereich ist gern gesehen
- Blizzard-Einstellungen (CVars, Tastenbelegung) nur auf ausdrücklichen Wunsch des Spielers ändern

## 10. Verschieben und Positionen
- Alle Rahmen starten **gesperrt**; entsperren per Menü, Rechtsklick auf den Minimap-Knopf oder `/fmove`
- Entsperrt: sichtbarer Griff mit Namen, Ziehen mit Raster/Einrasten, **Shift = frei schieben**; X/Y-Felder im Menü
- Positionen relativ zu einem festen Bezugspunkt (Bildschirmmitte oder -rand) speichern und auf ganze Pixel runden

## 11. Chatbefehle
- Jedes Addon: kurze Form `/f<kürzel>` und lange Form `/forever<name>`; ohne Zusatz öffnet sich das Menü
- Gemeinsame Zusätze (wo sinnvoll): `move`/`lock`, `reset`, `status`
- Belegt (keine Doppelungen!):
  | Befehl | Addon |
  |---|---|
  | /forever, /fhub, /fmove; /forever profile, export, import, options, reset | ForeverHub |
  | /ff, /foreverframes | ForeverFrames |
  | /fu, /foreverunits | ForeverUnits |
  | /fcast, /forevercast | ForeverCast |
  | /fb, /foreverbars | ForeverBars |
  | /fq, /foreverquests | ForeverQuests |
  | /floot, /foreverloot | ForeverLoot |
  | /fxp, /foreverxp | ForeverXP |
  | /fbuffs, /foreverbuffs | ForeverBuffs |
  | /fvendor, /forevervendor | ForeverVendor |
  | /fsb, /fspellbook, /foreverspellbook | ForeverSpellbook |
  | /fchat, /foreverchat | ForeverChat |
  | /fmm, /foreverminimap | ForeverMinimap |
- Tastenkürzel über `Bindings.xml` + `BINDING_HEADER_…`/`BINDING_NAME_…` (Bereich "AddOns")

## 12. Code-Stil
- Einfach und lesbar vor clever; Code wie der umliegende schreiben (Namen, Kommentardichte, Muster)
- Addon-Namensraum: `local addonName, ns = ...`; globale Namen nur für Rahmen (`Forever<Name>…`) und Pflicht-Globale
  (SavedVariables, `SLASH_…`, `BINDING_…`)
- Ereignis-Code absichern, damit ein Fehler nicht das ganze Addon stoppt (`pcall` + `geterrorhandler()`), wo sinnvoll
- Ticker/OnUpdate sparsam: wo Blizzard ein Ereignis liefert, das Ereignis nehmen; Timer nur für Dinge ohne Ereignis
  (Reichweite, verstrichene Zeit) bzw. als seltene Sicherheitsprüfung (≥ 5 s). Mehrere Anlässe kurz hintereinander
  bündeln (`C_Timer.After(0.3, …)` mit "schon geplant"-Merker)
- Blizzard-Rahmen umhängen (`SetParent`, nur mit dokumentierter Ausnahme wie ForeverBars): vorher im Blizzard-Code
  prüfen, ob er Funktionen am Elternrahmen aufruft (Beispiel: die Status-Leisten rufen
  `self:GetParent():CheckForLayoutChange()` auf). Solche Rahmen **nicht umhängen**, sondern nur per `SetPoint` an
  den eigenen Halter anlegen: Eine eigene Ersatz-Funktion am Halter wäre Addon-Code, den Blizzard dann aufruft –
  danach läuft Blizzards Code "getaintet" weiter (Beispiel: Fehler mit gesperrten Werten in
  `CompactUnitFrame_UpdateHealthColor` beim Öffnen des Bearbeitungsmodus, behoben in ForeverBars 0.13.0).
  Allgemein: nie eigene Funktionen oder Werte in Tabellen legen, die Blizzard-Code liest. Quelltext des
  Forever-Clients: github.com/Gethe/wow-ui-source, Zweig **forever**
- Keine Abhängigkeiten zu fremden Bibliotheken (Ace3, LibStub …) – optional erkennen ist ok (z. B. LibSharedMedia)
- Nur eigene Forever-Addons im Repository; keine SavedVariables, keine fremden Addons, keine gebauten Zips

## 13. Testen
- Syntax-Check vor jedem Commit: `lua-language-server --check <ordner> --checklevel=Error`
  (die VS-Code-Erweiterung "Lua" bringt ihn mit; WoW-Globale als "undefined global" sind normal)
- Im Spiel: `/reload`, BugSack prüfen, **auch im Kampf testen** (secret values, geschützte Rahmen)
- Bei Änderungen am Hub: mindestens zwei Forever-Addons gleichzeitig aktiv testen (Sammelknopf, /forever, /fmove)
- Nach jeder Änderung kurz notieren, was der Mitarbeiter im Spiel prüfen soll

## 14. Bekannte Wechselwirkungen
- **ForeverBars ↔ ForeverXP**: ForeverBars setzt die Blizzard-XP-Leiste (`MainStatusTrackingBarContainer`) in
  seinen Halter "xp"; ForeverXP macht sie unsichtbar (Alpha 0) und legt seinen Balken genau darüber.
  Ist ForeverXP aktiv (ab ForeverBars 0.12.0), gehört ihm die Erfahrungsleiste: ForeverBars hält Blizzards Leiste
  fest am Standardplatz (oben mittig, ohne Griff, ohne Größe/Sichtbarkeit aus den eigenen Einstellungen) und
  verweist im Menü mit einem Knopf auf `/fxp`. Position, Größe und Sichtbarkeit stellt man nur in ForeverXP ein
  (Standard "An Blizzards Platz" = oben mittig)
- **ForeverBars ↔ ForeverSpellbook**: ForeverSpellbook legt einen Klick-Knopf über den Zauberbuch-Knopf im
  Mikromenü; ForeverBars verschiebt das Mikromenü – der Knopf hängt am Mikromenü-Knopf und wandert mit.
  Mit den **eigenen Menüknöpfen** von ForeverBars (Standard) sind die eigenen Knöpfe nur Optik; Blizzards echte
  Menüknöpfe liegen unsichtbar (Deckkraft 0) genau darüber und bekommen den Klick selbst (Blizzards Spielmenü öffnet
  nur, wenn die Maus wirklich über seinem Knopf ist – ein weitergeleiteter Klick reicht nicht). Der Knopf von
  ForeverSpellbook hängt am Zauberbuch-Knopf und wandert so mit.
  **Neue Ränge**: ForeverBars ("Neue Ränge automatisch in die Leisten", Standard an) ersetzt beim Lernen eines Rangs
  (`LEARNED_SPELL_IN_TAB`/`…_IN_SKILL_LINE`, 0,5 s später) auf den Aktionsknöpfen den niedrigeren Rang genau dieses
  Zaubers – gleiche Rang-Erkennung wie ForeverSpellbook. Dessen Hinweis "neuer Rang, Leiste hat noch den alten"
  (1 s nach dem Lernen) findet danach nichts mehr; "Ersetzen" im Zauberbuch bleibt für alle übrigen Zauber
- **ForeverMinimap ↔ Minimap-Knöpfe**: ForeverMinimap legt die globale `GetMinimapShape()` an ("SQUARE"/"ROUND",
  wie es LibDBIcon erwartet); `UI.MinimapButton` setzt Forever-Knöpfe bei eckiger Karte an die Kante,
  `UI.RefreshMinimapButtons()` setzt alle neu, wenn sich die Form ändert. Knöpfe anderer Addons am Rand blendet
  ForeverMinimap nur per Alpha ein/aus (Platz bleibt). Blizzards Kopfzeile, Verfolgung, Kalender, Uhr, Post,
  Addon-Menü und Zoom-Knöpfe: Alpha 0 + nicht anklickbar (`UI.HideBlizzard`); eigene Knöpfe rufen deren Funktionen
  auf (`Tracking.Button:OpenMenu()`, `ToggleCalendar`, `TimeManager_Toggle`, `AddonCompartmentFrame:OpenMenu()`).
  Blizzard setzt die Form bei "Minimap drehen" neu (`MinimapCluster:UpdateMinimapConfig`) – ForeverMinimap hängt sich
  dort an. Position und Größe verwaltet Blizzards Bearbeitungsmodus. Das Warteschlangen-Auge (`QueueStatusButton`)
  gehört ForeverBars nur, wenn dessen Warteschlangen-Leiste an ist; sonst lässt Bars es in Ruhe und ForeverMinimap
  zeigt es klein in seiner Leiste (prüft `ForeverBarsDB.bars.queue.enabled`; beide halten es per SetPoint-Hook, nie gleichzeitig)
- **Hub ↔ Details!**: Skin "Forever Core" über `Details:InstallSkin` (`no_cache`, nichts in Details' Speicher). Knopf im Hub:
  `SaveProfile("Forever Core")` = Kopie des aktuellen Details-Profils, `ApplyProfile` (gilt je Charakter), dort Skin für alle
  Fenster; vorheriges Profil in `ForeverHubDB.detailsPrevious`, zweiter Klick wechselt zurück. Details-Ordner nie ändern
- **ForeverQuests ↔ ForeverMinimap**: `followMinimap` (Standard an) hängt den Tracker unter die Minimap/Leiste, gleich breit;
  ForeverMinimap meldet Änderungen per `UI.Fire("ForeverMinimap.Layout")` (Hub-Nachrichten `UI.On`/`UI.Fire`)
- **ForeverBars ↔ Bartender4**: läuft Bartender4, lässt ForeverBars die Leisten in Ruhe
- **ForeverBars ↔ Bearbeitungsmodus**: öffnet der Spieler Blizzards Bearbeitungsmodus, entsperrt ForeverBars seine
  Leisten (Blizzard kann sie nicht greifen) und sperrt sie beim Schließen wieder. Laut flowfy lösen Hooks/Callbacks
  des Bearbeitungsmodus in Forever nicht aus – deshalb wird nur nachgesehen, ob `EditModeManagerFrame` sichtbar ist.
  Eine spätere gemeinsame Lösung im Hub (alle Forever-Rahmen im Bearbeitungsmodus entsperren) muss das genauso machen
  und ForeverBars dann einbeziehen statt doppelt zu entsperren
- **Bearbeitungsmodus speichert Anker an Addon-Rahmen**: Legt ein Addon ein Blizzard-Element per `SetPoint` an einen
  eigenen Rahmen (z. B. die Erfahrungsleiste an `ForeverBars_xp`), merkt sich Blizzards Layout diesen Anker und wendet
  ihn schon beim Laden an. Solche Rahmen deshalb **sofort beim Laden der Datei** anlegen (nicht erst bei
  `PLAYER_LOGIN`), sonst kommt "Couldn't find region named …". Wer das Addon später entfernt, setzt das Element im
  Bearbeitungsmodus einmal zurück, damit der Verweis aus dem Layout verschwindet
  Ist das Addon ausgeschaltet (z. B. über den Hub), legt der Hub für die Namen in `EDITMODE_ANCHORS` unsichtbare
  Platzhalter an Blizzards Standardstelle an – neue Halter-Rahmen, an die Blizzard-Elemente gehängt werden, dort eintragen
- **ForeverBars Proc-Leuchten**: blendet Blizzards Leuchten per `SetAlpha(0)` aus einem `hooksecurefunc` heraus aus
  (taint-frei, gleiches Verfahren wie ForeverXP/ForeverCast)
- **ForeverQuests**: ersetzt den Blizzard-Questtracker
- **ForeverChat ↔ Blizzard-Chat**: Der Chat ist im Forever-Client besonders geschützt (Nachrichten können im Kampf
  gesperrt sein, `AddMessage` läuft über `ScrollingMessageFrameSecureMixin`). Deshalb gilt für Chat-Code:
  - Texte nur über die offiziellen Filter ändern: `ChatFrameUtil.AddSenderNameFilter` (Absendername) und
    `ChatFrameUtil.AddMessageEventFilter` (Nachricht/Argumente). Blizzard überspringt sie bei gesperrten Werten selbst
  - **Nie** `AddMessage`, `GetColoredName`, `SetItemRef` o. Ä. ersetzen und nie `ChatTypeInfo` oder
    `CHAT_TIMESTAMP_FORMAT` beschreiben – das lässt Blizzards Chat-Code danach "verunreinigt" laufen
  - Eigene klickbare Links: `|Haddon:<Addonname>:…|h…|h`; Klicks kommen über `EventRegistry` "SetItemRef"
  - Den Hauptchat (`ChatFrame1`) verwaltet der Bearbeitungsmodus – nicht selbst verschieben
  - Nur Blizzard-Grafiken unsichtbar machen (`UI.HideBlizzard`), eigene Flächen daneben/als Zusatz-Texturen
  - Blizzards Eingabefeld und den Merker für "Antworten" (`ChatFrameUtil.SetLastTellTarget`) nie aus Addon-Code
    setzen: ein verunreinigtes Eingabefeld kann danach Befehle wie `/cast` blockieren. Der Messenger hat deshalb
    ein eigenes Antwortfeld (`C_ChatInfo.SendChatMessage` auf Enter). Wird Flüstern aus dem Hauptchat gefiltert,
    kennt Blizzards /r den Absender nicht – im IM-Reiter antworten
  - Die Reiterleiste (`GENERAL_CHAT_DOCK`) hängt an zwei Ankern über `ChatFrame1.Background`; ForeverChat kürzt sie
    rechts um die eigene Knopfleiste und setzt das nach `FCFDock_SetPrimary` erneut

## 15. Git-Ablauf
- Vor dem Arbeiten: `git pull --ff-only` (bzw. `git pull --rebase`, wenn lokal schon Commits liegen);
  `tools/session-sync.ps1` erledigt das (holen, vorspulen, Stand melden) und eignet sich als SessionStart-Hook
- Während der Arbeit am Live-Ordner (AddOns-Verknüpfung = dieses Repository) NICHT automatisch pushen
- Fertige Änderungen lokal committen (kurze deutsche Nachricht, was und warum) ist erlaubt
- `git push` nur auf ausdrückliches Kommando des Nutzers oder am Ende einer Session (dann kurz nachfragen bzw. ankündigen)
- Bei Konflikten oder unerwarteten Änderungen des anderen erst nachfragen; nie force-pushen
- Größere Umbauten auf einem eigenen Zweig + Pull Request
- Installieren über die CurseForge-App überschreibt die verknüpften Ordner = das Repository → danach `git status`,
  ggf. `git restore .`

## 16. Release
- `release/addons.txt` = Addons im Release; Prototypen erst nach Freigabe eintragen
- Alle Release-Addons tragen dieselbe `## Version` (Suite-Version, z. B. `0.41b`); `tools/build-release.ps1` prüft das
- Alle Release-.toc: `## Title: <Addon> |cff8a8a8a(Beta)|r`, `## X-Curse-Project-ID: 1743753`, `## X-License: MIT`
- `release/README.txt` (DE/EN, kommt ins Gesamt-Zip) bei neuen Befehlen/Funktionen anpassen
- `release/Changelog-CurseForge.txt` = Englisch, für Spieler geschrieben; wandert nicht ins Zip
- `release/Description-CurseForge.txt` = Text der CurseForge-Hauptseite (Englisch, Markdown); bei neuen Addons/Funktionen anpassen, nicht ins Zip
- ForeverCore ist immer im Release und steckt in **jedem Einzel-Zip** mit (sonst lädt das Addon nicht)
- Bauen mit `tools/build-release.ps1` (Versionsprüfung, Addon-Ordner, Einzel-Zips, Gesamt-Zip);
  fremde Zips im Zielordner werden nie angefasst
