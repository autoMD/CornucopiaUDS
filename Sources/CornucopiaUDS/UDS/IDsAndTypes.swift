//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import CornucopiaCore
import Foundation

public protocol _UDSConstructableFromMessage {

    init(message: UDS.Message)
}

/// UDS Standard IDs and types defined by ISO14229-1:2020
extension UDS {

    public typealias ConstructableViaMessage = _UDSConstructableFromMessage

    public enum ServiceId {

        /// SAE J1979
        public static let currentPowertrainDiagnosticsData            : UInt8 = 0x01
        public static let powertrainFreezeFrameData                   : UInt8 = 0x02
        public static let emissionRelatedDTCs                         : UInt8 = 0x03
        public static let resetEmissionRelatedDTCs                    : UInt8 = 0x04
        public static let oxygenSensorMonitoringTestResults           : UInt8 = 0x05
        public static let onBoardMonitoringTestResults                : UInt8 = 0x06
        public static let pendingEmissionRelatedDTCs                  : UInt8 = 0x07
        public static let controlOnBoardSystemTestOrComponent         : UInt8 = 0x08
        public static let vehicleInformation                          : UInt8 = 0x09
        public static let permanentEmissionRelatedDTCs                : UInt8 = 0x0A

        /// ISO14229
        public static let diagnosticSessionControl                    : UInt8 = 0x10
        public static let ecuReset                                    : UInt8 = 0x11
        public static let clearDiagnosticInformation                  : UInt8 = 0x14
        public static let readDTCInformation                          : UInt8 = 0x19

        public static let readDataByIdentifier                        : UInt8 = 0x22
        public static let readMemoryByAddress                         : UInt8 = 0x23
        public static let readScalingDataByIdentifier                 : UInt8 = 0x24
        public static let securityAccess                              : UInt8 = 0x27
        public static let communicationControl                        : UInt8 = 0x28
        public static let authentication                              : UInt8 = 0x29
        public static let readDataByPeriodicIdentifier                : UInt8 = 0x2A
        public static let dynamicallyDefineDataIdentifier             : UInt8 = 0x2C
        public static let writeDataByIdentifier                       : UInt8 = 0x2E
        public static let inputOutputControlByIdentifier              : UInt8 = 0x2F

        public static let routineControl                              : UInt8 = 0x31
        public static let requestDownload                             : UInt8 = 0x34
        public static let requestUpload                               : UInt8 = 0x35
        public static let transferData                                : UInt8 = 0x36
        public static let requestTransferExit                         : UInt8 = 0x37
        public static let requestFileTransfer                         : UInt8 = 0x38
        public static let writeMemoryByAddress                        : UInt8 = 0x3D
        public static let testerPresent                               : UInt8 = 0x3E

        public static let securedDataTransmission                     : UInt8 = 0x84
        public static let controlDTCSetting                           : UInt8 = 0x85
        public static let responseOnEvent                             : UInt8 = 0x86
        public static let linkControl                                 : UInt8 = 0x87

        /// ISO14230 (KWP 2000, deprecated)
        public static let kwpStopDiagnosticSession                    : UInt8 = 0x20
        public static let kwpStartCommunication                       : UInt8 = 0x81
        public static let kwpStopCommunication                        : UInt8 = 0x82
        public static let kwpEnableNormalMessageTransmission          : UInt8 = 0x29
        public static let kwpNetworkConfiguration                     : UInt8 = 0x84
        public static let kwpReadDataByLocalIdentifier                : UInt8 = 0x21
        public static let kwpReadECUIdentification                    : UInt8 = 0x1A
        public static let kwpWriteDataByLocalIdentifier               : UInt8 = 0x3B
        public static let kwpWetDataRates                             : UInt8 = 0x26
        public static let kwpReadDiagnosticTroubleCode                : UInt8 = 0x13
        public static let kwpReadFreezeFrameData                      : UInt8 = 0x12
        public static let kwpReadDTCsByStatus                         : UInt8 = 0x18
        public static let kwpReadStatusOfDTCs                         : UInt8 = 0x17
        public static let kwpInputOutputControlByLocalIdentifier      : UInt8 = 0x30
        public static let kwpStopRoutineByLocalIdentifier             : UInt8 = 0x32
        public static let kwpStartRoutineByAddress                    : UInt8 = 0x38
        public static let kwpStopRoutineByAddress                     : UInt8 = 0x39
        public static let kwpRequestRoutineResultsByLocalIdentifier   : UInt8 = 0x33
        public static let kwpRequestRoutineResultsByAddress           : UInt8 = 0x3A
    }

    /// DTC Response: Responses containing one or more diagnostic trouble codes
    public struct DTCResponse: ConstructableViaMessage, CustomStringConvertible {

        public let dtc: [UDS.DTC]

        public init(message: UDS.Message) {
            guard message.bytes.count > 1 else { fatalError() }
            /*
             CAN-protocols deliver the actual number of DTC in the first byte of the payload (after 0x43 for the positive indication of service 0x03).
             From here, we have no idea about the bus protocol that transported this message, hence we need some heuristics:
             Assuming that no ECU will manage to accumulate over 255 error codes (in which case our offset computation would be off),
             we just check whether the length of the result is odd (non-CAN) or even (CAN).
             */
            let dtcStartOffset = message.bytes.count.CC_parity == .odd ? 1 : 2
            self.dtc = message.bytes[dtcStartOffset...].CC_chunked(size: 2).map { UDS.DTC(from: $0) }
        }

        public var description: String { "DTCResponse: \(dtc)" }
    }

    /// Generic Response: For responses with vendor-specific response parameter records
    public struct GenericResponse: ConstructableViaMessage, CustomStringConvertible {

        public let record: [UInt8]

        public init(message: UDS.Message) {
            self.record = message.bytes
        }

        public var description: String { "GenericResponse: " + self.record.map { String(format: "0x%02X ", $0) }.joined() }
    }

    /// String Response: For ASCII-encoded strings
    public struct StringResponse: ConstructableViaMessage, CustomStringConvertible {

        public let string: String

        public init(message: UDS.Message) {
            self.string = message.bytes.map { String(format: "%c", $0.CC_isASCII ? $0 : ".") }.joined()
        }

        public var description: String { "StringResponse: '\(string)'" }
    }

    /// OBD2 Response: For OBD2 measurements et. al.
    public struct OBD2Response: ConstructableViaMessage, CustomStringConvertible {

        public enum ValueType {
            case measurement
            case string
            case invalid
            case unknown
            case pids
        }

        public let message: UDS.Message
        public let mnemonic: String
        public private(set) var value: Any?
        public private(set) var valueType: ValueType
        public private(set) var measurement: Measurement<Unit>?
        public private(set) var string: String?
        public private(set) var pids: [UInt8]?
        public var localizedValueTypeDescription: String { self.mnemonic.CC_localized }
        public var localizedValueDescription: String { "???" }

        public init(message: UDS.Message) {

            self.message = message
            let sid = message.bytes[0] & ~0x40
            let pid = message.bytes[1]
            guard let spec = UDS.OBD2.messageSpecs.first(where: { $0.sid == sid && $0.pid == pid }) else {
                print("Can't find a matching spec for response \(pid, radix: .hex, prefix: true, toWidth: 2) \(sid, radix: .hex, prefix: true, toWidth: 2)")
                self.value = nil
                self.valueType = .unknown
                self.mnemonic = "UNKNOWN"
                return
            }
            self.mnemonic = spec.mnemonic
            guard let value = spec.convert(message: message) else {
                self.valueType = .invalid
                return
            }
            self.value = value
            switch value {
                case let measurement as Measurement<Unit>:
                    self.measurement = measurement
                    self.valueType = .measurement

                case let string as String:
                    self.string = string
                    self.valueType = .string

                case let pids as [UInt8]:
                    self.pids = pids
                    self.valueType = .pids

                default:
                    self.valueType = .unknown
            }
        }

        public var description: String { "\(self.mnemonic): \(self.value ?? "Unknown")" }
    }

    // Service 0x01 – OBD2 Current Data
    public enum CurrentPowertrainDiagnosticsDataType {

        public static let pids_00_1F                                 : UInt8 = 0x00
        public static let monitorStatusSinceDtcCleared               : UInt8 = 0x01
        public static let dtcThatTriggeredFreezeFrame                : UInt8 = 0x02
        public static let fuelSystemStatus                           : UInt8 = 0x03
        public static let calculatedEngineLoad                       : UInt8 = 0x04
        public static let engineCoolantTemperature                   : UInt8 = 0x05
        public static let shortTermFuelTrimBank1                     : UInt8 = 0x06
        public static let longTermFuelTrimBank1                      : UInt8 = 0x07
        public static let shortTermFuelTrimBank2                     : UInt8 = 0x08
        public static let longTermFuelTrimBank2                      : UInt8 = 0x09
        public static let fuelPressure                               : UInt8 = 0x0A
        public static let intakePressure                             : UInt8 = 0x0B
        public static let engineRPM                                  : UInt8 = 0x0C
        public static let vehicleSpeed                               : UInt8 = 0x0D
        public static let timingAdvance                              : UInt8 = 0x0E
        public static let intakeTemperature                          : UInt8 = 0x0F
        public static let manifestAirFlowRate                        : UInt8 = 0x10
        public static let throttlePosition                           : UInt8 = 0x11
        public static let secondaryAirStatus                         : UInt8 = 0x12
        public static let o2SensorsPresent                           : UInt8 = 0x13
        public static let o2Bank1Sensor1Voltage                      : UInt8 = 0x14
        public static let o2Bank1Sensor2Voltage                      : UInt8 = 0x15
        public static let o2Bank1Sensor3Voltage                      : UInt8 = 0x16
        public static let o2Bank1Sensor4Voltage                      : UInt8 = 0x17
        public static let o2Bank2Sensor1Voltage                      : UInt8 = 0x18
        public static let o2Bank2Sensor2Voltage                      : UInt8 = 0x19
        public static let o2Bank2Sensor3Voltage                      : UInt8 = 0x1A
        public static let o2Bank2Sensor4Voltage                      : UInt8 = 0x1B
        public static let standardsCompliance                        : UInt8 = 0x1C
        public static let o2SensorsPresentAlternative                : UInt8 = 0x1D
        public static let auxiliaryInputStatus                       : UInt8 = 0x1E
        public static let engineRunTime                              : UInt8 = 0x1F

        public static let pids_20_3F                                 : UInt8 = 0x20

        public static let pids_40_5F                                 : UInt8 = 0x40
        public static let fuelType                                   : UInt8 = 0x52

        public static let pids_60_7F                                 : UInt8 = 0x60
        public static let pids_80_9F                                 : UInt8 = 0x80
        public static let pids_A0_BF                                 : UInt8 = 0xA0
        public static let pids_C0_DF                                 : UInt8 = 0xC0
        public static let pids_E0_FF                                 : UInt8 = 0xE0
    }

    // Service 0x09 – OBD2 Vehicle Information
    public enum VehicleInformationType {

        public static let supportedServices                              : UInt8 = 0x00
        public static let vinMessageCount                                : UInt8 = 0x01
        public static let vin                                            : UInt8 = 0x02
        public static let calibrationIDMessageCount                      : UInt8 = 0x03
        public static let calibrationId                                  : UInt8 = 0x04
        public static let calibrationVerificationNumbersCount            : UInt8 = 0x05
        public static let calibrationVerificationNumbers                 : UInt8 = 0x06
        public static let inUsePerformanceTrackingMessageCount           : UInt8 = 0x07
        public static let inUsePerformanceTrackingForSparkIgnition       : UInt8 = 0x08
        public static let ecuNameMessageCount                            : UInt8 = 0x09
        public static let ecuName                                        : UInt8 = 0x0A
        public static let inUsePerformanceTrackingForCompressionIgnition : UInt8 = 0x0B
        public static let ecuSerialNumberMessageCount                    : UInt8 = 0x0C
        public static let ecuSerialNumber                                : UInt8 = 0x0D
        public static let exhaustRegulationOrTypeApprovalNumber          : UInt8 = 0x0E
        public static let exhaustRegulationOrTypeApprovalNumberCount     : UInt8 = 0x0F
    }

    // Service 0x10 – Diagnostic Session Control
    public enum DiagnosticSessionType: UInt8 {

        case `default`    = 0x01
        case programming  = 0x02
        case extended     = 0x03
        case safetySystem = 0x04
    }

    public struct DiagnosticSessionResponse: ConstructableViaMessage {

        /// Maximum allowed time until first response after having received the request (ISO14229-2:2013)
        let p2serverMax: TimeInterval
        /// Maximum allowed time until next response after having sent 0x78 to enhance overall response time (ISO14229-2:2013)
        let p2extServerMax: TimeInterval

        public init(message: UDS.Message) {
            let p2Hi = UInt16(message.bytes[1])
            let p2Lo = UInt16(message.bytes[2])
            let ms = p2Hi << 8 | p2Lo
            self.p2serverMax = Double(ms) / 1000.0

            let p2exHi = UInt16(message.bytes[3])
            let p2exLo = UInt16(message.bytes[4])
            let tms = p2exHi << 8 | p2exLo
            self.p2extServerMax = Double(tms) / 100.0
        }
    }

    // Service 0x11 – ECU Reset
    public enum EcuResetType: UInt8 {

        case hardReset                 = 0x01
        case keyOffOnReset             = 0x02
        case softReset                 = 0x03
        case enableRapidPowerShutdown  = 0x04
        case disableRapidPowerShutdown = 0x05
    }

    public struct EcuResetResponse: ConstructableViaMessage {

        let powerDownTime: TimeInterval

        public init(message: UDS.Message) {
            guard message.bytes[1] == EcuResetType.enableRapidPowerShutdown.rawValue else {
                self.powerDownTime = 0xFF
                return
            }
            self.powerDownTime = TimeInterval(message.bytes[2])
        }
    }

    // Service 0x22 – Read Data By Identifier
    public struct DataIdentifierResponse: ConstructableViaMessage {

        public init(message: UDS.Message) {

            guard message.bytes.count >= 3 else {
                self.dataIdentifier = 0
                self.dataRecord = []
                return
            }

            let hi = message.bytes[1]
            let lo = message.bytes[2]
            let payload = message.bytes[3...]
            self.dataIdentifier = UInt16(hi) << 8 | UInt16(lo << 0)
            self.dataRecord = Array(payload)
        }

        public let dataIdentifier: DataIdentifier
        public let dataRecord: DataRecord
        public var ascii: String { self.dataRecord.map { String(format: "%c", $0 > 0x08 && $0 < 0x80 ? $0 : 0x2E) }.joined() }
    }

    // Service 0x27 – Security Access
    public struct SecurityAccessSeedResponse: ConstructableViaMessage {

        public init(message: UDS.Message) {
            self.seed = Array(message.bytes[2...])
        }

        public let seed: [UInt8]
    }

    // Service 0x31 – Routine Control
    public enum RoutineControlType: UInt8 {

        case startRoutine                                = 0x01
        case stopRoutine                                 = 0x02
        case requestRoutineResults                       = 0x03
    }
    public enum RoutineControlIdentifier {

        public static let eraseMemory           : UInt16 = 0xFF00
    }

    // Service 0x34 – Request Download
    public struct RequestDownloadResponse: ConstructableViaMessage {

        let lengthFormatIdentifier: UInt8
        let maxNumberOfBlockLength: Int

        public init(message: UDS.Message) {
            self.lengthFormatIdentifier = message.bytes[2] // hi nibble is number of bytes in block size specifier
            switch self.lengthFormatIdentifier >> 4 {
                case 1:
                    self.maxNumberOfBlockLength = Int(message.bytes[3])
                case 2:
                    self.maxNumberOfBlockLength = Int(message.bytes[3] << 8*1) | Int(message.bytes[4] << 8*0)
                case 3:
                    self.maxNumberOfBlockLength = Int(message.bytes[3] << 8*2) | Int(message.bytes[4] << 8*1) | Int(message.bytes[5] << 8*0)
                case 4:
                    self.maxNumberOfBlockLength = Int(message.bytes[3] << 8*3) | Int(message.bytes[4] << 8*2) | Int(message.bytes[5] << 8*1) | Int(message.bytes[6] << 8*0)
                default:
                    //FIXME: Handle
                    preconditionFailure("Not yet implemented")
            }
        }
    }

    // Service 0x3E – Tester Present
    public enum TesterPresentType: UInt8 {

        case sendResponse                                = 0x00
        case doNotRespond                                = 0x80
    }

}

/// Service 0x22 – Read Data By Identifier.
/// Predefined values as per ISO14229-1:2020 – all other values are vendor-specific.
public extension UDS.DataIdentifier {

    static let bootSoftwareIdentification                                       : UInt16 = 0xF180
    static let applicationSoftwareIdentification                                : UInt16 = 0xF181
    static let applicationDataIdentification                                    : UInt16 = 0xF182
    static let bootSoftwareFingerprint                                          : UInt16 = 0xF183
    static let applicationSoftwareFingerprint                                   : UInt16 = 0xF184
    static let applicationDataFingerprint                                       : UInt16 = 0xF185
    static let activeDiagnosticSession                                          : UInt16 = 0xF186
    static let vehicleManufacturerSparePartNumber                               : UInt16 = 0xF187
    static let vehicleManufacturerECUSoftwareNumber                             : UInt16 = 0xF188
    static let vehicleManufacturerECUSoftwareVersionNumber                      : UInt16 = 0xF189
    static let systemSupplierIdentifier                                         : UInt16 = 0xF18A
    static let ecuManufacturingDate                                             : UInt16 = 0xF18B
    static let ecuSerialNumber                                                  : UInt16 = 0xF18C
    static let supportedFunctionalUnits                                         : UInt16 = 0xF18D
    static let vehicleManufacturerKitAssemblyPartNumber                         : UInt16 = 0xF18E
    static let regulationXSoftwareIdentificationNumbers                         : UInt16 = 0xF18F
    static let vin                                                              : UInt16 = 0xF190
    static let vehicleManufacturerECUHardwareNumber                             : UInt16 = 0xF191
    static let systemSupplierECUHardwareNumber                                  : UInt16 = 0xF192
    static let systemSupplierECUHardwareVersionNumber                           : UInt16 = 0xF193
    static let systemSupplierECUSoftwareNumber                                  : UInt16 = 0xF194
    static let systemSupplierECUSoftwareVersionNumber                           : UInt16 = 0xF195
    static let exhaustRegulationOrTypeApprovalNumber                            : UInt16 = 0xF196
    static let systemNameOrEngineType                                           : UInt16 = 0xF197
    static let repairShopCodeOrTesterSerialNumber                               : UInt16 = 0xF198
    static let programmingDate                                                  : UInt16 = 0xF199
    static let calibrationRepairShopCodeOrCalibrationEquipmentSerialNumber      : UInt16 = 0xF19A
    static let calibrationDate                                                  : UInt16 = 0xF19B
    static let calibrationEquipmentSoftwareNumber                               : UInt16 = 0xF19C
    static let ecuInstallationDate                                              : UInt16 = 0xF19D
    static let odxFile                                                          : UInt16 = 0xF19E
    static let entity                                                           : UInt16 = 0xF19F
    static let numberOfEDRDevices                                               : UInt16 = 0xFA10
    static let edrIdentification                                                : UInt16 = 0xFA11
    static let edrDeviceAddressInformation                                      : UInt16 = 0xFA12
    static let udsVersion                                                       : UInt16 = 0xFF00
}

