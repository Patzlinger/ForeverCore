# Bekannte Wechselwirkungen (Addons untereinander, mit Blizzard und fremden Addons)

Ausgelagert aus CLAUDE.md (Abschnitt 14). Lesen, bevor ein Addon etwas anfasst, das ein anderes Addon oder
Blizzard auch benutzt (Leisten, Minimap, Taschen, Chat, Tracker, Bearbeitungsmodus, Questie, Details, Leatrix, Masque).

- **Blizzard-Vorlagen mit fester Ebene** (z. B. `ContainerFrameItemButtonTemplate`: `frameLevel="10"`): der Hub
  (`UI.BringToFront`) hebt Forever-Fenster beim Nach-vorne-Holen auf Ebenen weit über 10 – solche Knöpfe bleiben
  stehen und liegen dann HINTER der eigenen Fensterfläche (dunkel, nicht anklickbar; trat 2026-10-20 in ForeverBags
  auf). Abhilfe: `SetFixedFrameLevel(false)` und Ebene knapp über den Rahmen setzen (`ns.FollowParentLevel`).
  Zur Fehlersuche: `GetMouseFoci()` zeigt, welcher Rahmen die Maus wirklich hat (z. B. `/fbags bankcheck`).
- **Zugriff auf andere Addons nur mit Erlaubnis (verbindlich):** Bevor eine Funktion auf ein anderes Addon zugreift
  (dessen Datenbank, Funktionen, Fenster oder Einstellungen), immer zuerst prüfen, ob der Ersteller das erlaubt:
  Lizenz (CurseForge-Seite, LICENSE-Datei, .toc `X-License`), README/API-Doku und ausdrückliche Hinweise des Autors.
  Ergebnis kurz im Code-Kommentar oder hier festhalten. Ist es verboten oder unklar: nicht einbauen, sondern
  nachfragen. Nie Code oder Daten fremder Addons kopieren oder mitliefern – nur zur Laufzeit lesen, was der Spieler
  selbst installiert hat, und ohne das Addon muss alles weiterlaufen.
  Stand der Prüfung: **Questie/QuestieDB** (2026-10-18) – GPLv3 laut CurseForge, kein Verbot; Questie bietet
  `Questie.API` an, QuestieDB lädt Fremd-Addons ausdrücklich ein (`LibQuestieDB`, docs/api.md). Wir nutzen zum Teil
  Interna (`QuestieLoader:ImportModule`) – erlaubt, aber nicht stabil, darum alles mit pcall abgesichert.
  Questie-Einstellungen, die Forever umstellt: `trackerEnabled`, `hideUntrackedQuestsMapIcons` (ForeverQuests),
  `nameplateEnabled` (ForeverPlates zeigt Questies Plaketten-Symbol selbst vor dem Namen; aus = wieder an).
- **Dungeondaten von ForeverQuests nur aus Spiel und Questie (seit 2026-10-18, verbindlich):** Das Dungeonfenster
  baut Dungeons, Quests, Questreihen, Vorquests und Belohnungen zur Laufzeit aus dem Spiel und aus Questies Datenbank
  (`QuestieDungeons.lua`); `Data/Dungeons.lua` bleibt leer. Die frühere selbst gepflegte Excel-Tabelle samt Kopien
  wurde auf Wunsch von flowfy gelöscht – keine eigene Tabelle oder Datensammlung dafür mehr vorschlagen oder anlegen.
  Fehlen Daten (z. B. Questreihen neuer Forever-Quests), lieber aus vorhandenen Daten ableiten (gleichnamige Quests).
- **Andere Addons für dieselbe Aufgabe** (Hub v41, Abschnitt 3b "ConflictDefs" in ForeverHub.lua): je Paar (z. B.
  ForeverBars ↔ Bartender4) wählt der Spieler, welches läuft; das andere wird über C_AddOns ausgeschaltet. Fenster
  ForeverHubConflicts erscheint beim ersten Start neben der Begrüßung und bei neuen Paaren einmal (ForeverHubDB:
  conflictAsked, conflictChoice), sonst über "Andere Addons …" im Hub. Neue Konkurrenz-Addons dort eintragen
  (Ordnername!). Pakete wie ElvUI absichtlich nicht (würden ganz abgeschaltet).
- **Leatrix Plus** (Hub v42, `LeatrixDefs`): nicht ganz abschalten, sondern nur die Funktionen, die ein Forever-Addon
  übernimmt (`MinimapModder` ↔ ForeverMinimap, `TipModEnable` ↔ ForeverTooltip, Chat-Schalter ↔ ForeverChat,
  Tasten-/Makrotext ↔ ForeverBars). ForeverCore lädt vor Leatrix und setzt beim ADDON_LOADED von Leatrix_Plus
  `LeaPlusDB[key] = "Off"` – unmittelbar bevor Leatrix liest. Selbst abgeschaltete Schlüssel merkt
  `ForeverHubDB.leatrixOff` (Wahl "Leatrix" stellt sie zurück). Händler (Verkaufen/Reparieren) bewusst nicht: doppelt
  schadet nicht. Leatrix Maps: nur Weltkarte, keine Überschneidung.
- **Masque** (optional, ## OptionalDeps: Masque): ForeverBars (Masque.lua, Gruppe "Forever Core › ForeverBars")
  und ForeverBags (Gruppe "› ForeverBags"). Gestaltet Masque, lassen wir Rand/Fläche/Symbol/Leuchten weg
  (`ns.MasqueActive()`), Texte bleiben bei uns; Gruppe in Masque aus = eigener Stil.
- **Erfahrungs- und Rufleiste sind Leisten von ForeverBars** (seit 0.44b; das Addon ForeverXP ist darin aufgegangen,
  Stand davor: Git-Markierung `snapshot-vor-xp-rep-umbau` bzw. `..\_Forever-Beiseite\ForeverXP-vor-Integration`).
  `Status.lua` baut den Inhalt (`kind = "status"`: Füllung, Zehntel-Striche, drei Textzonen mit Ruhe-/Maus-drüber-Fassung,
  Tooltip); Halter, Verschieben, Einrasten, Sichtbarkeit, Profile kommen aus Bars.lua wie bei den Aktionsleisten. Standard:
  genauso breit wie Aktionsleiste 1 (`ns.ActionBarWidth()`, `width = nil`), ganz unten (Erfahrung unten, Ruf darüber),
  alle anderen Leisten beginnen darüber (`DefaultPosition`, Layout-Version 19). Blizzards Behälter werden nur unsichtbar
  (Alpha), und zwar der, der gerade Erfahrung (`shownBarIndex == StatusTrackingBarInfo.BarsEnum.Experience`) bzw. Ruf
  (`BarsEnum.Reputation`) zeigt, solange die eigene Leiste an ist (Hook auf `ApplyPendingBarToShow` verteilt neu) – nie
  den ganzen `StatusTrackingBarManager`. Spielzeit pro Level liegt weiter in `ForeverXPCharDB`. Layouts im Bearbeitungsmodus,
  die an `ForeverBars_xp`/`ForeverBars_rep` hängen, finden wieder die Halter (Hub-Platzhalter nur bei ausgeschaltetem Addon)
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
  zeigt es ganz unten rechts in der Karte (rund: auf dem Kreisrand; prüft `ForeverBarsDB.bars.queue.enabled`; beide halten es
  per SetPoint-Hook, nie gleichzeitig). Neue Post: eigene Kachel in der Ecke unten neben der Knopfleiste, exakt zwischen Leiste
  und dem unter der Karte angedockten Mikromenü von ForeverBars (Höhe = Mikromenü, Signal `ForeverBars.Layout`)
- **Hub ↔ Details!**: Skin "Forever Core" über `Details:InstallSkin` (`no_cache`, nichts in Details' Speicher). Knopf im Hub:
  `SaveProfile("Forever Core")` = Kopie des aktuellen Details-Profils, `ApplyProfile` (gilt je Charakter), dort Skin für alle
  Fenster; vorheriges Profil in `ForeverHubDB.detailsPrevious`, zweiter Klick wechselt zurück. Details-Ordner nie ändern
- **ForeverQuests ↔ ForeverMinimap**: `followMinimap` (Standard an) hängt den Tracker unter die Minimap/Leiste, gleich breit;
  ForeverMinimap meldet Änderungen per `UI.Fire("ForeverMinimap.Layout")` (Hub-Nachrichten `UI.On`/`UI.Fire`)
- **ForeverBars ↔ ForeverMinimap ↔ ForeverQuests**: das Mikromenü (`ForeverBars_micro`) dockt standardmäßig
  (`bars.micro.dockMinimap`) unter der Karte bzw. unter `ForeverMinimapBar`, wenn die unten liegt – per Skalierung
  so breit wie die Karte samt Rahmen; weggezogen ist es frei, nahe der Stelle losgelassen rastet es wieder ein.
  ForeverBars meldet jede Anordnung per `UI.Fire("ForeverBars.Layout")`; ForeverQuests setzt den Tracker dann 4 px
  unter das Menü, hängt ihn aber weiter an Karte/Leiste (das Menü ist geschützt – daran gehängt dürfte der Tracker
  im Kampf nicht mehr ein-/ausgeblendet werden). Anheften am Chatfenster gibt es nicht mehr
- **ForeverBags ↔ ForeverBars / Blizzard**: ForeverBars besitzt die Taschenleiste (Rucksack- und Taschenknöpfe),
  ForeverBags nur das Taschen**fenster**. Ein Klick auf den Rucksack ruft Blizzards `ToggleBackpack` – ForeverBags hört
  das mit und öffnet sein Fenster. Händler, Post und Bank öffnen/schließen über `OpenAllBags`/`CloseAllBags` ebenso.
  Blizzards Umschalt-Funktionen rufen intern selbst Öffnen/Schließen auf (im selben Bild): ForeverBags merkt sich
  den Zustand vom Beginn des Bildes und schaltet genau einmal um. Suche über `C_Container.SetItemSearch` (gilt wie bei
  Blizzard auch für die Bank), Sortieren über `C_Container.SortBags`.
  Das Taschenfenster ist nie gesperrt (an der Titelleiste ziehbar, ohne Raster/Hilfslinien) und meldet sich deshalb
  nicht bei `/fmove` an. Taschen, Bank und Gold aller Charaktere liegen kontoweit in `ForeverBagsData` (eigene
  SavedVariable, nicht über `UI.RegisterSettings` – Charakter-Daten, keine Einstellungen); die Bank wird nur gespeichert,
  solange sie offen ist (nach `BANKFRAME_CLOSED` wäre sie leer)
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
  (taint-frei, gleiches Verfahren wie ForeverCast)
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

