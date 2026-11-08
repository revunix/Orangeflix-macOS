import Foundation
import Testing

@testable import OrangeflixLogic

@Suite("Push device list")
struct NotificationDeviceTests {
    @Test("reads devices in a server response")
    func readsDevices() throws {
        let data = Data(#"{"devices":[{"deviceId":"abc","deviceName":"Phone","platform":"ios"}]}"#.utf8)
        let devices = try NotificationModels.devices(from: data)
        #expect(devices.count == 1)
        #expect(devices.first?.deviceID == "abc")
        #expect(devices.first?.name == "Phone")
    }

    @Test("accepts an empty device list")
    func emptyList() throws {
        #expect(try NotificationModels.devices(from: Data(#"{"devices":[]}"#.utf8)).isEmpty)
    }

    @Test("does not mistake an unknown response for an empty list")
    func unknownResponse() {
        #expect(throws: APIError.self) {
            try NotificationModels.devices(from: Data(#"{"result":{}}"#.utf8))
        }
    }

    @Test("does not silently discard devices without an identifier")
    func missingDeviceID() {
        #expect(throws: APIError.self) {
            try NotificationModels.devices(from: Data(#"{"devices":[{"name":"Phone"}]}"#.utf8))
        }
    }
}
