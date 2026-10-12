import Foundation
import OneBudsProtocol

/// Deterministic, scriptable transport for unit tests and the labelled Demo mode. Never talks to
/// real hardware.
public actor MockTransport: EarbudTransport {
    public enum Reaction: Sendable {
        case none
        case reply([Data])
        case disconnect(String)
    }

    public typealias Handler = @Sendable (Data) async -> Reaction

    public nonisolated let kind = TransportKind.mock
    public nonisolated let incoming: AsyncStream<Data>
    public nonisolated let state: AsyncStream<TransportState>
    private let incomingContinuation: AsyncStream<Data>.Continuation
    private let stateContinuation: AsyncStream<TransportState>.Continuation

    private let handler: Handler
    private let connectError: TransportError?
    private let framesOnConnect: [Data]
    private var connected = false
    private var used = false
    private var finished = false
    public private(set) var sent: [Data] = []

    public init(connectError: TransportError? = nil, framesOnConnect: [Data] = [], handler: @escaping Handler = { _ in .none }) {
        self.connectError = connectError
        self.framesOnConnect = framesOnConnect
        self.handler = handler
        (incoming, incomingContinuation) = AsyncStream.makeStream(of: Data.self)
        (state, stateContinuation) = AsyncStream.makeStream(of: TransportState.self)
    }

    public func connect() async throws {
        guard !used else { throw TransportError.alreadyUsed }
        used = true
        stateContinuation.yield(.connecting)
        if let connectError {
            finish(.failed(connectError.localizedDescription))
            throw connectError
        }
        connected = true
        stateContinuation.yield(.connected)
        framesOnConnect.forEach { incomingContinuation.yield($0) }
    }

    public func disconnect() async {
        finish(.disconnected(reason: "closed by OneBuds"))
    }

    public func send(_ frame: Data) async throws {
        guard connected else { throw TransportError.notConnected }
        sent.append(frame)
        switch await handler(frame) {
        case .none: break
        case .reply(let replies): replies.forEach { incomingContinuation.yield($0) }
        case .disconnect(let reason): finish(.disconnected(reason: reason))
        }
    }

    /// Delivers unsolicited bytes, as if the earbuds sent them.
    public func inject(_ data: Data) {
        guard connected else { return }
        incomingContinuation.yield(data)
    }

    public func simulateDisconnect(reason: String) {
        finish(.disconnected(reason: reason))
    }

    public var sentFrames: [OPOFrame] {
        var decoder = OPOFrameDecoder()
        return sent.flatMap { decoder.append([UInt8]($0)) }.compactMap { if case .frame(let frame) = $0 { frame } else { nil } }
    }

    private func finish(_ final: TransportState) {
        guard !finished else { return }
        finished = true
        connected = false
        stateContinuation.yield(final)
        stateContinuation.finish()
        incomingContinuation.finish()
    }
}
