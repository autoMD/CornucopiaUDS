//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
public extension UDS {

    enum BusProtocol: String, RawRepresentable, CustomStringConvertible {
        case unknown        = "?"
        // Basic
        case auto           = "0"
        case j1850_PWM      = "1"
        case j1850_VPWM     = "2"
        case iso9141_2      = "3"
        case kwp2000_5KBPS  = "4"
        case kwp2000_FAST   = "5"
        case can_11B_500K   = "6"
        case can_29B_500K   = "7"
        case can_11B_250K   = "8"
        case can_29B_250K   = "9"
        case can_SAE_J1939  = "A"
        case user1_11B_125K = "B"
        case user2_11B_50K  = "C"
        //FIXME: Shall we add the STN-specific protocol variants here?

        var numberOfHeaderCharacters: Int { self.broadcastHeader.count }

        var broadcastHeader: String {
            switch self {
                case .can_11B_250K:
                    fallthrough
                case .can_11B_500K:
                    return "7DF"
                case .can_29B_250K:
                    fallthrough
                case .can_29B_500K:
                    return "18DB33F1"
                case .kwp2000_5KBPS:
                    fallthrough
                case .kwp2000_FAST:
                    return "81F110"
                default:
                    preconditionFailure("Not yet implemented")
            }
        }

        var isKWP: Bool { self == .kwp2000_FAST || self == .kwp2000_5KBPS }
        var isCAN: Bool { 6...0xD ~= UInt8(self.rawValue, radix: 16) ?? 0 }

        public var description: String { "OBD2_OBD_BUSPROTO_\(self.rawValue)".uds_localized }
    }
}

