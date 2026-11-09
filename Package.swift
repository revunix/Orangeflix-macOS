// swift-tools-version: 6.0
//
// Test harness for the pure logic of the app.
//
// The app itself is built by Xcode (`Orangeflix.xcodeproj`). This package does
// not build the app: it compiles a hand-picked set of the app's source files
// that have no UI and no libmpv dependency, so `swift test` can exercise them
// without a running app. The files are referenced in place, never copied, so a
// test always runs against the code that ships.
//
// Add a file here when it is pure logic (no SwiftUI, no AppKit, no mpv).
import PackageDescription

let package = Package(
    name: "OrangeflixLogic",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "OrangeflixLogic",
            path: "Orangeflix",
            sources: [
                "App/Foundation/NewEpisodeLogic.swift",
                "Core/API/APIError.swift",
                "Core/API/APIHTTP.swift",
                "Core/API/APIJSON.swift",
                "Core/API/Models.swift",
                "Core/API/NotificationModels.swift",
                "Core/API/Quality.swift",
                "Core/API/SessionModels.swift",
                "Core/Download/DownloadError.swift",
                "Core/Download/MediaNaming.swift",
                "Core/Live/LiveHTML.swift",
                "Core/Live/LiveHTMLEntities.swift",
                "Core/Persistence/MainWindowFrameLogic.swift",
                "Features/Browse/RecentsDismissal.swift",
                "Features/Browse/SearchPointerLogic.swift",
                "Features/Live/LiveChatScroll.swift",
                "Features/Playback/PlaybackLogic.swift",
            ]
        ),
        .testTarget(
            name: "OrangeflixLogicTests",
            dependencies: ["OrangeflixLogic"],
            path: "Tests/OrangeflixLogicTests"
        ),
    ]
)
