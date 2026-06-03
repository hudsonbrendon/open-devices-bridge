import Foundation

/// Converts an arbitrary device name into an MQTT/HA-safe object id:
/// lowercase, non-alphanumeric runs collapsed to a single underscore,
/// leading/trailing underscores trimmed.
///
///     slugify("MX Keys Mini")  == "mx_keys_mini"
///     slugify("MX Master 3!")  == "mx_master_3"
public func slugify(_ name: String) -> String {
    var out = ""
    var lastWasUnderscore = false
    for ch in name.lowercased() {
        if ch.isLetter || ch.isNumber {
            out.append(ch)
            lastWasUnderscore = false
        } else if !lastWasUnderscore {
            out.append("_")
            lastWasUnderscore = true
        }
    }
    while out.hasPrefix("_") { out.removeFirst() }
    while out.hasSuffix("_") { out.removeLast() }
    return out.isEmpty ? "device" : out
}
