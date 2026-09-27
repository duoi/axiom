import Foundation

struct TranscriptRow: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case user
        case assistant
    }

    var kind: Kind
    var text: String
    var chipNames: [String]
    var live: Bool
}

enum Transcript {
    static func rows(in session: Session, expanded: Bool) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        for turn in session.turns {
            switch turn.role {
            case .user:
                rows.append(
                    TranscriptRow(
                        kind: .user,
                        text: turn.text,
                        chipNames: turn.chips.map(\.name),
                        live: false
                    )
                )
            case .assistant:
                rows.append(
                    TranscriptRow(kind: .assistant, text: turn.text, chipNames: [], live: false)
                )
            }
        }
        if session.phase == .waiting || session.phase == .streaming {
            rows.append(
                TranscriptRow(kind: .assistant, text: session.displayAnswer, chipNames: [], live: true)
            )
        }
        if expanded {
            return rows
        }
        if let last = rows.last(where: { $0.kind == .assistant }) {
            return [last]
        }
        return []
    }
}
