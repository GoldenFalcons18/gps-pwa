import Foundation
import Network

enum NICTClock {
    private final class CompletionGate {
        private let lock = NSLock()
        private var finished = false
        func run(_ body: () -> Void) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            body()
        }
    }

    static func query() async throws -> Date {
        try await withCheckedThrowingContinuation { continuation in
            let gate = CompletionGate()
            let queue = DispatchQueue(label: "com.goldenfalcons.sailinggps.nict-clock")
            let connection = NWConnection(host: "ntp.nict.jp", port: 123, using: .udp)
            let startedAt = Date()
            var packet = Data(repeating: 0, count: 48)
            packet[0] = 0x1B
            let timer = DispatchWorkItem {
                gate.run {
                    connection.cancel()
                    continuation.resume(throwing: NSError(domain: "NICTClock", code: 1, userInfo: [NSLocalizedDescriptionKey: "NTP request timed out"]))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timer)
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error {
                            timer.cancel()
                            gate.run { continuation.resume(throwing: error) }
                            connection.cancel()
                            return
                        }
                        connection.receiveMessage { data, _, _, error in
                            timer.cancel()
                            if let error {
                                gate.run { continuation.resume(throwing: error) }
                                connection.cancel()
                                return
                            }
                            guard let data, data.count >= 48 else {
                                gate.run { continuation.resume(throwing: NSError(domain: "NICTClock", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid NTP response"])) }
                                connection.cancel()
                                return
                            }
                            let seconds = data[40..<44].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                            let fraction = data[44..<48].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                            let unix = Double(seconds) - 2_208_988_800 + Double(fraction) / 4_294_967_296
                            let receivedAt = Date()
                            let midpoint = startedAt.addingTimeInterval(receivedAt.timeIntervalSince(startedAt) / 2)
                            let ntpAtMidpoint = Date(timeIntervalSince1970: unix).addingTimeInterval(-receivedAt.timeIntervalSince(midpoint))
                            gate.run { continuation.resume(returning: ntpAtMidpoint) }
                            connection.cancel()
                        }
                    })
                } else if case .failed(let error) = state {
                    timer.cancel()
                    gate.run { continuation.resume(throwing: error) }
                    connection.cancel()
                }
            }
            connection.start(queue: queue)
        }
    }
}
