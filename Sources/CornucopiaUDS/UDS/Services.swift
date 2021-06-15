//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation

public extension UDS {

    typealias AddressAndLengthFormatIdentifier = UInt8
    typealias BlockSequenceCounter = UInt8
    typealias Compression = UInt8 // actually, just a nibble
    typealias DataIdentifier = UInt16
    typealias DataFormatIdentifier = UInt8
    typealias DataRecord = [UInt8]
    typealias Encryption = UInt8 // actually, just a nibble
    typealias GroupOfDTC = UInt32 // actually, just two or three bytes
    typealias Header = UInt32
    typealias MemorySize = UInt8 // 0x01 - 0xFF, in reality a lot less though
    typealias ParameterId = UInt8 // 0x01 - 0xFF, in reality a lot less though
    typealias PositionInRecord = UInt8
    typealias RoutineIdentifier = UInt16
    typealias RoutineControlOptionRecord = [UInt8]
    typealias SecurityLevel = UInt8
    typealias TransferAddress = [UInt8]
    typealias TransferLength = [UInt8]
    typealias TransferRequestParameterRecord = [UInt8]

    static let canBroadcastHeader11: Header = .init(0x7DF)
    static let canBroadcastHeader29: Header = .init(0x18DB33F1)

    static let ecuCharacterSet: CharacterSet = .init(charactersIn: "0123456789ABCDEF ")

    enum Service {

        // On-Board-Diagnostics 2 (OBD2)
        case currentData(pid: ParameterId)
        case freezeFrameData(frame: UInt8, pid: ParameterId)
        case storedDTCs
        case resetDTCs
        case oxygenSensorMonitoring
        case componentMonitoring
        case pendingDTCs
        case triggerControlOperation(pid: ParameterId)
        case vehicleInformation(pid: ParameterId)
        case permanentDTCs

        // Unified Diagnostic Services (UDS)
        case clearDiagnosticInformation(groupOfDTC: GroupOfDTC)
        case clearAllDynamicallyDefinedDataIdentifiers
        case clearDynamicallyDefinedDataIdentifier(id: DataIdentifier)
        case dynamicallyDefineDataIdentifier(id: DataIdentifier, byIdentifier: DataIdentifier, position: PositionInRecord, length: MemorySize)
        case diagnosticSessionControl(session: DiagnosticSessionType)
        case ecuReset(type: EcuResetType)
        case readDataByIdentifier(id: DataIdentifier)
        case readDTCByStatusMask(mask: DTC.StatusMask)
        case requestDownload(compression: Compression, encryption: Encryption, address: TransferAddress, length: TransferLength)
        case requestTransferExit(trpr: DataRecord = [])
        case routineControl(type: RoutineControlType, id: RoutineIdentifier, rcor: DataRecord)
        case securityAccessRequestSeed(level: UInt8)
        case securityAccessSendKey(level: UInt8, key: [UInt8])
        case testerPresent(type: TesterPresentType)
        case transferData(bsc: BlockSequenceCounter, trpr: DataRecord)
        case writeDataByIdentifier(id: DataIdentifier, drec: DataRecord)

        public var payload: [UInt8] {

            switch self {
                // On-Board-Diagnostics 2 (OBD2)
                case .componentMonitoring:
                    return [UDS.ServiceId.onBoardMonitoringTestResults]

                case .currentData(pid: let pid):
                    return [UDS.ServiceId.currentPowertrainDiagnosticsData, pid]

                case .freezeFrameData(frame: let frame, pid: let pid):
                    return [UDS.ServiceId.powertrainFreezeFrameData, frame, pid]

                case .oxygenSensorMonitoring:
                    return [UDS.ServiceId.oxygenSensorMonitoringTestResults]

                case .pendingDTCs:
                    return [UDS.ServiceId.pendingEmissionRelatedDTCs]

                case .permanentDTCs:
                    return [UDS.ServiceId.permanentEmissionRelatedDTCs]

                case .resetDTCs:
                    return [UDS.ServiceId.resetEmissionRelatedDTCs]

                case .storedDTCs:
                    return [UDS.ServiceId.emissionRelatedDTCs]

                case .triggerControlOperation(pid: let pid):
                    return [UDS.ServiceId.controlOnBoardSystemTestOrComponent, pid]

                case .vehicleInformation(pid: let pid):
                    return [UDS.ServiceId.vehicleInformation, pid]

                // Unified Diagnostic Services (UDS)
                case .clearDiagnosticInformation(let group):
                    let (_, msblo, lsbhi, lsblo) = group.CC_UInt8tuple
                    return [UDS.ServiceId.clearDiagnosticInformation, msblo, lsbhi, lsblo]

                case .clearDynamicallyDefinedDataIdentifier(let id):
                    let idhi = UInt8(id >> 8 & 0xff)
                    let idlo = UInt8(id & 0xff)
                    return [UDS.ServiceId.dynamicallyDefineDataIdentifier, UDS.DynamicallyDefineDataIdentifierDefinitionType.clear.rawValue, idhi, idlo]

                case .clearAllDynamicallyDefinedDataIdentifiers:
                    return [UDS.ServiceId.dynamicallyDefineDataIdentifier, UDS.DynamicallyDefineDataIdentifierDefinitionType.clear.rawValue]

                case .dynamicallyDefineDataIdentifier(let id, let sourceId, let position, let length):
                    let idhi = UInt8(id >> 8 & 0xff)
                    let idlo = UInt8(id & 0xff)
                    let sourceidhi = UInt8(sourceId >> 8 & 0xff)
                    let sourceidlo = UInt8(sourceId & 0xff)
                    return [UDS.ServiceId.dynamicallyDefineDataIdentifier, UDS.DynamicallyDefineDataIdentifierDefinitionType.defineByIdentifier.rawValue, idhi, idlo, sourceidhi, sourceidlo, position, length]

                case .diagnosticSessionControl(session: let session):
                    return [UDS.ServiceId.diagnosticSessionControl, session.rawValue]

                case .ecuReset(type: let type):
                    return [UDS.ServiceId.ecuReset, type.rawValue]

                case .readDataByIdentifier(id: let id):
                    let idhi = UInt8(id >> 8 & 0xff)
                    let idlo = UInt8(id & 0xff)
                    return [UDS.ServiceId.readDataByIdentifier, idhi, idlo]

                case .readDTCByStatusMask(let mask):
                    return [UDS.ServiceId.readDTCInformation, UDS.ReadDTCReportType.reportDTCByStatusMask.rawValue, mask.rawValue]

                case .requestDownload(compression: let compression, encryption: let encryption, address: let address, length: let length):
                    guard compression < 0x10 else { return [] }
                    guard encryption < 0x10 else { return [] }
                    let dfi: UDS.DataFormatIdentifier = ((compression & 0x0F) << 4) | (encryption & 0x0F)
                    guard address.count < 0x10 else { return [] }
                    guard length.count < 0x10 else { return [] }
                    let alfid: UDS.AddressAndLengthFormatIdentifier = ((UInt8(address.count) & 0x0F) << 4) | (UInt8(length.count) & 0x0F)
                    return [UDS.ServiceId.requestDownload, dfi, alfid] + address + length

                case .requestTransferExit(trpr: let tprp):
                    return [UDS.ServiceId.requestTransferExit] + tprp

                case .routineControl(type: let type, id: let id, rcor: let rcor):
                    let idhi = UInt8(id >> 8 & 0xff)
                    let idlo = UInt8(id & 0xff)
                    return [UDS.ServiceId.routineControl, type.rawValue, idhi, idlo] + rcor

                case .securityAccessRequestSeed(level: let level):
                    guard level < 0x7F && level % 2 == 1 else { return [] }
                    return [UDS.ServiceId.securityAccess, level]

                case .securityAccessSendKey(level: let level, key: let key):
                    guard level < 0x7F && level % 2 == 0 else { return [] }
                    return [UDS.ServiceId.securityAccess, level] + key

                case .testerPresent(type: let type):
                    return [UDS.ServiceId.testerPresent, type.rawValue]

                case .transferData(bsc: let bsc, trpr: let trpr):
                    //FIXME: On ISOTP, the maximum record size for transferData is 4093.
                    //       I need to check whether this also applies to the other UDS transport protocols.
                    guard trpr.count <= 4095 - 2 else { return [] }
                    return [UDS.ServiceId.transferData, bsc] + trpr

                case .writeDataByIdentifier(id: let id, drec: let drec):
                    let idhi = UInt8(id >> 8 & 0xff)
                    let idlo = UInt8(id & 0xff)
                    return [UDS.ServiceId.writeDataByIdentifier, idhi, idlo] + drec
            }
        }
    }
}
