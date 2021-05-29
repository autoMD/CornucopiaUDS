//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation

public extension UDS {

    class OBD2Session {

        public typealias TypedResult<SuccessfulResponseType> = Result<SuccessfulResponseType, UDS.Error>
        public typealias TypedResultHandler<SuccessfulResponseType> = (TypedResult<SuccessfulResponseType>) -> ()

        let adapter: Adapter
        let header: Header = 0x7DF

        public init(adapter: Adapter) {
            precondition(adapter.state == .connected, "Adapter needs to be in connected state")
            self.adapter = adapter
        }

        public func readDTCs(storage: UDS.DTC.StorageArea, then: @escaping(TypedResultHandler<DTCResponse>)) {
            self.request(service: storage.service, then: then)
        }

        public func read(service: UDS.Service, then: @escaping(TypedResultHandler<OBD2Response>)) {
            self.request(service: service, then: then)
        }
    }
}

internal extension UDS.OBD2Session {

    func request<T: UDS.ConstructableViaMessage>(service: UDS.Service, then: @escaping(TypedResultHandler<T>)) {
        let payload = service.payload
        guard !payload.isEmpty else {
            let failure: UDS.Error = .malformedService
            then(.failure(failure))
            return
        }
        let message = UDS.Message(id: self.header, reply: 0x0, bytes: payload)

        self.adapter.send(message: message) { result in

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
}
