import Foundation

public struct HandoffItem: Identifiable, Sendable {
    public let id: UUID
    public var sourceID: UUID?
    public var spec: DeliverySpec
    public init(sourceID: UUID?, spec: DeliverySpec) {
        self.id = UUID(); self.sourceID = sourceID; self.spec = spec
    }
}

public enum HandoffBriefParser {
    /// One version per line. Never guess between multiple matching filenames.
    public static func parse(_ text: String, assets: [ProjectAsset], defaultSource: UUID?, base: DeliverySpec) -> (items: [HandoffItem], warnings: [String]) {
        var items: [HandoffItem] = []
        var warnings: [String] = []
        for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let result = BriefParser.parse(String(line), base: base)
            let matches = assets.filter { $0.isAudio && line.localizedCaseInsensitiveContains($0.name) }
            let source = matches.count == 1 ? matches[0].id : (matches.isEmpty ? defaultSource : nil)
            items.append(HandoffItem(sourceID: source, spec: result.spec))
            if matches.count != 1 { warnings.append("Line \(index + 1): \(matches.isEmpty ? "using the selected source; check it matches the brief." : "multiple source filenames found; select a source manually.")") }
            warnings += result.warnings.map { "Line \(index + 1): " + $0 }
        }
        return (items, warnings)
    }
}
