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

## Updates

Die App verwendet [Sparkle](https://sparkle-project.org/) für Update-Prüfung,
Download, Signaturprüfung und Installation. **Orangeflix → Nach Updates suchen …**
oder **Einstellungen → Über → Softwareupdate** öffnet die Update-Prüfung; Sparkle
zeigt die zum Release gehörenden Versionshinweise an.

Updates werden aus GitHub Releases bezogen. Dafür muss das Repository öffentlich
sein und ein Release die von Sparkle signierte `appcast.xml`, ein signiertes
App-Archiv und die Versionshinweise enthalten. Der private EdDSA-Schlüssel liegt
lokal im macOS-Schlüsselbund und darf nicht in dieses Repository gelangen.

### Release veröffentlichen

Unter **Actions → Publish macOS release → Run workflow** eine Version im Format
`X.Y.Z` und den Changelog eingeben. Der Workflow baut die App mit Ad-hoc-
Signierung, signiert das Update-Archiv mit Sparkle, erzeugt `appcast.xml` und
veröffentlicht Release und Versionshinweise zusammen.

Dafür muss im Repository unter **Settings → Secrets and variables → Actions**
das Secret `SPARKLE_EDDSA_PRIVATE_KEY` (base64-kodierter privater Sparkle-
Schlüssel) hinterlegt sein. Der Workflow benötigt keinen Apple-Account.

Da Apple die App nicht notariert, kann Gatekeeper beim ersten Öffnen eine Warnung
anzeigen. Nutzer müssen die App dann gegebenenfalls über **Rechtsklick → Öffnen**
freigeben. Sparkle prüft heruntergeladene Updates weiterhin mit der EdDSA-
Signatur. [Hinweise von Sparkle zu Signaturen und Verteilung](https://sparkle-project.org/documentation/)

## Lizenz

Der Quelltext steht unter der [MIT-Lizenz](LICENSE).
