# Menü-Aufbau im Detail (Maße aus dem ForeverQuests-Menü)

Ausgelagert aus CLAUDE.md (Abschnitt 7.1). Lesen, wenn ein Einstellungsfenster oder Menü gebaut oder umgebaut wird.

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
