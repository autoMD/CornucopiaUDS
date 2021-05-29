//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation

public extension UDS {

    enum KWP {
        public static var HeaderLength: Int = "87F110".count
    }
}

public extension UDS.KWP {

    /// A KWPISOTP encoder, see ISO14230-4
    final class Encoder: UDS.BusProtocolEncoder {

        public init() { }

        /// Encode a byte stream by inserting the appropriate framing control bytes as per ISOTP
        public func encode(_ bytes: [UInt8]) throws -> [UInt8] {
            throw UDS.Error.encoderError(string: "KWP encoding not yet implemented")
        }
    }

    /// A KWP decoder, see ISO14230-4
    final class Decoder: UDS.BusProtocolDecoder {

        public init() { }

        /// Decode a byte stream consisting on multiple individual concatenated frames by removing the protocol framing bytes as per KWP
        public func decode(_ bytes: [UInt8]) throws -> [UInt8] {
            throw UDS.Error.decoderError(string: "KWP decoding not yet implemented")
        }
    }
}
