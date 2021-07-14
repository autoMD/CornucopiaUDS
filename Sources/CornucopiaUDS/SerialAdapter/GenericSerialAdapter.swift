//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation
import CornucopiaCore

fileprivate let logger = Cornucopia.Core.Logger(category: "GenericSerialAdapter")

public extension UDS {

    typealias RawCompletionHandler = ([UInt8]) -> ()
    typealias StringCompletionHandler = (String) -> ()

    /// A generic serial command adapter, i.e. using (relatively) low-cost _OBD2 to RS232_ adapters, such as
    /// ```markdown
    ///  *==================================================
    ///  *   VENDOR       CHIPSET     MODEL
    ///  *==================================================
    ///  * ELM ELECTRONICS ELM327    Various Clones
    ///  * OBD SOLUTIONS   STN11xx   OBDLINK SX, OBDLINK MX WiFi, etc.
    ///  * OBD SOLUTIONS   STN22xx   OBDLINK MX+, OBDLINK CX, etc.
    ///  * WGSoft.de       CUSTOM    UniCarScan 2000 (CAUTION!)
    ///  *==================================================
    /// ```
    class GenericSerialAdapter: BaseAdapter {

        private var commandProvider: StringCommandProvider
        private var commandQueue: StreamCommandQueue

        private var header = Header(0x7DF) // start out with OBD2 broadcast header
        private var replyHeader = Header(0x000) // none set
        private var stnSendFragmentation = false
        private var stnReceiveFragmentation = false
        private var desiredBusProtocol: BusProtocol = .unknown

        public enum ICType: String {
            case unknown = "???"
            case elm327  = "ELM327"
            case stn11xx = "STN11xx"
            case stn22xx = "STN22xx"
            case unicars = "UniCarScan"
        }
        public var icType = ICType.unknown {
            didSet {
                switch self.icType {
                    case .stn11xx:
                        self.maximumAutoSegmentationFrameLength = 0x7FF // STPX
                    case .stn22xx:
                        self.maximumAutoSegmentationFrameLength = 0xFFF // STPX
                    case .unicars:
                        self.maximumAutoSegmentationFrameLength = 0xFF  // automatic ISOTP
                    default:
                        self.maximumAutoSegmentationFrameLength = 0
                }
                self.mtu = self.maximumAutoSegmentationFrameLength > 0 ? self.maximumAutoSegmentationFrameLength : 8
            }
        }
        public var identification: String = "???"
        public var name: String = "Unspecified"
        public var vendor: String = "Unknown"
        public var serial: String = "Unknown"
        public var version: String = "Unknown"

        public var hasAutoSegmentation: Bool = false
        public var hasSmallFrameNoResponse: Bool = false
        public var hasFullFrameNoResponse: Bool = false
        public var canAutoFormat: Bool = true // CAN auto format is true by default for all ELM327-compatible serial adapters
        public var detectedECUs: [String] = []
        public var maximumAutoSegmentationFrameLength: Int = 0

        public init(inputStream: InputStream, outputStream: OutputStream, commandProvider: StringCommandProvider? = nil) {
            self.commandProvider = commandProvider ?? DefaultStringCommandProvider()
            self.commandQueue = StreamCommandQueue(input: inputStream, output: outputStream, termination: ">")
            super.init()
            self.commandQueue.inputConfigurationHandler = { stream in
                NotificationCenter.default.post(name: Self.CanInitializeDevice, object: self, userInfo: ["stream": stream] )
            }
            self.commandQueue.delegate = self
        }

        public override func connect(via busProtocol: BusProtocol = .auto) {
            precondition(self.state == .created, "It is only valid to call this during state .created. Current State is \(self.state)")
            self.desiredBusProtocol = busProtocol
            self.updateState(.searching)
        }

        public func sendString(_ string: String, then: @escaping(StringCompletionHandler)) {
            let timeout = self.state == .connected ? 5.0 : 10.0
            self.commandQueue.send(command: string, timeout: timeout, then: then)
        }

        public override func send(message: UDS.Message, expectedResponses: Int? = nil, then: @escaping(UDS.MessageResultHandler)) {

            var message = message

            do {
                message.bytes = try self.busProtocolEncoder!.encode(message.bytes)
            } catch {
                let failure: UDS.MessageResult = .failure(error as! UDS.Error)
                then(failure)
                return
            }

            let theSendRaw = ( message.bytes.count > 8 ) && ( self.icType == .stn11xx || self.icType == .stn22xx ) ? self.stnSendRaw : self.sendRaw

            theSendRaw(message, expectedResponses) { result in

                switch result {
                    case .failure(let error):
                        let failure = UDS.MessageResult.failure(error)
                        then(failure)

                    case .success(let responses):
                        //TODO: Change the UDS.MessageHandler into a Result<Error, UDS.Message>, else we can't convey low level errors over to the next logical layer
                        precondition(responses.count > 0, "Did not receive at least a single CAN frame")

                        let sid = self.canAutoFormat ? message.bytes[0] : message.bytes[1]

                        let responses = responses.filter { response in
                            guard response.bytes[0] == UInt8(0x03) else { return true }
                            guard response.bytes[1] == UDS.NegativeResponse else { return true }
                            guard response.bytes[2] == sid else { return true }
                            guard response.bytes[3] == UDS.NegativeResponseCode.requestCorrectlyReceivedResponsePending.rawValue else { return true }
                            let transient = responses[0].bytes[1..<4].map { String(format: "0x%02X ", $0) }.joined()
                            logger.trace("Ignoring transient UDS response \(transient)")
                            return false
                        }
                        //FIXME: Ensure all headers are the same
                        var bytes = [UInt8]()
                        responses.forEach { response in
                            bytes += response.bytes
                        }
                        do {
                            bytes = try self.busProtocolDecoder!.decode(bytes)
                            let assembled: UDS.Message = .init(id: responses.first!.id, bytes: bytes)
                            let success: UDS.MessageResult = .success(assembled)
                            then(success)
                        } catch {
                            let failure: UDS.MessageResult = .failure(error as! UDS.Error)
                            then(failure)
                        }
                }
            }
        }

        public override func sendRaw(message: UDS.Message, expectedResponses: Int? = nil, then: @escaping(UDS.MessagesResultHandler)) {

            let doSend = {
                self.send(command: .data(bytes: message.bytes), expectedResponses: expectedResponses) { response in

                    switch response {
                        case .failure(let error):
                            let failure = UDS.MessagesResult.failure(error)
                            then(failure)

                        case .success(let messages as UDS.Messages):
                            let success = UDS.MessagesResult.success(messages)
                            then(success)

                        case .success(_):
                            fatalError()
                    }
                }
            }

            //FIXME: This doesn't handle the case yet when the reply arbitration changes, but the request header stays the same
            //       Will fix this once we have async/await

            // check current header arbitration
            if self.header != message.id {
                self.send(command: .setHeader(id: message.id)) { result in
                    guard case .success(let ok as Bool) = result, ok else {
                        let failure = UDS.MessagesResult.failure(.unrecognizedCommand)
                        logger.notice("Can't set header arbitration: \(result)")
                        then(failure)
                        return
                    }
                    self.header = message.id

                    // check current receive arbitration
                    if self.replyHeader != message.reply {
                        self.send(command: .canReceiveArbitration(id: message.reply)) { result in
                            guard case .success(let ok as Bool) = result, ok else {
                                let failure = UDS.MessagesResult.failure(.unrecognizedCommand)
                                logger.notice("Can't set receive arbitration: \(result)")
                                then(failure)
                                return
                            }
                            self.replyHeader = message.reply
                            doSend()
                        }
                    } else {
                        doSend()
                    }
                }
            } else {
                doSend()
            }
        }

        override func didUpdateState() {
            switch self.state {

                case .searching:
                    self.sendInitSequence()

                case .configuring:
                    self.sendConfigSequence()

                default:
                    break
            }
        }

        public override func shutdown() {
            self.updateState(.gone)
            self.commandQueue.cleanup()
        }
    }
}

private extension UDS.GenericSerialAdapter {

    /// Sends a UDS message by using the proprietary STPX command found on STN chipsets
    private func stnSendRaw(message: UDS.Message, expectedResponses: Int? = nil, then: @escaping(UDS.MessagesResultHandler)) {

        let doSend = {
            self.send(command: .stnCanTransmitAnnounce(count: message.bytes.count), expectedResponses: expectedResponses) { announceResponse in
                switch announceResponse {
                    case .failure(let error):
                        let failure = UDS.MessagesResult.failure(error)
                        then(failure)
                    case .success(_):
                        self.send(command: .data(bytes: message.bytes), expectedResponses: expectedResponses) { actualResponse in
                            switch actualResponse {
                                case .failure(let error):
                                    let failure = UDS.MessagesResult.failure(error)
                                    then(failure)
                                case .success(let messages as UDS.Messages):
                                    let success = UDS.MessagesResult.success(messages)
                                    then(success)
                                case .success(_):
                                    fatalError()
                            }
                        }
                }
            }
        }

        //FIXME: This doesn't handle the case yet when the reply arbitration changes, but the request header stays the same
        //       Will fix this once we have async/await

        // check current header arbitration
        if self.header != message.id {
            self.send(command: .setHeader(id: message.id)) { result in
                guard case .success(let ok as Bool) = result, ok else {
                    let failure = UDS.MessagesResult.failure(.unrecognizedCommand)
                    logger.notice("Can't set header arbitration: \(result)")
                    then(failure)
                    return
                }
                self.header = message.id

                // check current receive arbitration
                if self.replyHeader != message.reply {
                    self.send(command: .canReceiveArbitration(id: message.reply)) { result in
                        guard case .success(let ok as Bool) = result, ok else {
                            let failure = UDS.MessagesResult.failure(.unrecognizedCommand)
                            logger.notice("Can't set receive arbitration: \(result)")
                            then(failure)
                            return
                        }
                        self.replyHeader = message.reply
                        doSend()
                    }
                } else {
                    doSend()
                }
            }
        } else {
            doSend()
        }
    }
}

private extension UDS.GenericSerialAdapter {

    func send(command: StringCommand, expectedResponses: Int? = nil, then: @escaping((ResponseResult)->())) {
        guard self.state != .notFound, self.state != .gone, self.state != .unsupportedProtocol else {
            logger.notice("Ignoring commands during state \(self.state)")
            return
        }

        guard let (request, responseConverter) = self.commandProvider.provide(command: command) else {
            logger.notice("Ignoring unresolved command: \(command)")
            return
        }

        var string = request
        if let expectedResponses = expectedResponses {
            string.append("\(expectedResponses)\r")
        } else {
            string.append("\r")
        }
        self.sendString(string) { stringResponse in
            let result = responseConverter(stringResponse, self)
            then(result)
        }
    }
}

extension UDS.GenericSerialAdapter: StreamCommandQueue.Delegate {

    public func streamCommandQueueDetectedEOF(_ streamCommandQueue: StreamCommandQueue) {
        guard self.commandQueue == streamCommandQueue else { return }
        self.updateState(.gone)
    }

    public func streamCommandQueueDetectedError(_ streamCommandQueue: StreamCommandQueue) {
        guard self.commandQueue == streamCommandQueue else { return }
        self.updateState(.gone)
    }
}

private extension UDS.GenericSerialAdapter {

    private static let ELM327_DEFAULT_VERSION = "OBDII to RS232 Interpreter"

    func sendInitSequence() {

        let sequence: [StringCommand] = [
            .dummy,
            .reset,
            .spaces(on: false),
            .echo(on: false),
            .linefeed(on: false),
            .showHeaders(on: true),
            .identify,
            .version1,
            .version2,
            .stnExtendedIdentify,
            .stnDeviceIdentify,
            .stnSerialNumber,
            .stnCanSegmentationTransmit(on: true),
            .unicarsIdentify,
            .setProtocol(p: self.desiredBusProtocol),
            .connect,
            .probeAutoSegmentation,
            .probeSmallFrameNoResponse,
            //NOTE: These guys seem to get non-CAN protocols into a strange state, so we better not send them for now
            //.canAutoFormat(on: false),
            //.probeFullFrameNoResponse,
            //.canAutoFormat(on: true),
        ]

        sequence.forEach { command in

            self.send(command: command) { response in

                switch command {
                    case .canAutoFormat(let on):
                        guard case .success(_) = response else { return }
                        self.canAutoFormat = on

                    case .connect:
                        guard case .success(let ecus as [String]) = response, !ecus.isEmpty else { return }
                        self.detectedECUs = ecus

                    case .dummy:
                        guard case .failure(let error) = response, error == .noResponse else {
                            self.updateState(.initializing)
                            return
                        }
                        self.updateState(.notFound)
                        self.commandQueue.flush()

                    case .identify:
                        guard case .success(let name as String) = response else { return }
                        let components = name.components(separatedBy: " ")
                        if components.count == 2 {
                            self.identification = components[0]
                            self.version = components[1]
                        } else {
                            self.identification = name
                        }
                        self.icType = .elm327

                    case .probeAutoSegmentation:
                        guard case .success(_) = response else { return }
                        self.hasAutoSegmentation = true

                    case .probeSmallFrameNoResponse:
                        guard case .success(let answer as String) = response else { return }
                        self.hasSmallFrameNoResponse = answer.isEmpty

                    case .probeFullFrameNoResponse:
                        guard case .success(_) = response else { return }
                        self.hasFullFrameNoResponse = true

                    case .stnExtendedIdentify:
                        guard case .success(let id as String) = response else { return }
                        let components = id.components(separatedBy: " ")
                        if components.count >= 3 {
                            self.identification = components[0]
                            self.version = components[1]
                        } else {
                            self.identification = id
                        }
                        self.icType = id.starts(with: "STN11") ? .stn11xx : .stn22xx
                        self.vendor = "ScanTool.net"

                    case .stnDeviceIdentify:
                        guard case .success(let id as String) = response else { return }
                        self.name = id

                    case .stnSerialNumber:
                        guard case .success(let name as String) = response else { return }
                        self.serial = name

                    case .unicarsIdentify:
                        guard case .success(let name as String) = response else { return }
                        guard name.contains("WGSoft.de") else { return }
                        self.name = name.contains("2021") ? "UniCarScan 2100" : "UniCarScan 2000"
                        self.icType = .unicars
                        self.vendor = "WGSoft.de"

                    case .version1:
                        guard case .success(let name as String) = response else { return }
                        guard name != Self.ELM327_DEFAULT_VERSION else { return }
                        self.version = name

                    default:
                        break
                }
            }
        }

        self.commandQueue.send(command: "") { _ in
            let info = Info(model: self.name, ic: self.identification, vendor: self.vendor, serialNumber: self.serial, firmwareVersion: self.version)
            self.updateInfo(info)
            self.updateState(.configuring)
        }
    }

    func sendConfigSequence() {
        let cafMode = !(!self.hasAutoSegmentation && self.hasFullFrameNoResponse)
        var sequence: [StringCommand] = []
        //BUG: At this point of time, the negotiated protocol has not been gathered yet, hence the whole sequence has no effect
        //TODO: Move .describeProtocolNumeric into the init sequence
        if self.negotiatedProtocol.isCAN {
            sequence += [
                .readVoltage,
                .canAutoFormat(on: cafMode),
                .adaptiveTiming(on: false),
            ]
        }
        #if DIAG
        sequence += [
            // <DIAG>
            .setTimeout(0xFF),
            // <DIAG OFF>
            ]
        #endif
        // Enlarge ISOTP timeouts a bit, if we can
        if self.icType == .stn11xx || self.icType == .stn22xx {
            sequence.append(.stnCanSegmentationTimeouts(flowControl: 255, consecutiveFrame: 255))
        }
        // This one _always_ needs to be there, otherwise we will never reach the `.ready` state
        sequence.append(.describeProtocolNumeric)

        sequence.forEach { command in

            self.send(command: command) { response in

                switch command {

                    /*
                    case .readVoltage:
                        guard case .success(let voltage as String) = response else { return }
                        print("voltage: \(voltage)")
                    */

                    case .canAutoFormat(let on):
                        guard case .success(let ok as Bool) = response else { return }
                        guard ok else { return }
                        self.canAutoFormat = on

                    case .describeProtocolNumeric:
                        guard case .success(let proto as UDS.BusProtocol) = response, proto != .auto else {
                            self.updateState(.unsupportedProtocol)
                            self.commandQueue.flush()
                            return
                        }
                        self.handleProtocolNegotiation(proto)

                    default:
                        break
                }
            }
        }
    }

    func handleProtocolNegotiation(_ proto: UDS.BusProtocol) {

        switch proto {

            case .unknown:
                fallthrough
            case .auto:
                fallthrough
            case .j1850_PWM:
                fallthrough
            case .j1850_VPWM:
                fallthrough
            case .iso9141_2:
                fatalError("Unsupported bus protocol \(proto)")

            case .kwp2000_5KBPS:
                fallthrough
            case .kwp2000_FAST:
                self.busProtocolEncoder = NullProtocolEncoder(maximumFrameLength: 7)
                self.busProtocolDecoder = UDS.KWP.Decoder()

            case .can_SAE_J1939:
                fallthrough
            case .user1_11B_125K:
                fallthrough
            case .user2_11B_50K:
                fallthrough
            case .can_11B_500K:
                fallthrough
            case .can_29B_500K:
                fallthrough
            case .can_11B_250K:
                fallthrough
            case .can_29B_250K:
                if self.hasAutoSegmentation {
                    self.busProtocolEncoder = NullProtocolEncoder(maximumFrameLength: self.maximumAutoSegmentationFrameLength)
                } else {
                    let maximumFrameLength = self.canAutoFormat ? 7 : 8
                    self.busProtocolEncoder = NullProtocolEncoder(maximumFrameLength: maximumFrameLength)
                }
                self.busProtocolDecoder = UDS.ISOTP.Decoder()
        }

        self.updateNegotiatedProtocol(proto)
        self.updateState(.connected)
    }
}
