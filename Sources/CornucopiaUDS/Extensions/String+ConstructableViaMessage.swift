//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
extension String: UDS.ConstructableViaMessage {

    public init(message: UDS.Message) {
        self = message.bytes.map { String(format: "%c", $0.CC_isASCII ? $0 : 0x2E) }.joined()
    }
}
