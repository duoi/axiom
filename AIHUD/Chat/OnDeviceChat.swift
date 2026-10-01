import Foundation
import FoundationModels
import ImageIO

enum OnDeviceChat {
    static var availability: OnDeviceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .notEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .notReady
        case .unavailable:
            return .other
        @unknown default:
            return .other
        }
    }

    static var supportsImages: Bool {
        if #available(macOS 27.0, *) {
            return true
        }
        return false
    }

    static func stream(messages: [OutboundMessage]) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let message = ChatRouting.message(for: availability) {
                        continuation.yield(.failure(message))
                        continuation.finish()
                        return
                    }

                    let prepared = try prepare(messages)
                    let session = prepared.session
                    let prompt = prepared.prompt
                    let images = prepared.images
                    let stream: LanguageModelSession.ResponseStream<String>
                    if images.isEmpty {
                        stream = session.streamResponse(to: prompt)
                    } else if #available(macOS 27.0, *) {
                        var attachments: [CGImage] = []
                        for jpeg in images {
                            guard let image = cgImage(from: jpeg) else {
                                continuation.yield(.failure(ChatRouting.cannotTakeImage))
                                continuation.finish()
                                return
                            }
                            attachments.append(image)
                        }
                        stream = session.streamResponse {
                            prompt
                            for image in attachments {
                                Attachment(image)
                            }
                        }
                    } else {
                        continuation.yield(.failure(ChatRouting.cannotTakeImage))
                        continuation.finish()
                        return
                    }

                    var seen = ""
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        let text = snapshotText(snapshot)
                        if text.hasPrefix(seen) {
                            let token = String(text.dropFirst(seen.count))
                            if !token.isEmpty {
                                continuation.yield(.token(token))
                            }
                        } else if !text.isEmpty {
                            continuation.yield(.token(text))
                        }
                        seen = text
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(.failure(String(localized: "The on-device model failed.")))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private struct Prepared {
        var session: LanguageModelSession
        var prompt: String
        var images: [Data]
    }

    private static func prepare(_ messages: [OutboundMessage]) throws -> Prepared {
        var system = ""
        var turns: [OutboundMessage] = []
        for message in messages {
            if message.role == "system", system.isEmpty, turns.isEmpty {
                system = message.text
            } else {
                turns.append(message)
            }
        }
        guard let current = turns.popLast() else {
            throw OnDeviceChatError.empty
        }
        var entries: [FoundationModels.Transcript.Entry] = []
        if !system.isEmpty {
            entries.append(
                .instructions(
                    FoundationModels.Transcript.Instructions(
                        segments: [.text(FoundationModels.Transcript.TextSegment(content: system))],
                        toolDefinitions: []
                    )
                )
            )
        }
        for turn in turns {
            let segment = FoundationModels.Transcript.Segment.text(
                FoundationModels.Transcript.TextSegment(content: turn.text)
            )
            if turn.role == "assistant" {
                entries.append(
                    .response(FoundationModels.Transcript.Response(assetIDs: [], segments: [segment]))
                )
            } else {
                entries.append(
                    .prompt(FoundationModels.Transcript.Prompt(segments: [segment]))
                )
            }
        }
        let session: LanguageModelSession
        if entries.isEmpty {
            session = LanguageModelSession(instructions: system)
        } else {
            session = LanguageModelSession(
                model: .default,
                tools: [],
                transcript: FoundationModels.Transcript(entries: entries)
            )
        }
        return Prepared(session: session, prompt: current.text, images: current.imageJPEGs)
    }

    private static func snapshotText(
        _ snapshot: LanguageModelSession.ResponseStream<String>.Snapshot
    ) -> String {
        snapshot.content
    }

    private static func cgImage(from jpeg: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

private enum OnDeviceChatError: Error {
    case empty
}
