import Foundation

struct LinkedEnvironmentList: Decodable {
    struct Link: Decodable {
        let environmentId: String
        let label: String
        let status: String
    }

    let links: [Link]

    var reachable: [LinkedEnvironment] {
        links.filter { $0.status == "reachable" }.map { LinkedEnvironment(id: $0.environmentId, label: $0.label) }
    }
}

struct LinkedThreadPage: Decodable {
    let threads: [LinkedThreadItem]
    let nextCursor: Int?
}

struct LinkedProjectPage: Decodable {
    let projects: [ProjectShell]
}

struct LinkedThreadItem: Decodable {
    static let finishedStatuses: Set<String> = ["completed", "failed", "interrupted", "cancelled", "rolled_back"]

    let threadId: String
    let projectId: String?
    let title: String
    let status: String
    let latestRunId: String?
    let providerInstanceId: String?
    let model: String?
    let settled: Bool?
    let snoozedUntil: Date?
    let blockedOnThreadWait: Bool?
    let pendingBackgroundTasks: [AnyWireValue]?
    let parentThreadId: String?
    let relationshipToParent: String?
    let delegatedFrom: DelegatedFrom?
    let createdAt: Date?
    let updatedAt: Date?

    var runStatus: String {
        status == "waiting" && pendingBackgroundTasks?.isEmpty == false ? "completed" : status
    }

    func shell(in environment: LinkedEnvironment) -> ThreadShell {
        ThreadShell(
            id: threadId,
            projectId: projectId,
            title: title,
            providerInstanceId: providerInstanceId,
            modelSelection: ModelSelection(instanceId: providerInstanceId, model: model),
            lineage: Lineage(parentThreadId: parentThreadId, relationshipToParent: relationshipToParent),
            delegatedFrom: delegatedFrom,
            status: runStatus,
            latestRunId: latestRunId,
            latestRunCompletedAt: Self.finishedStatuses.contains(runStatus) ? updatedAt : nil,
            blockedOnThreadWait: blockedOnThreadWait,
            pendingBackgroundTasks: pendingBackgroundTasks,
            createdAt: createdAt,
            updatedAt: updatedAt,
            settledOverride: settled == true ? "settled" : nil,
            snoozedUntil: snoozedUntil,
            linkedEnvironment: environment
        )
    }
}

enum McpReply {
    static func structuredContent(_ data: Data) throws -> Data {
        guard let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw T3Failure.unreadable
        }
        if let error = reply["error"] as? [String: Any] {
            throw T3Failure.rejected(error["message"] as? String ?? "T3 refused.")
        }
        guard let result = reply["result"] as? [String: Any] else { throw T3Failure.unreadable }
        if result["isError"] as? Bool == true { throw T3Failure.rejected(failureMessage(result)) }
        guard let content = result["structuredContent"] else { throw T3Failure.unreadable }
        return try JSONSerialization.data(withJSONObject: content)
    }

    static func failureMessage(_ result: [String: Any]) -> String {
        let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.first ?? ""
        let failure = text.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        if failure?["code"] as? String == "runtime_mode_escalation_denied" {
            return "This thread runs with more access than a linked machine allows. Open it in T3 Code."
        }
        return failure?["message"] as? String ?? text.nilIfEmpty ?? "T3 refused."
    }

    static func lastEvent(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
        let payload = text.split(whereSeparator: \.isNewline).last { $0.hasPrefix("data:") }?.dropFirst(5)
        return payload.map { Data($0.trimmingCharacters(in: .whitespaces).utf8) } ?? data
    }

    static func request(id: Int, method: String, params: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params]))
            ?? Data()
    }

    static func toolCall(id: Int, name: String, arguments: [String: Any]) -> Data {
        request(id: id, method: "tools/call", params: ["name": name, "arguments": arguments])
    }
}

enum LinkedCommand {
    static func tool(for command: T3Command, in environment: String) throws -> (name: String, arguments: [String: Any]) {
        var arguments: [String: Any] = ["environmentId": environment, "threadId": command.threadId]
        switch command {
        case .approve:
            throw T3Failure.rejected("Approve this in T3 Code on that machine.")
        case .answer(_, let requestId, let answers):
            arguments["action"] = "respond"
            arguments["requestId"] = requestId
            arguments["answers"] = try T3ServerClient.jsonObject(answers.mapValues(\.wire))
            return ("t3_pending_request", arguments)
        case .stop:
            arguments["stop"] = true
            return ("t3_thread_interrupt", arguments)
        case .snooze(_, let until):
            arguments["action"] = "snooze"
            arguments["snoozedUntil"] = WireDate.format(until)
        case .unsnooze:
            arguments["action"] = "unsnooze"
        case .settle:
            arguments["action"] = "settle"
        case .unsettle:
            arguments["action"] = "unsettle"
        }
        return ("t3_thread_organize", arguments)
    }
}
