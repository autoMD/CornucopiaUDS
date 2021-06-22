//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import CornucopiaCore
import Foundation

private let logger = Cornucopia.Core.Logger(category: "UDS.Pipeline")

public extension UDS {

    /// An UDS command pipeline.
    class Pipeline {

        public let adapter: UDS.Adapter
        public var logFilePath: String? = nil
        private var logFile: FileHandle? = nil
        private var logQ: DispatchQueue = DispatchQueue(label: "dev.cornucopia.CornucopiaUDS.UDSPipeline-Logging")

        /// Create using an `adapter` as the sink.
        public init(adapter: UDS.Adapter) {
            precondition(adapter.state == .connected, "At pipeline construction time, the adapter needs to be in state '.connected'")
            self.adapter = adapter
            logger.debug("UDS Pipeline with adapter \(adapter) ready.")
        }

        /// Starts logging by creating a log file in the specified directory.
        /// A given `header` will be written into the file, if supplied.
        /// Remember to give it a postfix of `\n`, if you want.
        public func startLogging(header: String = "") {
            self.logQ.async {
                let dir = FileManager.CC_pathInCachesDirectory(suffix: "dev.cornucopia.CornucopiaUDS")
                do {
                    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
                    let logFilePath = "\(dir)/\(UUID())-uds.csv"
                    FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil)
                    self.logFilePath = logFilePath
                    self.logFile = FileHandle(forWritingAtPath: logFilePath)
                    guard self.logFile != nil else { throw NSError(domain: "dev.cornucopia.CornucopiaUDS", code: 7, userInfo: nil) }
                    if !header.isEmpty, let headerData = header.data(using: .utf8) {
                        self.logFile?.write(headerData)
                    }
                } catch {
                    logger.notice("Can't create log file: \(error)")
                }
            }
        }

        /// Stops logging, flushing the current logging file (if necessary).
        /// Returns the name of the last log file, if existing.
        public func stopLogging() {
            guard let logFile = self.logFile else { return }
            self.logQ.async {
                do {
                    try logFile.close()
                } catch {
                    logger.notice("Can't close log file: \(error)")
                }
                self.logFile = nil
            }
        }

        /// Send a requested service command to a device and deliver the result via the completion handler.
        public func send(to: UDS.Header, reply: UDS.Header? = nil, service: UDS.Service, then: @escaping(UDS.MessageResultHandler)) {
            let payload = service.payload
            guard payload.count > 0 else {
                let failure: UDS.MessageResult = .failure(.malformedService)
                then(failure)
                return
            }
            let message = UDS.Message(id: to, reply: reply, bytes: payload)

            guard let logFile = self.logFile else {
                self.adapter.send(message: message, then: then)
                return
            }

            self.adapter.send(message: message) { result in

                self.logQ.async {
                    let requestString = "\(message.id, radix: .hex),\(payload, radix: .hex, toWidth: 2)\n"
                    var replyString = ""

                    switch result {
                        case .success(let reply):
                            replyString = "\(reply.id, radix: .hex),\(reply.bytes, radix: .hex, toWidth: 2)\n"
                            break

                        case .failure(let error):
                            replyString = "ERROR: \(error)\n"
                            break
                    }
                    try? logFile.write(contentsOf: requestString.data(using: .utf8)!)
                    try? logFile.write(contentsOf: replyString.data(using: .utf8)!)
                }
                then(result)
            }
        }
    }
}
