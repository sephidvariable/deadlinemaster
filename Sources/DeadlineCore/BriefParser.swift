import Foundation

public struct BriefResult: Sendable {
    public let spec: DeliverySpec
    public let detected: [String]
    public let warnings: [String]
}

/// Deliberately deterministic and offline. Ambiguity is surfaced, never silently resolved.
public enum BriefParser {
    public static func parse(_ text: String, base: DeliverySpec = DeliverySpec()) -> BriefResult {
        var spec = base
        var detected: [String] = [], warnings: [String] = []
        func captures(_ pattern: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
            let ns = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
                ns.substring(with: $0.range(at: $0.numberOfRanges > 1 ? 1 : 0))
            }
        }
        let depths = Set(captures(#"\b(16|24)\s*[- ]?bit\b"#).compactMap(Int.init))
        if depths.count == 1, let value = depths.first { spec.bitDepth = value; detected.append("\(value)-bit") }
        if depths.count > 1 { warnings.append("Multiple bit depths requested. Export each deliverable separately.") }
        let rates = captures(#"\b(44[.,]1|48|96)\s*k(?:hz)?\b"#).compactMap { Double($0.replacingOccurrences(of: ",", with: ".")).map { $0 * 1000 } }
            + captures(#"\b(44100|48000|96000)\s*(?:hz)?\b"#).compactMap(Double.init)
        let uniqueRates = Set(rates)
        if uniqueRates.count == 1, let value = uniqueRates.first { spec.sampleRate = value; detected.append("\(value / 1000) kHz") }
        if uniqueRates.count > 1 { warnings.append("Multiple sample rates requested. Choose one for this export.") }
        let mono = !captures(#"\bmono\b"#).isEmpty, stereo = !captures(#"\bstereo\b"#).isEmpty
        if mono && stereo { warnings.append("Both mono and stereo requested. Choose one for this export.") }
        else if mono || stereo { spec.channels = mono ? 1 : 2; detected.append(mono ? "Mono" : "Stereo") }
        if let artist = captures(#"(?:^|[\n;])\s*artist\s*:\s*([^\n;]+)"#).first { spec.artist = artist.trimmingCharacters(in: .whitespaces); detected.append("Artist") }
        if let title = captures(#"(?:^|[\n;])\s*title\s*:\s*([^\n;]+)"#).first { spec.title = title.trimmingCharacters(in: .whitespaces); detected.append("Title") }
        if !captures(#"\bwav\b"#).isEmpty { detected.append("WAV") }
        if !captures(#"\b(mp3|flac|aiff|aac|lufs|dither|normalize|normalise|32\s*[- ]?bit|192\s*k|88[.,]2\s*k)\b|true[ -]?peak"#).isEmpty {
            warnings.append("This brief includes unsupported formats or processing. WAV export alone may not satisfy it.")
        }
        warnings.append("Review every setting. Unspecified or ambiguous settings retain their previous values. This parser does not interpret arbitrary instructions.")
        return BriefResult(spec: spec, detected: detected, warnings: warnings)
    }
}
