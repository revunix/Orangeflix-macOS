import Foundation
import Observation

/// The notifications of the account: the catalog of the events, the choices
/// of the account and the devices the app may reach.
@MainActor @Observable final class NotificationSettingsModel {
    @ObservationIgnored let app: AppModel

    /// Every event the app can notify about.
    private(set) var catalog: [NotificationEvent] = []
    /// The effective preferences of the account.
    private(set) var preferences: NotificationPreferences?
    /// The devices registered for the push notifications.
    private(set) var devices: [NotificationDevice] = []
    /// Whether the server has successfully returned a device list.
    private(set) var devicesLoaded = false
    /// The error of the last attempt to read the devices.
    private(set) var devicesError: String?
    /// Whether the data is being loaded.
    private(set) var isLoading = false
    /// The error of the last attempt.
    private(set) var error: String?
    /// The message of the last successful change.
    private(set) var message: String?
    /// The account the catalog belongs to.
    @ObservationIgnored private var loadedGeneration: Int?
    /// The channel the user just chose. The switch shows it at once and
    /// keeps it until the server has stored that same value.
    private(set) var wantedChannels: [String: Bool] = [:]
    /// The event the user just chose, for the same reason.
    private(set) var wantedEvents: [String: Bool] = [:]
    /// Channels whose change is on its way. A newer choice waits and is sent
    /// right after, so a fast second click is not dropped.
    @ObservationIgnored private var sendingChannels: Set<String> = []
    /// Events whose change is on its way.
    @ObservationIgnored private var sendingEvents: Set<String> = []

    /// Whether the catalog is missing or belongs to another account.
    var needsLoad: Bool {
        preferences == nil || loadedGeneration != app.accountGeneration
    }

    init(app: AppModel) {
        self.app = app
    }

    /// The channels of the account and their state.
    var channels: [String: Bool] {
        preferences?.channels ?? [:]
    }

    /// The channels the catalog names, in the order of the catalog.
    var channelNames: [String] {
        var names: [String] = []
        for event in catalog {
            for channel in event.channels where !names.contains(channel) {
                names.append(channel)
            }
        }
        for name in channels.keys where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// The German name of a channel.
    static func channelName(_ channel: String) -> String {
        switch channel.lowercased() {
        case "push": "Push"
        case "email", "mail": "E-Mail"
        case "inapp", "in_app": "In der App"
        case "chat": "Chat"
        default: channel
        }
    }

    /// Whether the event is on for the account. A choice that is still on
    /// its way counts, so the switch does not jump back.
    func isEnabled(_ key: String) -> Bool {
        wantedEvents[key] ?? preferences?.preference(for: key)?.enabled ?? false
    }

    /// Whether the channel is on. A choice that is still on its way counts.
    func isChannelOn(_ channel: String) -> Bool {
        wantedChannels[channel] ?? channels[channel] ?? false
    }

    /// Whether the event may be changed by the account.
    func isConfigurable(_ key: String) -> Bool {
        catalog.first { $0.key == key }?.configurable ?? true
    }

    /// Loads the catalog, the preferences and the devices.
    func load() async {
        guard !isLoading else { return }
        // A new account clears the old catalog first. A later visit of the
        // same account does not: the page asks only when `needsLoad`.
        if loadedGeneration != app.accountGeneration {
            loadedGeneration = app.accountGeneration
            catalog = []
            preferences = nil
            devices = []
            devicesLoaded = false
            devicesError = nil
            message = nil
            wantedChannels = [:]
            wantedEvents = [:]
        }
        isLoading = true
        error = nil
        devicesError = nil
        defer { isLoading = false }
        do {
            try await app.ensureSession()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            devicesError = error.localizedDescription
            app.record("Die Mitteilungseinstellungen konnten nicht geladen werden: \(error.localizedDescription)", error: true)
            return
        }

        async let events = app.services.api.notificationEvents()
        async let prefs = app.services.api.notificationPreferences()
        async let list = app.services.api.notificationDevices()
        do {
            devices = try await list
            devicesLoaded = true
        } catch is CancellationError {
            return
        } catch {
            devicesError = error.localizedDescription
            app.record("Die Push-Geräte konnten nicht geladen werden: \(error.localizedDescription)", error: true)
        }
        do {
            catalog = try await events.events
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.record("Die Mitteilungsereignisse konnten nicht geladen werden: \(error.localizedDescription)", error: true)
        }
        do {
            preferences = try await prefs
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.record("Die Mitteilungseinstellungen konnten nicht geladen werden: \(error.localizedDescription)", error: true)
        }
    }

    /// Switches one event of the catalog on or off. The switch shows the
    /// choice at once. A second click while the first is on its way is sent
    /// afterwards; a refusal returns the switch to the server.
    func setEvent(_ key: String, enabled: Bool) async {
        var next = wantedEvents
        next[key] = enabled
        wantedEvents = next
        await sendEvent(key)
    }

    /// Switches one channel of the account on or off, the same way.
    func setChannel(_ channel: String, enabled: Bool) async {
        var next = wantedChannels
        next[channel] = enabled
        wantedChannels = next
        await sendChannel(channel)
    }

    /// Sends the newest wanted state of one event until the server has it.
    private func sendEvent(_ key: String) async {
        guard sendingEvents.insert(key).inserted else { return }
        defer { sendingEvents.remove(key) }
        while let wanted = wantedEvents[key] {
            do {
                preferences = try await app.services.api.updateNotificationEvent(key, enabled: wanted)
                error = nil
                message = nil
                if wantedEvents[key] == wanted {
                    var next = wantedEvents
                    next[key] = nil
                    wantedEvents = next
                }
            } catch is CancellationError {
                return
            } catch {
                // A newer click replaced this value while it was failing.
                // That one still has to go out; dropping it here is what
                // made a fast second click disappear.
                guard wantedEvents[key] == wanted else { continue }
                var next = wantedEvents
                next[key] = nil
                wantedEvents = next
                self.error = error.localizedDescription
                app.show(error.localizedDescription, error: true)
                return
            }
        }
    }

    /// Sends the newest wanted state of one channel until the server has it.
    private func sendChannel(_ channel: String) async {
        guard sendingChannels.insert(channel).inserted else { return }
        defer { sendingChannels.remove(channel) }
        while let wanted = wantedChannels[channel] {
            do {
                let update = NotificationPreferenceUpdate(
                    channels: [channel: NotificationChannelUpdate(enabled: wanted)])
                preferences = try await app.services.api.updateNotificationPreferences(update)
                error = nil
                message = nil
                if wantedChannels[channel] == wanted {
                    var next = wantedChannels
                    next[channel] = nil
                    wantedChannels = next
                }
            } catch is CancellationError {
                return
            } catch {
                guard wantedChannels[channel] == wanted else { continue }
                var next = wantedChannels
                next[channel] = nil
                wantedChannels = next
                self.error = error.localizedDescription
                app.show(error.localizedDescription, error: true)
                return
            }
        }
    }

    /// Removes a device from the list.
    func removeDevice(_ deviceID: String) async {
        do {
            try await app.services.api.removeNotificationDevice(deviceID)
            error = nil
            devices.removeAll { $0.deviceID == deviceID }
            app.show("Das Gerät ist abgemeldet.")
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }

    /// Sends a test notification.
    func sendTest() async {
        do {
            let result = try await app.services.api.sendTestNotification()
            error = nil
            if result.total > 0 {
                app.show("Die Testmitteilung ist unterwegs (\(result.total)).")
            } else {
                app.show("Die Testmitteilung ging nicht raus; die Kanäle sind ausgeschaltet.")
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }

    /// Re-enables the delivery of the e-mail after an unsubscribe.
    func resubscribeEmail() async {
        do {
            try await app.services.api.resubscribeEmailNotifications()
            error = nil
            app.show("Der E-Mail-Versand ist wieder an.")
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }
}
