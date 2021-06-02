//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation

public extension UDS {

    /// An encapsulation of a UDS Diagnostic Session, providing high level calls as per ISO14229-1:2020
    class DiagnosticSession {

        public typealias TypedResult<SuccessfulResponseType> = Result<SuccessfulResponseType, UDS.Error>
        public typealias TypedResultHandler<SuccessfulResponseType> = (TypedResult<SuccessfulResponseType>) -> ()

        let id: UDS.Header
        let reply: UDS.Header
        let pipeline: UDS.Pipeline

        public var activeTransferProgress: Progress?

        public init(with id: UDS.Header, replyAddress: UDS.Header? = nil, via: UDS.Pipeline) {
            self.id = id
            self.reply = replyAddress ?? id | 0x08
            self.pipeline = via
        }

        /// Clear stored diagnostic trouble codes
        public func clearDiagnosticInformation(groupOfDTC: GroupOfDTC, then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {
            self.request(service: .clearDiagnosticInformation(groupOfDTC: groupOfDTC), then: then)
        }

        /// Reset the ECU
        public func ecuReset(type: EcuResetType, then: @escaping(TypedResultHandler<UDS.EcuResetResponse>)) {
            self.request(service: .ecuReset(type: type), then: then)
        }

        /// Start a (non-default) diagnostic session
        public func start(type: DiagnosticSessionType, then: @escaping(TypedResultHandler<UDS.DiagnosticSessionResponse>)) {
            self.request(service: .diagnosticSessionControl(session: type), then: then)
        }

        /// Request the security access seed
        public func requestSeed(securityLevel: UDS.SecurityLevel, then: @escaping(TypedResultHandler<UDS.SecurityAccessSeedResponse>)) {
            self.request(service: .securityAccessRequestSeed(level: securityLevel), then: then)
        }

        /// Send the security access key
        public func sendKey(securityLevel: UDS.SecurityLevel, key: [UInt8], then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {
            self.request(service: .securityAccessSendKey(level: securityLevel, key: key), then: then)
        }

        /// Read data record
        public func readData(byIdentifier: UDS.DataIdentifier, then: @escaping(TypedResultHandler<UDS.DataIdentifierResponse>)) {
            self.request(service: .readDataByIdentifier(id: byIdentifier), then: then)
        }

        /// Write data record
        public func writeData(byIdentifier: UDS.DataIdentifier, dataRecord: DataRecord, then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {
            self.request(service: .writeDataByIdentifier(id: byIdentifier, drec: dataRecord), then: then)
        }

        /// Initiate a block transfer (TESTER -> ECU)
        public func requestDownload(compression: UInt8, encryption: UInt8, address: [UInt8], length: [UInt8], then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {
            self.request(service: .requestDownload(compression: compression, encryption: encryption, address: address, length: length), then: then)
        }

        /// Trigger a routine
        public func routineControl(type: UDS.RoutineControlType, identifier: UDS.RoutineIdentifier, optionRecord: DataRecord = [], then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {
            self.request(service: .routineControl(type: type, id: identifier, rcor: optionRecord), then: then)
        }

        /// Transfer a single data block. The maximum data length is adapter-specific.
        public func transferBlock(_ block: UInt8, data: Data, then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {
            self.request(service: .transferData(bsc: block, trpr: [UInt8](data)), then: then)
        }

        /// Finish a block transfer
        public func transferExit(_ optionRecord: DataRecord = [], then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {
            self.request(service: .requestTransferExit(trpr: optionRecord), then: then)
        }

        /// Higher level data transfer
        public func transferData(_ data: Data, then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {
            self.activeTransferProgress = .init(totalUnitCount: Int64(data.count))
            self.transferNextBlock(1, chunkSize: self.pipeline.adapter.mtu - 2, remainingData: data, then: then)
        }
    }
}

internal extension UDS.DiagnosticSession {

    func request<T: UDS.ConstructableViaMessage>(service: UDS.Service, then: @escaping(TypedResultHandler<T>)) {
        self.pipeline.send(to: self.id, reply: self.reply, service: service) { result in

            switch result {

                case .failure(let error):
                    then(.failure(error))

                case .success(let message) where message.bytes[0] == UDS.NegativeResponse:
                    let negativeResponseCode = UDS.NegativeResponseCode(rawValue: message.bytes[2]) ?? .undefined
                    then(.failure(.udsNegativeResponse(code: negativeResponseCode)))

                case .success(let message):
                    let response = T(message: message)
                    then(Result.success(response))
            }
        }
    }

    func transferNextBlock(_ block: UInt8, chunkSize: Int, remainingData: Data, then: @escaping(TypedResultHandler<UDS.GenericResponse>)) {

        let chunk = remainingData.prefix(chunkSize)
        self.transferBlock(block, data: chunk) { result in
            guard case .success(_) = result else {
                self.activeTransferProgress = nil
                then(result)
                return
            }
            //FIXME: Sanity-Check: Check whether the acknowledged block is actually the one we just have sent
            self.activeTransferProgress!.completedUnitCount += Int64(chunk.count)
            let nextBlock = block == 0xFF ? 0x00 : block + 1
            var nextRemainingData = remainingData
            nextRemainingData.removeFirst(chunk.count)
            guard !nextRemainingData.isEmpty else {
                then(result)
                return
            }
            self.transferNextBlock(nextBlock, chunkSize: chunkSize, remainingData: nextRemainingData, then: then)
        }
    }
}