# Fenster-Stil (ForeverSkin) – Regeln für jedes neue Blizzard-Fenster

Gewonnen aus Händler (`Merchant.lua`), Handel (`Extra.lua`, SkinTrade) und Briefkasten (`Mail.lua`). Ein neues Fenster
wird **beim ersten Versuch** nach diesen Regeln gebaut – nicht erst nach mehreren Runden Feinschliff.
Werte in Punkten des Fensters (vor `ns.Scaled`).

## 1. Grundsatz (Taint, Sperren)

- Blizzards Grafiken nur unsichtbar machen (`SetAlpha(0)` bzw. `ns.Hide`/`ns.HideTextures`), eigene Texturen
  darunter/daneben. **Nichts in Blizzards Tabellen schreiben** – eigene schwache Tabellen (`setmetatable({}, { __mode = "k" })`).
- **Vor jedem Zugriff prüfen, ob ein Rahmen gesperrt ist** (`obj.IsForbidden and obj:IsForbidden()`), auch beim
  Durchlaufen von Unter-Rahmen. Gesperrte Teile bleiben im Blizzard-Look (Beispiele: Rückfrage „Handel abschließen?“,
  Gold-Eingabe im Handel). Nie raten: mit `/fskin maus` nachsehen.
- Gesperrte Teile lassen sich auch nicht verschieben – dann wächst das Fenster **optisch** (eigene Fläche mit
  negativem Einzug, `ns.Flat(f, C.background, { 0, -oben, 0, -unten })`) statt Inhalt zu verschieben.

## 2. Größe und Aufbau von oben nach unten

- **Größe wie das Gesprächsfenster** (`GossipFrame`, Grundmaß 384 × 512), danach `ns.Scaled(f)` (Regler „Größe“).
  Kleinere Blizzard-Fenster auf diese Größe setzen und laufend halten (siehe Lehrer, Briefkasten).
- **Titelleiste** 23 hoch mit goldener Linie (`ns.SkinWindow`), Titel mittig, Schließen-Kreuz rechts.
  **Links immer „Dein Gold: …“** – kommt automatisch mit `ns.SkinWindow` (`ns.HeaderGold`, aktualisiert sich bei
  jeder Gold-Änderung). Eigenes Gold dann nirgends sonst im Fenster (Blizzards Gold-Anzeigen ausblenden); wächst die
  Titelleiste nach oben, die Anzeige mitversetzen. Ausnahmen: Beute-Fenster (zu schmal), Optionen-Fenster, Makro-Fenster, Berufe, Talente, Gilde & Communitys,
  Sammlungen/Vorlagen, Gruppensuche, Chat-Einstellungen/-Channels, Charakterfenster, Abklingzeiten-Manager, Sozialfenster samt Ignorierliste (kein Bezug zum Gold bzw. auf
  Wunsch) – Liste GOLD_SKIP in ForeverSkin/Core.lua.
- **Variante ohne Titelleiste** (Anprobe, Charakterfenster): flache Fläche, Titel gold oben, kleines rundes Porträt
  mit goldenem Ring auf der oberen linken Ecke, feine goldene Linie unter dem Kopf.
- **Visitenkarte** unter der Titelleiste (wie `ns.NpcCard`): rundes Bild mit goldenem Ring (48 Ring / 45 Fuge /
  43 Bild, Mitte bei (36, −56)), daneben Name groß in Gold (`GameFontNormalLarge` bei (68, −37)), darunter Unterzeile
  (`GameFontHighlightSmall`, 0.85 grau) und Info (`GameFontDisableSmall`). Ohne NPC ein passendes Symbol (Briefkasten:
  Brief). **Zwei Parteien** (Handel): je Spalte eine kleinere Karte (40 / 37 / 35), mittig zwischen Titelleiste und
  erstem Kasten – gleich viel Luft oben und unten.
- **Inhalt ab TOP = −87**; Innenfläche `TOPLEFT (6, TOP + 4)` bis `BOTTOMRIGHT (−6, FOOTER + 4)`.
- **Fußleiste** `ns.ContentBox(f, FOOTER, nil, true)` mit feiner goldener Linie: FOOTER = 40 (einzeilig), 54 bei
  zwei Zeilen. Knöpfe **mittig auf halber Höhe**, 10 vom Rand, **8 zwischen Knöpfen**, „Abbrechen“ ganz rechts,
  Hauptaktion links daneben. **Nichts darf auf der goldenen Linie liegen** – mindestens 6 Luft zu Kästen darüber.
- Reiter unter dem Fenster: `ns.SkinTab` (gewählter gold), 8 Abstand zwischen den Reitern.

## 3. Zeilen und Plätze (Listen, Gegenstände)

- **Je Zeile ein grauer Balken** (`C.button`, 1-px-Rand `C.border`), Lücke zur nächsten Zeile (≈ 4).
  Maus über der Zeile: Rand gold. Wo man etwas ablegen kann: Ablegen auf der **ganzen Zeile** erlauben.
- **Symbol-Platz links im Balken mit 1 px Luft rundum** (Balken = Platz ± 1, links ebenso).
- **Platz-Look wie ForeverBags**: dunkle Fläche (0.06, 0.06, 0.08, 0.85), 1-px-Rand `C.border`, Maus auf dem Platz =
  gold (`C.accent`, 0.9), Symbol 1 px eingerückt (`SetTexCoord(0.07, 0.93, 0.07, 0.93)`), Blizzards Seltenheitsrand
  (`IconBorder`) bleibt. **Leere Plätze zeigen das dunkle Feld** (ggf. selbst zeichnen, wenn Blizzard den Knopf
  ausblendet). Keine hellen Kästchen.
- Neben dem Symbol: Name in Seltenheitsfarbe (einzeilig), darunter klein die Art/Info (`GameFontDisableSmall`).

## 4. Knöpfe, Pfeile, Eingaben, Geld

- Text-Knöpfe `ns.SkinButton`. Setzt Blizzard die Grafiken wieder ein (rote Knöpfe), zusätzlich einen **eigenen
  flachen Kasten als Geschwister-Rahmen dahinter** und Blizzards Grafiken **laufend** ausblenden (siehe Handel).
- Blätter-Pfeile `ns.SkinArrowButton` und deren Blizzard-Grafiken ebenfalls laufend ausblenden; ausgegraut blasser.
- Eingabefelder flach (`C.input`, Einzug `{ −4, 1, 0, 1 }`), Blizzards Left/Middle/Right weg.
- **Geld immer als drei Felder Gold / Silber / Kupfer mit Münz-Symbol** (auch reine Anzeigen, z. B. Betrag des
  Handelspartners). Münz-Symbole beim Umgestalten behalten (Pfad/Atlas mit coin/money/gold/silver/copper oder Grafik
  ≤ 20 breit).
- **Kontostand eindeutig beschriften** („Dein Gold: …“) und **keine doppelten Anzeigen** – Blizzards Doppel
  ausblenden. Kosten/Porto nicht mit dem Kontostand verwechselbar platzieren.

## 5. Texte, Effekte, Rückmeldung

- Texte auf Pergament hell machen (≈ 0.92) bzw. dunkle Farbcodes mit `ns.LightenCodes` aufhellen.
- **Keine Blizzard-Leucht-Animationen** (Glow beim Hineinlegen/Herausnehmen …): Animationsgruppen anhalten und die
  Grafik verstecken – Animationen setzen die Deckkraft selbst und überstimmen `SetAlpha(0)`.
- Eigene Rückmeldung nur wie beim Händler: gedrückt kurz dunkler, ausgeführt kurzes goldenes Aufleuchten.

## 6. Robustheit (gleich von Anfang an einbauen)

- Blizzard hängt Teile beim Aktualisieren neu auf: eine **`Place()`-Funktion** mit allen festen Plätzen, Ankerpunkte nur
  setzen, wenn sie abweichen; aufrufen beim Öffnen, nach Blizzards `…_Update` (`hooksecurefunc`), bei passenden
  Ereignissen und im **0,2-s-Takt, solange das Fenster offen ist**.
- **Jeder Teilschritt einzeln abgesichert** (`Step(name, fn)` mit `pcall` und `ns.UI.ReportError`) – ein Fehler hält die
  übrigen Schritte nicht auf und ist im Chat sichtbar.
- Erst-beim-Öffnen geladene Fenster: `ADDON_LOADED` (Blizzard-Addon) + `PLAYER_LOGIN` + Öffnungs-Ereignis.
  Rückfrage-Fenster entstehen teils erst beim Anzeigen (`hooksecurefunc("StaticPopup_Show", …)`).
- Schalter in `ns.DEFAULTS` und als Haken in `/fskin` (Einstellungsseite darunter verlängern).
- Andocken: ForeverBags hängt die Taschen an Händler, Bank und Handel – bei neuen Fenstern mit Gegenständen
  (z. B. Auktionshaus) gleich mit vorsehen.

## 6a. Erfahrungen aus Talente, Gruppensuche, Chat, Charakterfenster (2026-10)

- **Forever-Namen weichen ab** (Charakterfenster: `CharacterStatsPaneScrollBox` ist ein einfacher Rahmen mit Liste
  darin, Seiten heißen `PVPRankFrame`, `SkillsFrame`; Gruppensuche ist `LFGParentFrame`, Sammlungen
  `CollectionsJournal`). Nie Blizzards Retail-Namen voraussetzen – erst `/fskin maus` bzw. `/fskin grafik`.
- **Blizzard macht Ausgeblendetes wieder sichtbar** (beim Öffnen, Umschalten, per Animation oder durch Neusetzen der
  Grafik). Ausblenden im Takt reicht dann nicht: **Haken an der Grafik selbst** (`hooksecurefunc` auf
  `SetAlpha`/`Show`/`SetAtlas`/`SetTexture`, mit Sperre gegen Schleifen) oder **ganz verstecken** (`Hide` + Haken auf
  `Show`), Backdrops mit `ClearBackdrop` und Haken auf `SetBackdrop`.
- **Kein Aufblitzen:** Umgestalten, bevor gezeichnet wird – im `OnShow` der Seite (Blizzard hat die Liste dann schon
  gefüllt), bei modernen Listen über `ScrollUtil.AddInitializedFrameCallback` (jeder Eintrag beim Befüllen), und nach
  dem Öffnen/Reiterwechsel eine halbe Sekunde in **jedem** Bild statt nur im Takt.
- **Kein Springen:** Verschiebt man Blizzard-Bereiche, die Blizzard neu verankert, mit einem Haken auf `SetPoint`
  sofort nachziehen (Sperre gegen die eigene Änderung). Messen statt fester Werte (oberste sichtbare Kante, auch Texte
  über dem Rand).
- **Eigene Grafiken auf eigenen Unter-Rahmen**, wenn im Takt `ns.HideTextures` über denselben Rahmen läuft (sonst
  blendet man die eigenen Linien gleich wieder aus); eigene Hilfsrahmen in einer Tabelle merken und beim Verschieben
  auslassen.
- **Ebenen:** Hintergründe von Seiten sind oft eigene Rahmen über dem Fenster – eigene Ränder, Linien und Porträts dann
  auf einem eigenen Rahmen mit hoher Ebene (`GetFrameLevel() + 100`), sonst verdeckt.
- **Feine Linien immer über `ns.OnePixel`** (genau 1 Bildschirmpixel, scharf bei jeder UI-Skalierung), nicht
  `SetHeight(1)`.
- **Zierelemente**: Trennlinien „common-framedivider“ (11 breit mit Schatten) durch eine eigene 1-px-Goldlinie ersetzen;
  „…ScrollLine…“, „common-insideframe“, „TopTileStreaks“ und Steinstreifen („…StoneBG…“) ausblenden.
- **Plus/Minus zum Auf-/Zuklappen** als feine Pfeile (`ns.SkinToggle`, Zustand aus Blizzards unsichtbarer Grafik:
  minus/plus bzw. Datei-Nummern 130821/130838).
- **Gleiche Vorlage = gleiche Umgestaltung:** z. B. Symbol-Auswahl (IconSelectorPopupFrameTemplate) über
  `ns.SkinIconPopup` (Makros, Ausrüstungssets).

## 7. Prüfbefehle

- `/fskin maus` – Fenster unter der Maus samt Eltern-Kette, „(geschützt)“ bei gesperrten Rahmen.
- `/fskin grafik` – Grafiken unter der Maus (Schlüssel, Atlas/Datei, Ebene, Größe, Eltern). Findet nur Rahmen, die die
  Maus annehmen – sonst einen eigenen Prüfbefehl mit Auflistung aller sichtbaren Grafiken bauen (siehe `/fskin lfg`).
- `/fskin fenster` – alle großen benannten Fenster des Spiels, umgestaltet (+) oder nicht (−).
- `/fskin aufbau <Fenstername>` – kompletter Aufbau eines Fensters (Unter-Rahmen, Grafiken, Schlüssel, Größen,
  Anker, Atlas/Datei) in `ForeverSkinDB._dump`; nach `/reload` in `WTF\Account\*\SavedVariables\ForeverSkin.lua`
  lesbar. Für Fenster, deren Forever-Fassung in keinem öffentlichen Quelltext steht (Stall: weder Blizzards neuer
  `StableFrame` noch die Classic-/Cata-Fassung passen).
- `/fskin lfg` (Gruppensuche: Reiter, ausgeblendete und sichtbare Grafiken), `/fskin werte` (Werte-Spalte im
  Charakterfenster), `/fskin taxi` (Flugkarte) – Vorlagen für ähnliche Untersuchungen.

## 8. Ablauf für ein neues Fenster

1. Fenster mit `/fskin maus` ansehen lassen (Namen, gesperrte Teile) – nicht raten.
2. Datei in `ForeverSkin/` anlegen (in die `.toc`), Schalter + Haken, Laden wie oben.
3. Aufbau nach Abschnitt 2, Zeilen/Plätze nach 3, Bedienelemente nach 4, Effekte nach 5, Robustheit nach 6.
4. Prüflauf, Changelog, Commit; beim Spieler Screenshots von **allen Reitern/Zuständen** erbitten (leer, gefüllt,
   ausgegraut).
