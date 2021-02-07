import ArgumentParser
import Socket
import Logging
import Foundation

struct Convert: ParsableCommand {

    @Flag(name: .shortAndLong, help: "Print incoming packets.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "TCP to UDP instead of UDP to TCP.")
    var reverse = false

    @Argument(help: "The port to listen to (receive packets from).")
    var from: Int

    @Argument(help: "The host to redirect packets to.")
    var to: String

    @Argument(help: "The port to redirect packets to.")
    var toPort: Int32

    mutating func run() throws {
        let termQueue = DispatchQueue(label: "kill")

        let logger = Logger(label: "com.koraykoska.UDPToTCP")

        let tcpOrganizer = TCPCLientOrganizer()

        let server = try UDPServer(port: from)
        let to = self.to
        let toPort = self.toPort
        server.messageCallback = { data, from in
            guard let from = from else {
                return
            }
            if let socket = tcpOrganizer.get(for: from) {
                do {
                    try socket.write(from: data)
                } catch {
                    logger.error("Could not send data to TCP Socket!")
                    logger.error("\(error)")
                }
            } else {
                if let socket = try? Socket.create(family: .inet, type: .stream, proto: .tcp), let _ = try? socket.connect(to: to, port: toPort) {
                    tcpOrganizer.register(tcp: socket, for: from)

                    do {
                        try socket.write(from: data)
                    } catch {
                        logger.error("Could not send data to TCP Socket!")
                        logger.error("\(error)")
                    }

                    tcpOrganizer.registerReadCallback(for: from) { data in
                        do {
                            try server.send(data: data, to: from)
                        } catch {
                            logger.error("Could not send data to UDP origin!")
                        }
                    }
                } else {
                    logger.error("Connection to host \(to):\(toPort) failed!")
                }
            }
        }

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let clean = {
            server.stop()
            tcpOrganizer.clean()

            Foundation.exit(0)
        }

        let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: termQueue)
        sigintSrc.setEventHandler {
            logger.info("Terminating due to signal SIGINT.")

            clean()
        }
        sigintSrc.resume()
        let sigTermSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: termQueue)
        sigTermSrc.setEventHandler {
            logger.info("Terminating due to signal SIGTERM.")

            clean()
        }
        sigTermSrc.resume()

        while server.shouldRun {
            sleep(1)
        }

        logger.error("Connection was closed!")
    }
}

Convert.main()
