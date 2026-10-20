import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CryptoKit

final class Feed: NSObject, XMLParserDelegate {
    var enclosure: [String: String] = [:]
    var values: [String: String] = [:]
    var items = 0
    private var current = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        current = name
        if name == "item" { items += 1 }
        if name == "enclosure" { enclosure = attributes }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) { values[current, default: ""] += text }
}
func require(_ condition: Bool, _ reason: String) throws {
    if !condition { throw NSError(domain: "LaunchDock.Release", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
}
do {
    guard CommandLine.arguments.count == 4 else { throw NSError(domain: "usage: check-update.swift appcast.xml archive.zip Sparkle.plist", code: 2) }
    let xml = URL(fileURLWithPath: CommandLine.arguments[1]), archive = URL(fileURLWithPath: CommandLine.arguments[2])
    let settings = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])), format: nil) as! [String: Any]
    let feed = Feed(), parser = XMLParser(data: try Data(contentsOf: xml))
    parser.delegate = feed
    try require(parser.parse() && feed.items == 1, "Appcast must contain one valid release item")
    let data = try Data(contentsOf: archive)
    try require(Int(feed.enclosure["length"] ?? "") == data.count, "Archive length does not match appcast")
    guard let key = Data(base64Encoded: settings["SUPublicEDKey"] as? String ?? ""),
          let signature = Data(base64Encoded: feed.enclosure["sparkle:edSignature"] ?? "") else {
        throw NSError(domain: "Missing Ed25519 public key or signature", code: 3)
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    try require(publicKey.isValidSignature(signature, for: data), "Archive signature is invalid")
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-p", archive.path, "LaunchDock.app/Contents/Info.plist"]
    process.standardOutput = pipe
    try process.run()
    let infoData = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "Archive does not contain LaunchDock.app")
    let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
    try require(info["CFBundleIdentifier"] as? String == "local.launchdock.app", "Unexpected app identifier")
    try require(info["SUPublicEDKey"] as? String == settings["SUPublicEDKey"] as? String, "Embedded public key mismatch")
    let version = info["CFBundleShortVersionString"] as? String ?? ""
    let build = info["CFBundleVersion"] as? String ?? ""
    try require(feed.values["sparkle:version"]?.trimmingCharacters(in: .whitespacesAndNewlines) == build, "Build mismatch")
    try require(feed.values["sparkle:shortVersionString"]?.trimmingCharacters(in: .whitespacesAndNewlines) == version, "Version mismatch")
    let expectedURL = "https://github.com/Hassanzhang/Launch-Dock/releases/download/v\(version)/\(archive.lastPathComponent)"
    try require(feed.enclosure["url"] == expectedURL, "Release download URL mismatch")
    try require(info["SUFeedURL"] as? String == settings["SUFeedURL"] as? String, "Feed URL mismatch")
    print("PASS appcast XML, version/build, download URL, archive length and Ed25519 signature")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
