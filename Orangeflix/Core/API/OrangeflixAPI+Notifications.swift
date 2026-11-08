import Foundation

/// The notification endpoints. They carry what the account wants to hear
/// about and which devices the app may reach.
extension OrangeflixAPI {
    /// The catalog of the events the app can notify about.
    func notificationEvents() async throws -> NotificationEventCatalog {
        let data = try await requestData("GET", "notifications/events")
        return try NotificationModels.catalog(from: data)
    }

    /// The effective notification preferences of the account: the defaults of
    /// the catalog and the choices the account made.
    func notificationPreferences() async throws -> NotificationPreferences {
        let data = try await requestData("GET", "notifications/preferences")
        return try NotificationModels.preferences(from: data)
    }

    /// Changes the notification preferences; the parts that are nil keep their
    /// value.
    func updateNotificationPreferences(_ update: NotificationPreferenceUpdate) async throws -> NotificationPreferences {
        let body = try APIJSON.encode(update)
        let data = try await requestData("PATCH", "notifications/preferences", body: body)
        return try NotificationModels.preferences(from: data)
    }

    /// Changes one event type and leaves the others alone.
    func updateNotificationEvent(_ eventType: String, enabled: Bool? = nil,
                                 channels: [String: Bool]? = nil) async throws -> NotificationPreferences {
        let body = try APIJSON.encode(NotificationEventUpdate(enabled: enabled, channels: channels))
        let data = try await requestData("PATCH",
                                        "notifications/preferences/events/" + APIHTTP.pathEscape(eventType),
                                        body: body)
        return try NotificationModels.preferences(from: data)
    }

    /// The devices registered for the push notifications.
    func notificationDevices() async throws -> [NotificationDevice] {
        let data = try await requestData("GET", "notifications/devices")
        return try NotificationModels.devices(from: data)
    }

    /// Removes a device from the list.
    func removeNotificationDevice(_ deviceID: String) async throws {
        _ = try await requestData("DELETE", "notifications/devices/" + APIHTTP.pathEscape(deviceID))
    }

    /// Sends a test notification. It follows the current preferences, so
    /// nothing goes out on a channel that is switched off.
    func sendTestNotification() async throws -> NotificationTestResult {
        let data = try await requestData("POST", "notifications/test")
        return try NotificationModels.testResult(from: data)
    }

    /// Re-enables the delivery of the e-mail after an unsubscribe. Changing
    /// the preferences does not do it.
    func resubscribeEmailNotifications() async throws {
        _ = try await requestData("POST", "notifications/email/resubscribe")
    }
}
