import Foundation

struct AIRecap: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var readID: UUID
    var sessionID: UUID
    var sessionStartedAt: Date
    var sessionEndedAt: Date
    var sourceStartWordIndex: Int
    var sourceEndWordIndex: Int
    var generatedText: String
    var createdAt: Date
    var inputWordCount: Int
    var outputWordCount: Int
    var modelName: String
    var modelVersion: String

    init(
        id: UUID = UUID(),
        readID: UUID,
        sessionID: UUID,
        sessionStartedAt: Date,
        sessionEndedAt: Date,
        sourceStartWordIndex: Int,
        sourceEndWordIndex: Int,
        generatedText: String,
        createdAt: Date = Date(),
        inputWordCount: Int,
        outputWordCount: Int,
        modelName: String,
        modelVersion: String
    ) {
        self.id = id
        self.readID = readID
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        self.sessionEndedAt = sessionEndedAt
        self.sourceStartWordIndex = max(sourceStartWordIndex, 0)
        self.sourceEndWordIndex = max(sourceEndWordIndex, self.sourceStartWordIndex)
        self.generatedText = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.inputWordCount = max(inputWordCount, 0)
        self.outputWordCount = max(outputWordCount, 0)
        self.modelName = modelName
        self.modelVersion = modelVersion
    }

    var sourceWordRange: Range<Int> {
        sourceStartWordIndex..<sourceEndWordIndex
    }
}
