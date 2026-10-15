import Foundation

/// Read complete log lines only, so a split URL/port cannot become a stale link.
public func frontendURL(in output: String) -> URL? {
    let plain = output.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    let complete = plain.components(separatedBy: .newlines).dropLast().joined(separator: "\n")
    guard let pattern = try? NSRegularExpression(pattern: #"https?://[^\s<>"'\x1B]+"#, options: .caseInsensitive) else { return nil }
    for match in pattern.matches(in: complete, range: NSRange(complete.startIndex..., in: complete)) {
        guard let range = Range(match.range, in: complete) else { continue }
        let text = String(complete[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)}"))
        guard var address = URLComponents(string: text), let host = address.host?.lowercased(),
              address.user == nil, address.password == nil else { continue }
        if let port = address.port, !(1...65535).contains(port) { continue }
        switch host {
        case "localhost", "127.0.0.1", "::1", "[::1]": break
        case "0.0.0.0", "::", "[::]": address.host = "localhost"
        default: continue
        }
        if let url = address.url { return url }
    }
    return nil
}
