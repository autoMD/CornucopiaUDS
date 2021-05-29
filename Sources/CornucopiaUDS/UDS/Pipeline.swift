//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import CornucopiaCore

private let logger = Cornucopia.Core.Logger(category: "UDS.Pipeline")

public extension UDS {

    class Pipeline {

        public let adapter: UDS.Adapter

        public init(adapter: UDS.Adapter) {
            precondition(adapter.state == .connected, "At pipeline construction time, the adapter needs to be in state '.connected'")
            self.adapter = adapter
            logger.debug("UDS Pipeline with adapter \(adapter)")
        }

        public func send(to: UDS.Header, reply: UDS.Header? = nil, service: UDS.Service, then: @escaping(UDS.MessageResultHandler)) {
            let payload = service.payload
            guard payload.count > 0 else {
                let failure: UDS.MessageResult = .failure(.malformedService)
                then(failure)
                return
            }
            let message = UDS.Message(id: to, reply: reply, bytes: payload)

            self.adapter.send(message: message) { result in
                //TODO: Add logging on UDS message level here
                #if false
                switch result {
                    case .success(let reply):
                        break
                    case .failure(let error):
                        break
                }
                #endif
                then(result)
            }
        }
    }
}
