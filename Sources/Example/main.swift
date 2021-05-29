//
// (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import CornucopiaUDS
import CornucopiaStreams
import Foundation

var url: URL!

class Handler {

    let adapter: UDS.GenericSerialAdapter
    var previousState: UDS.GenericSerialAdapter.State = .created
    var obd2: UDS.OBD2Session!

    init(istream: InputStream, ostream: OutputStream) {

        self.adapter = UDS.GenericSerialAdapter(inputStream: istream, outputStream: ostream)

        // Register for state updates
        _ = NotificationCenter.default.addObserver(forName: UDS.Adapter.DidUpdateState, object: self.adapter, queue: nil) { _ in self.onAdapterDidUpdateState() }

        // Reset the UART speed (necessary on macOS) after opening the stream
        if url.scheme == "tty" {
            _ = NotificationCenter.default.addObserver(forName: UDS.Adapter.CanInitializeDevice, object: self.adapter, queue: nil) { _ in
                let fd = open(url.path, 0)
                var settings = termios()
                cfsetspeed(&settings, speed_t(B115200))
                tcsetattr(fd, TCSANOW, &settings)
                close(fd)
            }
        }
    }

    func run() {
        self.adapter.connect(via: .auto)
    }


    func onAdapterDidUpdateState() {
        
        print("Adapter: \(self.previousState) => \(self.adapter.state)")
        self.previousState = self.adapter.state
        switch adapter.state {

            case .configuring:
                print("Adapter identified: \(adapter.info!)")

            case .connected:
                print("Connected via protocol: \(adapter.negotiatedProtocol)")

                self.obd2 = UDS.OBD2Session(adapter: adapter)
                let vinService = UDS.Service.vehicleInformation(pid: UDS.VehicleInformationType.vin)
                self.obd2.read(service: vinService) { response in
                    guard case let .success(answer) = response else { die("No response to VIN query") }
                    print("Response to VIN query: \(answer)")
                }

            default:
                break
        }
    }
}

func die(_ message: String? = nil) -> Never {
    guard let message = message else {
        print("""
              
              Usage: ./uds <stream-url-to-adapter>
              """)
        Foundation.exit(-1)
    }

    print("Error: \(message)")
    Foundation.exit(-1)
}

func main() {

    let arguments = CommandLine.arguments
    guard arguments.count == 2 else { die() }
    url = URL(string: arguments[1]) ?? URL(string: "none://")!
    if url.scheme == "none" { die() }

    print("Connecting to \(url!)…")

    Stream.CC_getStreamPair(to: url) { result in
        guard case .success(let (inputStream, outputStream)) = result else { die("Can't connect: \(result)") }
        print("Connected. Creating generic stream adapter.")
        //DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let handler = Handler(istream: inputStream, ostream: outputStream)
            handler.run()
        //}
    }

    let loop = RunLoop.current
    while loop.run(mode: .default, before: Date.distantFuture) {
        loop.run()
    }
}

main()
