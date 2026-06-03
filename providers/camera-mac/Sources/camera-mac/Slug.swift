import Foundation

// Lowercase alphanumeric+hyphen id, e.g. "Logitech BRIO" -> "logitech-brio".
func slug(_ s: String) -> String {
    var out = ""
    var lastDash = false
    for ch in s.lowercased() {
        if ch.isLetter || ch.isNumber {
            out.append(ch); lastDash = false
        } else if !lastDash {
            out.append("-"); lastDash = true
        }
    }
    let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "camera" : trimmed
}

// Stable unique ids for a list of names; duplicates get a -2, -3, … suffix.
func uniqueIDs(_ names: [String]) -> [String] {
    var seen: [String: Int] = [:]
    var out: [String] = []
    for n in names {
        let base = slug(n)
        let count = seen[base, default: 0] + 1
        seen[base] = count
        out.append(count == 1 ? base : "\(base)-\(count)")
    }
    return out
}
