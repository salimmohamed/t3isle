import Foundation

public enum ReplayEvent: Sendable {
    case shell(ShellUpdate)
    case detail(ThreadProjection)
    case provider(ProviderLimits)
}

public enum ScenarioError: Error, Equatable, LocalizedError {
    case unknown(String, known: [String])
    case malformed(scenario: String, line: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unknown(let name, let known): "Unknown scenario \"\(name)\". Scenarios: \(known.joined(separator: ", "))"
        case .malformed(let scenario, let line, let reason): "\(scenario).ndjson line \(line): \(reason)"
        }
    }
}

public struct Scenario: Sendable {
    public static let anchor = Date(timeIntervalSince1970: 1_767_225_600)

    struct Step: Sendable {
        enum Payload: Sendable {
            case shell(AnyWireValue)
            case detail(AnyWireValue)
            case provider(id: String, file: AnyWireValue)
        }

        let line: Int
        let after: Duration
        let payload: Payload
    }

    private struct Header: Decodable {
        let scenario: String
        let summary: String
    }

    public let name: String
    public let summary: String
    let steps: [Step]

    public var stepCount: Int { steps.count }

    public static var names: [String] {
        (Bundle.module.urls(forResourcesWithExtension: "ndjson", subdirectory: "Scenarios") ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public static func named(_ name: String) throws -> Scenario {
        guard let url = Bundle.module.url(forResource: name, withExtension: "ndjson", subdirectory: "Scenarios") else {
            throw ScenarioError.unknown(name, known: names)
        }
        return try parse(Data(contentsOf: url), name: name)
    }

    static func parse(_ data: Data, name: String) throws -> Scenario {
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first,
              let header = try? JSONDecoder().decode(Header.self, from: Data(first.utf8)),
              header.scenario == name
        else { throw ScenarioError.malformed(scenario: name, line: 1, reason: "expected {\"scenario\":\"\(name)\",\"summary\":…}") }
        let steps = try lines.enumerated().dropFirst()
            .filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try step($0.element, line: $0.offset + 1, scenario: name) }
        let scenario = Scenario(name: name, summary: header.summary, steps: steps)
        _ = try scenario.events(startingAt: anchor)
        return scenario
    }

    private static func step(_ text: Substring, line: Int, scenario: String) throws -> Step {
        let malformed = { (reason: String) in ScenarioError.malformed(scenario: scenario, line: line, reason: reason) }
        guard case .object(var fields)? = try? JSONDecoder().decode(AnyWireValue.self, from: Data(text.utf8)) else {
            throw malformed("not a JSON object")
        }
        let after: Duration
        switch fields.removeValue(forKey: "afterMs") {
        case nil: after = .zero
        case .number(let milliseconds)? where milliseconds >= 0 && milliseconds == milliseconds.rounded():
            after = .milliseconds(Int(milliseconds))
        default: throw malformed("afterMs must be a whole number of milliseconds")
        }
        guard fields.count == 1, let field = fields.first else {
            throw malformed("expected exactly one of shell, detail, provider")
        }
        switch (field.key, field.value) {
        case ("shell", let value): return Step(line: line, after: after, payload: .shell(value))
        case ("detail", let value): return Step(line: line, after: after, payload: .detail(value))
        case ("provider", .object(let provider)):
            guard case .string(let id)? = provider["id"], let file = provider["file"] else {
                throw malformed("provider needs an id and a file")
            }
            return Step(line: line, after: after, payload: .provider(id: id, file: file))
        default:
            throw malformed("expected exactly one of shell, detail, provider")
        }
    }

    public func events(startingAt start: Date) throws -> [(after: Duration, event: ReplayEvent)] {
        let offset = start.timeIntervalSince(Self.anchor)
        return try steps.flatMap { step in
            try decode(step, shiftedBy: offset).enumerated().map { index, event in
                (after: index == 0 ? step.after : .zero, event: event)
            }
        }
    }

    private func decode(_ step: Step, shiftedBy offset: TimeInterval) throws -> [ReplayEvent] {
        let malformed = { (reason: String) in ScenarioError.malformed(scenario: name, line: step.line, reason: reason) }
        switch step.payload {
        case .shell(let value):
            let updates = try T3ServerClient.shellUpdates(JSONSerialization.jsonObject(with: Self.wire(value, offset)))
            guard !updates.isEmpty else { throw malformed("not a shell item T3 streams") }
            for case .unreadable(let kind, let reason) in updates { throw malformed("unreadable \(kind): \(reason)") }
            return updates.map(ReplayEvent.shell)
        case .detail(let value):
            guard let envelope = try? T3ServerClient.decode(ThreadDetailEnvelope.self, Self.wire(value, offset)) else {
                throw malformed("not a thread detail response")
            }
            return [.detail(envelope.projection)]
        case .provider(let id, let file):
            guard let limits = UsageLimitsReader.parse(try Self.wire(file, offset), id: id, previous: []) else {
                throw malformed("not a provider cache file with usage limits")
            }
            return [.provider(limits)]
        }
    }

    private static func wire(_ value: AnyWireValue, _ offset: TimeInterval) throws -> Data {
        try JSONEncoder().encode(value.shiftingDates(by: offset))
    }
}

extension AnyWireValue {
    func shiftingDates(by offset: TimeInterval) -> AnyWireValue {
        switch self {
        case .string(let text):
            WireDate.parse(text).map { .string(WireDate.format($0.addingTimeInterval(offset))) } ?? self
        case .array(let values):
            .array(values.map { $0.shiftingDates(by: offset) })
        case .object(let fields):
            .object(fields.mapValues { $0.shiftingDates(by: offset) })
        case .number, .bool, .null:
            self
        }
    }
}
