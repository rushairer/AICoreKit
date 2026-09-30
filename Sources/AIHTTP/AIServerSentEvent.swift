public struct AIServerSentEvent: Sendable, Equatable {
    public let event: String?
    public let data: String
    public let id: String?

    public init(
        event: String? = nil,
        data: String,
        id: String? = nil
    ) {
        self.event = event
        self.data = data
        self.id = id
    }
}

public struct AIServerSentEventDecoder: Sendable {
    private var eventName: String?
    private var dataLines: [String] = []
    private var lastEventID: String?

    public init() {}

    public mutating func consume(
        _ rawLine: String
    ) -> AIServerSentEvent? {
        let line: String
        if rawLine.last == "\r" {
            line = String(rawLine.dropLast())
        } else {
            line = rawLine
        }

        if line.isEmpty {
            return dispatch()
        }

        if line.hasPrefix(":") {
            return nil
        }

        let parts = line.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )

        let field = String(parts[0])
        var value =
            parts.count == 2
            ? String(parts[1])
            : ""

        if value.first == " " {
            value.removeFirst()
        }

        switch field {
        case "event":
            eventName = value
        case "data":
            dataLines.append(value)
        case "id":
            if !value.contains("\0") {
                lastEventID = value
            }
        default:
            break
        }

        return nil
    }

    public mutating func finish() -> AIServerSentEvent? {
        dispatch()
    }

    private mutating func dispatch() -> AIServerSentEvent? {
        guard !dataLines.isEmpty else {
            eventName = nil
            return nil
        }

        let event = AIServerSentEvent(
            event: eventName,
            data: dataLines.joined(separator: "\n"),
            id: lastEventID
        )

        eventName = nil
        dataLines.removeAll(keepingCapacity: true)

        return event
    }
}
