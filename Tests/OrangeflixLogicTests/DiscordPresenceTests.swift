import Foundation
import Testing
@testable import OrangeflixLogic

@Suite("Discord Rich Presence")
struct DiscordPresenceTests {
    @Test("builds Spotify-style watching activity with progress timestamps and episode link")
    func episodeActivity() {
        let now = Date(timeIntervalSince1970: 1_760_000_120)
        let snapshot = DiscordPresenceLogic.Snapshot(
            kind: .episode,
            identifier: "pk322",
            title: "Herbstkino-Spezial",
            detail: "Pantoffelkino · Folge 322",
            chapterTitle: "Neustarts",
            thumbURL: "https://massengeschmack.tv/img/pk322.jpg",
            position: 120,
            duration: 3_600,
            isPaused: false,
            showsLinkButton: true
        )

        let activity = DiscordPresenceLogic.activity(from: snapshot, now: now)
        #expect(activity.type == 3)
        #expect(activity.details == "Herbstkino-Spezial")
        #expect(activity.state == "Pantoffelkino · Folge 322 · Neustarts")
        #expect(activity.timestamps?.start == 1_760_000_000)
        #expect(activity.timestamps?.end == 1_760_003_600)
        #expect(activity.assets?.largeImage == "https://massengeschmack.tv/img/pk322.jpg")
        #expect(activity.assets?.smallImage == "https://orangeflix.de/orangeflix.png")
        #expect(activity.buttons == [.init(label: "Folge öffnen", url: "https://orangeflix.de/clip/pk322")])
    }

    @Test("paused playback drops timestamps and marks paused state")
    func pausedActivity() {
        let snapshot = DiscordPresenceLogic.Snapshot(
            kind: .episode,
            identifier: "fktv237",
            title: "Folge 237",
            detail: "Fernsehkritik-TV",
            position: 45,
            duration: 1_800,
            isPaused: true
        )

        let activity = DiscordPresenceLogic.activity(from: snapshot)
        #expect(activity.timestamps == nil)
        #expect(activity.state.hasPrefix("Pausiert · "))
        #expect(activity.assets?.smallText == "Pausiert")
    }

    @Test("livestream points to orangeflix.de/live with elapsed start timestamp")
    func liveActivity() {
        let started = Date(timeIntervalSince1970: 1_760_000_000)
        let now = Date(timeIntervalSince1970: 1_760_000_600)
        let snapshot = DiscordPresenceLogic.Snapshot(
            kind: .live,
            identifier: "live",
            title: "Sondersendung Live",
            detail: "Live",
            isPaused: false,
            showsLinkButton: true
        )

        let activity = DiscordPresenceLogic.activity(from: snapshot, now: now, liveStartedAt: started)
        #expect(activity.state == "Gerade live")
        #expect(activity.timestamps?.start == 1_760_000_000)
        #expect(activity.timestamps?.end == nil)
        #expect(activity.buttons == [.init(label: "Livestream ansehen", url: "https://orangeflix.de/live")])
    }

    @Test("only triggers updates on state changes or seeks beyond drift threshold")
    func driftDetection() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let initial = DiscordPresenceLogic.Snapshot(
            kind: .episode, identifier: "pk1", title: "Test", detail: "Show",
            position: 10, duration: 600
        )
        var steady = initial
        steady.position = 15.2
        #expect(!DiscordPresenceLogic.shouldSendUpdate(
            previous: (initial, t0), current: steady, now: t0.addingTimeInterval(5)
        ))

        var scrubbed = initial
        scrubbed.position = 90
        #expect(DiscordPresenceLogic.shouldSendUpdate(
            previous: (initial, t0), current: scrubbed, now: t0.addingTimeInterval(5)
        ))
    }

    @Test("encodes and decodes little-endian IPC frames and null clear activity")
    func ipcFraming() throws {
        let clearPacket = try DiscordIPCFrame.setActivity(nil, pid: 42, nonce: "n1")
        let header = DiscordIPCFrame.decodeHeader(clearPacket.prefix(8))
        #expect(header?.opcode == .frame)
        #expect(header?.length == clearPacket.count - 8)
        let json = String(decoding: clearPacket.dropFirst(8), as: UTF8.self)
        #expect(json.contains("\"SET_ACTIVITY\""))
        #expect(json.contains("\"activity\":null"))
    }

    @Test("uses fixed Orangeflix Discord Application ID")
    func fixedClientID() {
        #expect(DiscordPresenceLogic.clientID == "1569859656023670946")
    }
}
