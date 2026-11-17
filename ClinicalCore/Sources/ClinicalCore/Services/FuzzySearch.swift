import Foundation

/// Lightweight, offline fuzzy search tolerant of typos and missing diacritics
/// (e.g. "anafilaksis" ~ "anafilaxis", "stemi", "lukabakar").
public enum FuzzySearch {
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let allowed = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(allowed).split(separator: " ").joined(separator: " ")
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Levenshtein distance with early exit.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Score of one query token against one candidate word (0 = no match).
    static func tokenScore(_ query: String, _ word: String) -> Double {
        if word == query { return 1.0 }
        if word.hasPrefix(query) { return 0.9 }
        if query.count >= 3 && word.contains(query) { return 0.75 }
        if query.count >= 4 {
            let comparable = String(word.prefix(query.count + 1))
            let distance = min(editDistance(query, word), editDistance(query, comparable))
            let allowed = query.count >= 7 ? 2 : 1
            if distance <= allowed { return 0.6 - Double(distance) * 0.1 }
        }
        return 0
    }

    /// Returns a relevance score in 0…1 for `query` against weighted fields. All query tokens must match something.
    public static func score(query: String, fields: [(text: String, weight: Double)]) -> Double {
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else { return 1 }
        let fieldTokens = fields.map { (tokens($0.text), $0.weight) }
        let joinedFields = fields.map { (normalize($0.text).replacingOccurrences(of: " ", with: ""), $0.weight) }

        var total = 0.0
        for token in queryTokens {
            var best = 0.0
            for (words, weight) in fieldTokens {
                for word in words {
                    best = max(best, tokenScore(token, word) * weight)
                }
            }
            // Allow queries that glue words together ("lukabakar", "codestroke").
            if best == 0, token.count >= 5 {
                for (joined, weight) in joinedFields where joined.contains(token) {
                    best = max(best, 0.5 * weight)
                }
            }
            if best == 0 { return 0 }
            total += best
        }
        return total / Double(queryTokens.count)
    }

    public static func searchGuidelines(_ guidelines: [Guideline], query: String) -> [Guideline] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return guidelines }
        let scored: [(Guideline, Double)] = guidelines.map { guideline in
            let body = guideline.sections.flatMap { [$0.title] + $0.items }.joined(separator: " ")
            let relevance = FuzzySearch.score(query: trimmed, fields: [
                (guideline.title, 1.0),
                (guideline.keywords.joined(separator: " "), 0.95),
                (guideline.category.label, 0.7),
                (guideline.summary, 0.6),
                (body, 0.4)
            ])
            return (guideline, relevance)
        }
        let matches = scored.filter { $0.1 > 0 }
        let sorted = matches.sorted { (lhs: (Guideline, Double), rhs: (Guideline, Double)) -> Bool in
            lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.title < rhs.0.title
        }
        return sorted.map { $0.0 }
    }

    public static func searchPediatricDrugs(_ drugs: [PediatricDrug], query: String) -> [PediatricDrug] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return drugs }
        var scored: [(drug: PediatricDrug, score: Double)] = []
        for drug in drugs {
            let indications: String = drug.regimens.map(\.indication).joined(separator: " ")
            let fields: [(text: String, weight: Double)] = [
                (text: drug.name, weight: 1.0),
                (text: drug.category.label, weight: 0.7),
                (text: indications, weight: 0.6)
            ]
            let relevance = FuzzySearch.score(query: trimmed, fields: fields)
            if relevance > 0 { scored.append((drug: drug, score: relevance)) }
        }
        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.drug.name < rhs.drug.name
        }
        return scored.map(\.drug)
    }
}
