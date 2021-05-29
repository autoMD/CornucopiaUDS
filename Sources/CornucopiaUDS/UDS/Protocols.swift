//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
/*
import CornucopiaCore

private var logger = Cornucopia.Core.Logger(category: "ISOTP")

public protocol _UDSTransportProtocol {

    func send(message: UDS.Message, then: @escaping(UDS.MessageResultHandler))
}

public extension UDS {

    typealias TransportProtocol = _UDSTransportProtocol

    class ISOTP: TransportProtocol {

        enum FlowStatus: UInt8 {
            case clearToSend    = 0x30
            case wait           = 0x31
            case overflow       = 0x32
        }

        struct ACK {
            let flowStatus: FlowStatus
            let blockSize: UInt8
            let separationTime: Double

            init?(bytes: [UInt8]) {
                guard let fs = FlowStatus(rawValue: bytes[0]) else { return nil }
                self.flowStatus = fs
                self.blockSize = bytes[1]
                self.separationTime = 1000.0 * Double(bytes[2])
            }
        }

        public enum Mode {
            case full           // encode and decode, assuming the adapter is configured via ATCAF0 and has _no_ automatic ISOTP segmentation
            case decodeOnly     // decode-only, assuming the adapter is configured via ATCAF1 and has automatic ISOTP segmentation for TX
            case passthrough    // encode and decode, assuming the adapter is configured via ATCAF1 and automatic ISOTP segmentation for TX and RX
        }

        private let adapter: UDS.Adapter
        private let mode: Mode

        public init(adapter: UDS.Adapter, mode: Mode = .full) {
            self.adapter = adapter
            self.mode = mode
        }

        public func send(message: UDS.Message, then: @escaping(UDS.MessageResultHandler)) {

            guard self.mode == .full else {
                // nothing to do for sending in decode and passthrough mode
                self.sendFrame(message: message, then: then)
                return
            }

            preconditionFailure(".full mode not supported at this point of time")

            let encodedMessage = self.encode(message: message)
            guard encodedMessage.bytes.count >= 8 else {
                self.sendFrame(message: encodedMessage, then: then)
                return
            }
            self.sendFirstFrame(message: encodedMessage, then: then)
        }

        private func sendFirstFrame(message: UDS.Message, then: @escaping(UDS.MessageResultHandler)) {

            let firstFrame = (message.header, Array(message.bytes[0..<8]))
            self.sendFrame(message: firstFrame) { result in

                guard case .success(let answer) = result else {
                    then(result)
                    return
                }

                guard let ack = ACK(bytes: answer.bytes) else { fatalError("Not an FC ACK") }
                var nextMessage = message
                nextMessage.bytes.removeFirst(8)
                let partialMessage = (header: message.header, bytes: nextMessage.bytes)
                self.sendConsecutive(message: partialMessage, allowUnacknowledged: ack.blockSize, then: then)
            }
        }

        private func sendConsecutive(message: UDS.Message, allowUnacknowledged: UInt8, then: @escaping(UDS.MessageResultHandler)) {

            var message = message
            let count = min(message.bytes.count, 8)
            let frame = (message.header, Array(message.bytes[0..<count]))
            message.bytes.removeFirst(count)
            let nextFrame = (message.header, Array(message.bytes))

            var expectedResponses: Int? = nil
            if message.bytes.count > 0 && allowUnacknowledged > 0 {
                expectedResponses = 0
            }

            self.sendFrame(message: frame, expectedResponses: expectedResponses) { result in

                guard case .success(let answer) = result else {
                    then(result)
                    return
                }

                guard message.bytes.isEmpty else {
                    // there are still pending frames…
                    guard let ack = ACK(bytes: answer.bytes) else { fatalError("Not an FC ACK") }
                    self.sendConsecutive(message: nextFrame, allowUnacknowledged: allowUnacknowledged - 1, then: then)
                    return
                }
                // we expect this to be the final answer
                let result = UDS.MessageResult.success(answer)
                then(result)
            }
        }

        // Sends and receive, if necessary, assembling multiple responses into one
        private func send(message: UDS.Message, expectedResponses: Int? = nil, then: @escaping(UDS.MessageResultHandler)) {
            self.adapter.sendRaw(message: message, expectedResponses: expectedResponses) { result in

                switch result {
                    case .failure(let error):
                        let failure = UDS.MessageResult.failure(error)
                        then(failure)

                    case .success(let responses):
                        //TODO: Change the UDS.MessageHandler into a Result<Error, UDS.Message>, else we can't convey low level errors over to the next logical layer
                        precondition(responses.count > 0, "Did not receive at least a single CAN frame")

                        let sid = self.mode == .full ? message.bytes[1] : message.bytes[0]

                        let responses = responses.filter { response in
                            guard response.bytes[0] == UInt8(0x03) else { return true }
                            guard response.bytes[1] == UDS.NegativeResponse else { return true }
                            guard response.bytes[2] == sid else { return true }
                            guard response.bytes[3] == UDS.NegativeResponseCode.requestCorrectlyReceivedResponsePending.rawValue else { return true }
                            let transient = responses[0].bytes[1..<4].map { String(format: "0x%02X ", $0) }.joined()
                            logger.debug("Ignoring transient UDS response \(transient)")
                            return false
                        }
                        //FIXME: Ensure all headers are the same
                        var bytes = [UInt8]()
                        responses.forEach { response in
                            bytes += response.bytes
                        }
                        let assembled = (header: responses.first!.header, bytes: bytes)
                        let decoded = self.decode(message: assembled)
                        let success = UDS.MessageResult.success(decoded)
                        then(success)
                }
            }
        }
    }
}

//MARK: - ISOTP Encoding
private extension UDS.ISOTP {

    func encode(message: UDS.Message) -> UDS.Message {
        precondition(1...4095 ~= message.bytes.count, "Total payload size needs to be 0 < n < 4096")
        let framedPayload = message.bytes.count < 7 ? self.encodeSingleFrame(payload: message.bytes) : self.encodeMultiFrame(payload: message.bytes)
        return (header: message.header, bytes: framedPayload)
    }

    // encodes bytes to a single frame
    func encodeSingleFrame(payload: [UInt8]) -> [UInt8] {
        let pci = UInt8(payload.count)
        return [pci] + payload
    }

    // encodes bytes to multiple frames
    func encodeMultiFrame(payload: [UInt8]) -> [UInt8] {
        var payload = payload
        let pci = 0x1000 | UInt16(payload.count)
        let pciHi = UInt8(pci >> 8 & 0xFF)
        let pciLo = UInt8(pci & 0xFF)
        let ff = [pciHi, pciLo] + payload[0..<6]
        payload.removeFirst(6)
        var bytes = ff
        var cfPci = UInt8(0x21)
        while payload.count > 0 {
            let cfPayloadCount = min(7, payload.count)
            let cf = [cfPci] + payload[0..<cfPayloadCount]
            payload.removeFirst(cfPayloadCount)
            bytes += cf
            cfPci = cfPci + 1
            if cfPci == 0x30 {
                #if true
                cfPci = 0x20
                #else
                cfPci = 0x21 //NOTE: If you want to force the ECU not responding, you might try setting the PCI to 0x21 here, thus rendering the protocol invalid
                #endif
            }
        }
        return bytes
    }
}

//MARK: - ISOTP Decoding
private extension UDS.ISOTP {

    func decode(message: UDS.Message) -> UDS.Message {

        let unframedPayload = message.bytes.count < 9 ? self.decodeSingleFrame(payload: message.bytes) : self.decodeMultiFrame(payload: message.bytes)
        return (header: message.header, bytes: unframedPayload)
    }

    // decodes a single frame to bytes
    func decodeSingleFrame(payload: [UInt8]) -> [UInt8] {
        let pci = payload[0]
        guard pci != 0x30 else {
            // Looks like an FC ACK frame, just pass this through
            return payload
        }
        guard pci < 0x08 else {
            logger.error("Corrupt single frame with PCI \(pci, radix: .hex, prefix: true) detected")
            //FIXME: Handle gracefully by throwing an exception
            fatalError()
        }
        let border = Int(pci)
        return Array(payload[1...border])
    }

    // decodes multiple frames to bytes
    func decodeMultiFrame(payload: [UInt8]) -> [UInt8] {
        var payload = payload
        let pciHi = payload[0]
        assert(pciHi & 0xF0 == 0x10, "Corrupt FF detected")
        let pciLo = payload[1]
        let pci = UInt16(pciHi) << 8 | UInt16(pciLo)
        var length = Int(pci & 0xFFF)
        var bytes = payload[2..<8]
        payload.removeFirst(8)
        var expectedCfPci: UInt8 = 0x21
        while payload.count > 0 {
            let cfPci = payload.removeFirst()
            assert(cfPci == expectedCfPci, "Corrupt CF detected")
            let expectedPayload = length - bytes.count
            let cfPayloadCount = min(8, payload.count, expectedPayload)
            bytes += payload[1..<cfPayloadCount]
            payload.removeFirst(payload.count)
            expectedCfPci += 1
            if expectedCfPci == 0x30 {
                expectedCfPci = 0x20
            }
        }
        return Array(bytes)
    }
}
*/
