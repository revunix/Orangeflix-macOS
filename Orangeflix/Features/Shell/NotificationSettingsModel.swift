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
    /// Whether the data is being loaded.
    private(set) var isLoading = false
    /// The error of the last attempt.
    private(set) var error: String?
    /// The message of the last successful change.
    private(set) var message: String?

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

    /// Whether the event is on for the account.
    func isEnabled(_ key: String) -> Bool {
        preferences?.preference(for: key)?.enabled ?? false
    }

    /// Whether the event may be changed by the account.
    func isConfigurable(_ key: String) -> Bool {
        catalog.first { $0.key == key }?.configurable ?? true
    }

    /// Loads the catalog, the preferences and the devices.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await app.ensureSession()
            async let events = app.services.api.notificationEvents()
            async let prefs = app.services.api.notificationPreferences()
            async let list = app.services.api.notificationDevices()
            catalog = try await events.events
            preferences = try await prefs
            devices = try await list
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.record("Die Mitteilungseinstellungen konnten nicht geladen werden: \(error.localizedDescription)", error: true)
        }
    }

    /// Switches one event of the catalog on or off.
    func setEvent(_ key: String, enabled: Bool) async {
        do {
            preferences = try await app.services.api.updateNotificationEvent(key, enabled: enabled)
            error = nil
            message = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }

    /// Switches one channel of the account on or off.
    func setChannel(_ channel: String, enabled: Bool) async {
        do {
            let update = NotificationPreferenceUpdate(
                channels: [channel: NotificationChannelUpdate(enabled: enabled)])
            preferences = try await app.services.api.updateNotificationPreferences(update)
            error = nil
            message = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
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
