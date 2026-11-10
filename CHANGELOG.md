# Changelog

## 1.2.5 – 2026-11-10

### Live und Chat
- Der Chat ist auch ohne laufenden Livestream verfügbar.
- Mitteilungen informieren über Erwähnungen und Reaktionen auf eigene Nachrichten, auch wenn die Live-Seite geschlossen ist.

### Einstellungen
- Die Einstellungen sind in übersichtliche Bereiche mit eigener Suche und Navigation aufgeteilt.
- Mitteilungen für Folgen, Livestreams und den Live-Chat lassen sich getrennt einrichten.

## 1.2.4 – 2026-11-09

### Suche
- Suchfeld und Filter schweben auf Glas über den Treffern; Karten laufen beim Scrollen darunter hindurch und blenden zum Seitentitel weich aus.
- Die Filtermenüs für Format, Reihenfolge und Person sind besser lesbar. Aktive Einschränkungen sind in der Akzentfarbe markiert.
- Der Suchfokus wird ohne sichtbares Aufpoppen gesetzt.

### Live und Chat
- Der Chat folgt neuen Nachrichten, solange du am unteren Ende liest. Beim Zurückscrollen pausiert er und zählt neue Nachrichten; eine Schaltfläche führt zurück zur neuesten Nachricht.
- Die Live-Fenstergröße passt sich an die Videogröße und die gewählte Chatposition an.
- Antworten auf eigene Chatnachrichten werden zuverlässiger den ausstehenden Nachrichten zugeordnet.

## 1.2.3 – 2026-11-08

### Mediathek und Darstellung
- Der Hintergrund der Mediathek übernimmt einen dezenten Farbton aus dem aktuellen Hero-Bild und wechselt weich mit dem Banner. Andere Seiten behalten ihren bisherigen Hintergrund.
- Ein breiterer Verlauf verbindet das Hero-Bild mit dem Seitenhintergrund, ohne Titel und Schaltflächen auszublenden.
- Die obere Navigation ist auf hellen und unruhigen Bildhintergründen besser lesbar.
- Bei ausgeschaltetem „Mit Theme einfärben“ bleibt der Akzent Orangeflix-Orange statt der Systemakzentfarbe. Auch die sanften Akzentflächen berücksichtigen den tatsächlich verwendeten Hintergrund.

### Suche und Folgennavigation
- Suchkarten sind großzügiger aufgeteilt: links eine größere 16:9-Vorschau, rechts Titel, Beschreibung und Zeitmarken. Schriftgrößen und Abstände wurden angepasst.
- Der Eingabefokus wird beim Öffnen der Suche später und ohne zusätzliche Fokusanimation gesetzt; der interaktive Leuchteffekt des umgebenden Glases entfällt.
- Suchfeld und Filterleiste schweben über den Treffern: Beim Scrollen laufen die Karten unter den Glasflächen hindurch und blenden zum Seitentitel hin weich aus, statt an einer harten Kante zu enden.
- Die Menüs für Format, Reihenfolge und Person stehen auf demselben Glas wie die Trefferarten und bleiben so über den Karten lesbar. Ein eingrenzender Filter erscheint in der Akzentfarbe.
- Videokarten in Merkliste, Weiterschauen und ähnlichen Folgen führen zur Folgenseite statt unmittelbar ins separate Player-Fenster. Auch das Merkliste-Regal der Mediathek öffnet die Folgenseite.
- „Ansehen“ für eine einzelne Folge startet die Wiedergabe auf der Folgenseite. Ausdrückliche Player-Fenster-Aktionen und die Wiedergabe mehrerer ausgewählter Folgen bleiben verfügbar.
- Merkliste und Weiterschauen besitzen eigene Navigationsverläufe; weiterführende Seiten bleiben im jeweiligen Bereich.

### Live und Fensterverhalten
- Die App merkt sich Größe und Position des normalen Fensters vor dem Wechsel zu Live und stellt sie beim Verlassen wieder her.
- Die temporäre Live-Größe überschreibt die gespeicherte normale Fenstergröße nicht mehr. Beim Seitenwechsel wird die Startgröße nicht erneut angewendet.
- Automatische Verbreiterungen verschieben das Fenster nicht mehr unnötig um seinen Mittelpunkt. Wiederhergestellte Fenster werden an den verfügbaren Bildschirmbereich angepasst.

### Einstellungen und Mitteilungen
- Die Einstellungen verwenden eine native Seitenleiste mit integrierter Suche und Navigation in der Symbolleiste.
- „Allgemein“ bündelt Softwareupdates, Download-Speicherort, Mitteilungen und Hintergrundbetrieb.
- Die Eingabetaste öffnet den ersten Einstellungssuchtreffer; `⌘[` und `⌘]` führen zurück und vor.
- Format-Treffer unterscheiden zwischen Mediathek-Sichtbarkeit und Mitteilungen. Beim Öffnen werden störende Formatfilter zurückgesetzt, damit die gesuchte Einstellung sichtbar ist.
- Push-Geräte zeigen getrennte Lade-, Fehler- und Leerzustände und lassen sich manuell aktualisieren. Die Beschreibung unterscheidet Server-Push-Geräte von angemeldeten Sitzungen und lokalen Mac-Mitteilungen.
- Unbekannte Geräteantworten oder fehlende Gerätekennungen werden als Fehler behandelt, statt unbemerkt als leere Liste zu erscheinen.

### Technische Korrekturen
- Korrekturen an CoreGraphics-Imports, Actor-Isolation der Suchkoordinaten und Referenzen in der Videovorschau verbessern die Kompatibilität mit dem aktuellen Swift-Compiler.
- Prozentanzeigen in Umfragen und den betroffenen Folgenansichten verwenden die sprachabhängige Zahlenformatierung.
- Zusätzliche Logiktests decken Geräteantworten und Fensterrahmenberechnungen ab.

---

Frühere Versionshinweise stehen in den [GitHub Releases](https://github.com/revunix/Orangeflix-macOS/releases).
