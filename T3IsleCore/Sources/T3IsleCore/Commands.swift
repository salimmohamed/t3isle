import Foundation

public enum ApprovalDecision: String, Sendable, CaseIterable {
    case accept, acceptForSession, acceptAlways, decline, cancel
}

public enum QuestionAnswer: Equatable, Sendable {
    case text(String)
    case choices([String])

    var wire: AnyWireValue {
        switch self {
        case .text(let value): .string(value)
        case .choices(let values): .array(values.map(AnyWireValue.string))
        }
    }
}

public enum T3Command: Equatable, Sendable {
    case approve(threadId: String, requestId: String, decision: ApprovalDecision)
    case answer(threadId: String, requestId: String, answers: [String: QuestionAnswer])
    case stop(threadId: String)
    case snooze(threadId: String, until: Date)
    case unsnooze(threadId: String)
    case settle(threadId: String)
    case unsettle(threadId: String)

    public var threadId: String {
        switch self {
        case .approve(let id, _, _), .answer(let id, _, _), .stop(let id),
             .snooze(let id, _), .unsnooze(let id), .settle(let id), .unsettle(let id):
            id
        }
    }

    public func payload(commandId: String) -> [String: AnyWireValue] {
        var body: [String: AnyWireValue] = ["commandId": .string(commandId), "threadId": .string(threadId)]
        switch self {
        case .approve(_, let requestId, let decision):
            body["type"] = .string("runtime-request.respond")
            body["requestId"] = .string(requestId)
            body["decision"] = .string(decision.rawValue)
        case .answer(_, let requestId, let answers):
            body["type"] = .string("runtime-request.respond")
            body["requestId"] = .string(requestId)
            body["answers"] = .object(answers.mapValues(\.wire))
        case .stop:
            body["type"] = .string("thread.stop")
            body["reason"] = .string("Interrupted from T3 Isle")
        case .snooze(_, let until):
            body["type"] = .string("thread.snooze")
            body["snoozedUntil"] = .string(WireDate.format(until))
        case .unsnooze:
            body["type"] = .string("thread.unsnooze")
            body["reason"] = .string("user")
        case .settle:
            body["type"] = .string("thread.settle")
        case .unsettle:
            body["type"] = .string("thread.unsettle")
            body["reason"] = .string("user")
        }
        return body
    }
}
