# Orangeflix for Mac

Eine inoffizielle macOS-App, mit der du die Mediathek eines Orangeflix.de-Kontos am Schreibtisch nutzen kannst. Das Projekt wird privat von [Alexander (@revunix)](https://github.com/revunix) entwickelt und steht in keiner Verbindung zu Orangeflix.de oder dessen Betreibern.

## Funktionen

- Mediathek und Folgen durchsuchen und ansehen
- Livestreams mit Chat und Umfragen
- Folgen herunterladen und die Download-Warteschlange verwalten
- Einstellungen, Formate und Bibliothek lokal verwalten

## Voraussetzungen

- macOS 15 oder neuer
- Xcode mit macOS-SDK
- [Homebrew](https://brew.sh/) und mpv zum Erzeugen der eingebetteten libmpv-Bibliotheken

## Bauen

1. Abhängigkeit installieren und die lokalen libmpv-Dateien erzeugen:

   ```sh
   brew install mpv
   scripts/vendor-libmpv.sh
   ```

2. `Orangeflix.xcodeproj` in Xcode öffnen.
3. Das Scheme **Orangeflix** und als Ziel **My Mac** auswählen.
4. Mit **⌘R** bauen und starten oder mit **⌘B** nur bauen.

Die erzeugten libmpv-Dateien unter `Vendor/libmpv` sind maschinenspezifisch und werden nicht mit Git versioniert. Das Skript erstellt sie lokal aus der Homebrew-Installation.

## Logiktests

Das Swift-Package enthält Tests für reine Logik ohne SwiftUI, AppKit oder mpv:

```sh
swift test
```

## Lizenz

Der Quelltext steht unter der [MIT-Lizenz](LICENSE).
