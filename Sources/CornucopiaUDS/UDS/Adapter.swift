//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation

public extension UDS {

    //NOTE: Ideally this would have been a protocol with a default implementation, but protocols are way too limited in Swift
    class Adapter {

        public struct Info {
            public let model: String
            public let ic: String
            public let vendor: String
            public let serialNumber: String
            public let firmwareVersion: String
        }

        /// Sent after a `state` change.
        public static let DidUpdateState = Notification.Name("DidUpdateState")

        /// Sent before the first I/O happens over the corresponding device.
        /// For devices that communicate over streams, this is typically when the output stream has been
        /// successfully opened. Use this notification as a chance to configure the device in a non-standard
        /// way, e.g. adjust the baudrate for USB TTYs, or send custom initialization commands. A device-specific handle
        /// (e.g., said output stream) is delivered as the notification `object`.
        public static let CanInitializeDevice = Notification.Name("CanInitializeDevice")

        /// Sent after the first (positive or negative) response from an ECU has been received.
        public static let DidNegotiateProtocol = Notification.Name("DidNegotiateProtocol")

        /// Sent after a request/response command cycle has been completed. This notification is sent on a background queue.
        public static let DidCompleteCommand = Notification.Name("DidCompleteCommand")

        /// The adapter state
        public enum State {
            case created // => searching
            case searching // => notFound || initializing
            case notFound // final
            case initializing // => error || configuring
            case configuring // => error || connected || unsupportedProtocol
            case connected // => gone
            case unsupportedProtocol
            case gone
        }

        public private(set) var state: State = .created {
            didSet {
                NotificationCenter.default.post(name: Self.DidUpdateState, object: self)
            }
        }

        public private(set) var negotiatedProtocol: UDS.BusProtocol = .unknown {
            didSet {
                NotificationCenter.default.post(name: Self.DidNegotiateProtocol, object: self)
            }
        }

        public private(set) var batteryVoltage: Measurement<UnitPower>? = nil

        public internal(set) var busProtocolEncoder: BusProtocolEncoder? = nil
        public internal(set) var busProtocolDecoder: BusProtocolDecoder? = nil

        public private(set) var info: Info? = nil
        public private(set) var numberOfHeaderCharacters: Int = 0
        public internal(set) var mtu: Int = 0

        public func connect(via protocol: BusProtocol = .auto) {
            fatalError("pure virtual")
        }
        public func sendRaw(message: UDS.Message, expectedResponses: Int? = nil, then: @escaping(MessagesResultHandler)) {
            fatalError("pure virtual")
        }
        public func send(message: UDS.Message, expectedResponses: Int? = nil, then: @escaping(MessageResultHandler)) {
            fatalError("pure virtual")
        }
        public func shutdown() {
            fatalError("pure virtual")
        }
    }
}

internal extension UDS.Adapter {

    func updateState(_ next: State) {
        guard self.state != next else {
            return
        }
        self.state = next
    }

    func updateNegotiatedProtocol(_ proto: UDS.BusProtocol) {
        precondition(self.negotiatedProtocol == .unknown, "The negotiated bus protocol can only be set once")
        precondition(self.busProtocolEncoder != nil, "Upon protocol negotiation, you need to install a bus protocol encoder")
        precondition(self.busProtocolDecoder != nil, "Upon protocol negotiation, you need to install a bus protocol decoder")
        self.negotiatedProtocol = proto
        self.numberOfHeaderCharacters = proto.numberOfHeaderCharacters
    }

    func updateInfo(_ info: Info) {
        self.info = info
    }
}

public extension UDS {

    class BaseAdapter: Adapter {

        override init() {
            super.init()
            NotificationCenter.default.addObserver(forName: Self.DidUpdateState, object: self, queue: nil) { _ in self.didUpdateState() }
        }

        func didUpdateState() { }
    }
}
