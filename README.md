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
`X.Y.Z` und den Changelog eingeben. Der Workflow erstellt ein signiertes und
notarisiertes Release-Archiv, erzeugt daraus `appcast.xml` und veröffentlicht
Release und Versionshinweise zusammen.

Dafür müssen im Repository unter **Settings → Secrets and variables → Actions**
diese Secrets hinterlegt sein: `SPARKLE_EDDSA_PRIVATE_KEY` (base64-kodierter
privater Sparkle-Schlüssel), `APPLE_CERTIFICATE_P12` (base64-kodiertes Developer
ID-Zertifikat), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_NOTARY_KEY_ID`,
`APPLE_NOTARY_ISSUER_ID` und `APPLE_NOTARY_KEY_P8` (Inhalt des App-Store-Connect-
Notarisierungsschlüssels). Private Schlüssel gehören ausschließlich in GitHub
Secrets, nie in den Quelltext.

## Lizenz

Der Quelltext steht unter der [MIT-Lizenz](LICENSE).
