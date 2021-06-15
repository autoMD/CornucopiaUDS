//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import CoreFoundation
import CornucopiaCore
import Foundation

private var logger = Cornucopia.Core.Logger(category: "StreamCommandQueue")

public protocol _StreamCommandQueueDelegate {
    func streamCommandQueueDetectedEOF(_ streamCommandQueue: StreamCommandQueue)
    func streamCommandQueueDetectedError(_ streamCommandQueue: StreamCommandQueue)
}

public class StreamCommandQueue: NSObject, StreamDelegate {

    public typealias CompletionHandler = (String) -> ()
    public typealias InputStreamConfigurationHandler = (InputStream) -> ()
    public typealias Delegate = _StreamCommandQueueDelegate

    class Command {

        let request: Data
        let termination: Data
        let timeout: TimeInterval
        let dummy: Bool

        var handler: CompletionHandler
        var pendingBytesToSend: Data
        var response = Data()
        var timestamp: CFTimeInterval?
        var timer: DispatchSourceTimer?

        init(request: String, termination: String, timeout: TimeInterval = 0, handler: @escaping(CompletionHandler)) {
            guard let request = request.data(using: String.Encoding.utf8) else { fatalError("Request needs to be representable as UTF8") }
            guard let termination = termination.data(using: String.Encoding.utf8) else { fatalError("Termination needs to be representable as UTF8") }

            self.request = request
            self.pendingBytesToSend = request
            self.termination = termination
            self.timeout = timeout
            self.dummy = request.isEmpty
            self.handler = handler
        }
    }

    private let input: InputStream
    private let output: OutputStream
    private let termination: String?
    private var pending: [Command] = []
    private var active: Command?
    private var mocks: [String: String] = [:]

    public var inputConfigurationHandler: InputStreamConfigurationHandler?
    public var delegate: Delegate?

    public init(input: InputStream, output: OutputStream, termination: String? = nil) {

        self.input = input
        self.output = output
        self.termination = termination

        super.init()

        self.input.delegate = self
        self.output.delegate = self
        self.input.schedule(in: RunLoop.current, forMode: .default)
        self.output.schedule(in: RunLoop.current, forMode: .default)
        //FIXME: Consider only opening the input stream on-demand, i.e. when the first command is being sent?
        self.input.open()

        //FIXME: Debugging
        //self.installMock(request: "101F360100010203\r", response: "7ED3020005555555555\r")
        //self.installMock(request: "210405060708090A220B0C0D0E0F1011231213141516171824191A1B1C\r", response: "7ED7F367F\r")
        //self.installMock(request: "021002\r", response: "CAN ERROR\r\r")
    }

    deinit {
        self.cleanup()
    }

    public func send(command: String, termination: String? = nil, timeout: TimeInterval = 0, then: @escaping(CompletionHandler)) {
        guard let term = termination ?? self.termination else {
            fatalError("Need either a command termination or the global termination")
        }

        let command = Command(request: command, termination: term, timeout: timeout, handler: then)
        self.pending.append(command)
        if active == nil {
            self.handleNextCommand()
        }
    }

    public func flush() {
        //FIXME: Don't remove remaining commands on `flush()`
        logger.debug("Flushing…")
        self.active = nil
        self.pending = []
        logger.debug("Flushing complete!")
    }

    public func cleanup() {
        //FIXME: If there is an active command, cancel it?
        logger.debug("Cleaning up…")
        if self.input.streamStatus != .closed {
            self.input.remove(from: RunLoop.current, forMode: .default)
            self.input.close()
        }
        if self.output.streamStatus != .closed {
            self.output.remove(from: RunLoop.current, forMode: .default)
            self.output.close()
        }
        logger.debug("Cleaned up!")
    }

    //MARK: - <StreamDelegate>

    public func stream(_ stream: Stream, handle eventCode: Stream.Event) {

        precondition(Thread.isMainThread)

        logger.trace("Handling stream \(stream) event \(eventCode)")

        if stream == self.input {

            switch eventCode {

                case .openCompleted:
                    guard let configurationHandler = self.inputConfigurationHandler else { return }
                    configurationHandler(input)
                    guard self.active != nil else { return }
                    self.handleActiveCommand()

                case .hasBytesAvailable:
                    self.handleBytesAvailable()

                case .errorOccurred:
                    self.handleError(on: stream)

                default:
                    break
            }

        } else if stream == self.output {

            switch eventCode {
                case .openCompleted:
                    guard self.active != nil else { return }
                    self.handleActiveCommand()

                case .hasSpaceAvailable:
                    guard self.active != nil else { return }
                    self.handleActiveCommand()

                case .errorOccurred:
                    self.handleError(on: stream)

                default:
                    break
            }

        }
    }
}

//MARK: - Helpers
private extension StreamCommandQueue {

    static var BufferSize = 1024

    func installMock(request: String, response: String) {
        self.mocks[request] = response
    }

    func handleNextCommand() {
        precondition(self.active == nil, "called while another command has not been completed yet")

        guard !self.pending.isEmpty else {
            logger.trace("No more commands pending")
            return
        }

        self.active = self.pending.removeFirst()
        self.handleActiveCommand()
    }

    func handleActiveCommand() {
        precondition(self.active != nil, "called while there was no active command")

        guard self.input.streamStatus == .open else {
            logger.trace("Input stream not open yet… waiting")
            return
        }

        guard self.output.streamStatus == .open else {
            logger.trace("Output stream not open yet… opening")
            self.output.open()
            return
        }

        guard self.output.hasSpaceAvailable else {
            logger.trace("No space available yet… waiting")
            return
        }

        guard let active = self.active else { fatalError() }

        let mockResponse = self.mocks[active.request.CC_string]
        guard mockResponse == nil else {
            logger.debug("Encountered mock request \(active.request.CC_debugString), synthesizing mocked response \(mockResponse!)")
            active.handler(mockResponse!)
            self.active = nil
            if !self.pending.isEmpty {
                DispatchQueue.main.async {
                    self.handleNextCommand()
                }
            }
            return
        }

        guard !active.dummy else {
            logger.trace("Encountered dummy command, synthesizing an empty response")
            active.handler("")
            self.active = nil
            if !self.pending.isEmpty {
                DispatchQueue.main.async {
                    self.handleNextCommand()
                }
            }
            return
        }

        guard !active.pendingBytesToSend.isEmpty else {
            logger.trace("No more bytes to send, already waiting for the response")
            return
        }

        //FIXME: withUnsafeBytes is deprecated – should rewrite this using the throwing API instead
        //FIXME: Also – while we're on that subject – might check whether all this data and byte handling can be improved by using
        //FIXME: [UInt8], ByteBuffer (from SwiftNIO), or pure unsafe memory instead
        let bytesWritten = active.pendingBytesToSend.withUnsafeBytes {
            self.output.write($0, maxLength: active.pendingBytesToSend.count)
        }
        let writtenBytes = active.pendingBytesToSend.prefix(bytesWritten)
        logger.trace("Wrote \(bytesWritten): '\(writtenBytes.CC_debugString)'")
        active.pendingBytesToSend.removeFirst(bytesWritten)

        guard active.pendingBytesToSend.count > 0 else {
            logger.trace("No more bytes to send, waiting for the response…")
            active.timestamp = CFAbsoluteTimeGetCurrent()
            if active.timeout > 0 {
                active.timer = {
                    let t = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(), queue: DispatchQueue.main)
                    t.schedule(deadline: .now() + active.timeout)
                    t.setEventHandler { self.handleCommandTimeout() }
                    t.resume()
                    return t
                }()
            }
            return
        }
    }

    func handleBytesAvailable() {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.BufferSize)
        defer { buffer.deallocate() }
        let bytesRead = self.input.read(buffer, maxLength: Self.BufferSize)
        logger.trace("Read \(bytesRead): '\(buffer.CC_debugString(withLength: bytesRead))'")
        guard bytesRead >= 0 else {
            logger.notice("Error during reading")
            return
        }
        if bytesRead == 0 {
            logger.info("EOF encountered")
            self.cleanup()
            self.delegate?.streamCommandQueueDetectedEOF(self)
            return
        }
        guard let active = self.active else {
            logger.info("Ignoring unsolicited bytes")
            return
        }
        active.timer?.cancel()

        //NOTE: Some adapters insert invalid (non-printable) data into the byte stream, so we need an additional sanitizing pass here
        var sanitized = Data()
        var foundInvalidCharacters = false
        for i in 0..<bytesRead {
            if buffer[i].CC_isASCII {
                sanitized.append(buffer[i])
            } else {
                foundInvalidCharacters = true
                logger.trace("Stripping byte value \(buffer[i])")
            }
        }
        if foundInvalidCharacters {
            logger.debug("Input contains invalid characters (sanitized).")
        }
        active.response.append(sanitized)

        guard let terminationRange = active.response.lastRange(of: active.termination) else { return }
        guard terminationRange.endIndex == active.response.count else { return }

        active.response.removeSubrange(terminationRange)
        guard let response = String(data: active.response, encoding: .utf8) else { fatalError("Data Encoding Error") }

        let duration = String(format: "%04.0f ms", 1000 * (CFAbsoluteTimeGetCurrent() - active.timestamp!))
        logger.debug("Command processed [\(duration)]: '\(active.request.CC_debugString)' => '\(active.response.CC_debugString)'")
        active.handler(response)

        self.active = nil
        self.handleNextCommand()
    }

    func handleCommandTimeout() {
        guard let active = self.active else { fatalError("Command timeout without active command!?") }
        logger.notice("Timeout while waiting for a response to \(active.request.CC_debugString)")

        active.handler("")
        self.active = nil

        self.handleNextCommand()
    }

    func handleError(on stream: Stream) {
        logger.notice("Error on stream \(stream)")
        self.delegate?.streamCommandQueueDetectedError(self)
    }
}
