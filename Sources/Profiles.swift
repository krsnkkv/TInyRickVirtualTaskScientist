import Cocoa

/// A character the pet can be: look (sprite), voice (Personality.md) and its own settings.
///
/// A profile is a folder containing:
///     profile.json      { "name": "Rick", "icon": "🧪" }
///     Personality.md    what it says (see the file for the format)
///     sprite.png        optional sprite / sprite sheet (none = the built-in drawn look)
///     sprite.json       optional row mapping for the sheet
///
/// Built-in profiles ship inside the app (Resources/Profiles). Your own live in
/// ~/Library/Application Support/MochiPet/profiles/ and win if they share a folder name.
struct Profile: Equatable {
    let id: String          // folder name
    let dir: URL
    let builtIn: Bool
    var name: String
    var icon: String

    var personalityFile: URL { dir.appendingPathComponent("Personality.md") }
    var spriteFile: URL { dir.appendingPathComponent("sprite.png") }
    var mappingFile: URL { dir.appendingPathComponent("sprite.json") }
}

enum Profiles {
    static var userDir: URL { MatrixStore.dir.appendingPathComponent("profiles") }
    static var bundleDir: URL? {
        ProcessInfo.processInfo.environment["RICK_PROFILES_DIR"].map { URL(fileURLWithPath: $0) }   // tests / dev
            ?? Bundle.main.resourceURL?.appendingPathComponent("Profiles")
    }
    static let defaultID = "mochi"
    private static let activeKey = "activeProfile"

    // MARK: listing

    static func all() -> [Profile] {
        var byID: [String: Profile] = [:]
        for (dir, builtIn) in [(bundleDir, true), (userDir, false)] {
            guard let dir, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for id in names where !id.hasPrefix(".") {
                if let p = read(dir.appendingPathComponent(id), id: id, builtIn: builtIn) { byID[id] = p }
            }
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func read(_ dir: URL, id: String, builtIn: Bool) -> Profile? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let info = (try? Data(contentsOf: dir.appendingPathComponent("profile.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return Profile(id: id, dir: dir, builtIn: builtIn,
                       name: info["name"] as? String ?? id.capitalized,
                       icon: info["icon"] as? String ?? "🙂")
    }

    // MARK: the active one

    static var activeID: String {
        get { UserDefaults.standard.string(forKey: activeKey) ?? defaultID }
        set { UserDefaults.standard.set(newValue, forKey: activeKey) }
    }

    static var active: Profile {
        let list = all()
        return list.first { $0.id == activeID } ?? list.first { $0.id == defaultID } ?? list.first
            ?? Profile(id: defaultID, dir: userDir.appendingPathComponent(defaultID), builtIn: false, name: "Mochi", icon: "🌱")
    }

    /// Settings key for the active profile, e.g. "rick.muted".
    static func key(_ setting: String) -> String { "\(activeID).\(setting)" }

    // MARK: making and changing profiles

    /// A built-in profile is read-only (inside the app). Before changing it (new sprite, edited
    /// personality) we copy it into your profiles folder; your copy then takes over.
    @discardableResult
    static func writable(_ p: Profile) -> Profile {
        guard p.builtIn else { return p }
        let dest = userDir.appendingPathComponent(p.id)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: p.dir, to: dest)
        }
        return read(dest, id: p.id, builtIn: false) ?? p
    }

    /// Creates a new profile (personality copied from `template`) and returns it.
    static func create(name: String, icon: String = "🙂", template: Profile?) -> Profile? {
        var slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        slug = slug.split(separator: "-").joined(separator: "-")
        if slug.isEmpty { slug = "profile" }
        var id = slug, n = 2
        while all().contains(where: { $0.id == id }) { id = "\(slug)-\(n)"; n += 1 }

        let dir = userDir.appendingPathComponent(id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let info = try JSONSerialization.data(withJSONObject: ["name": name, "icon": icon], options: [.prettyPrinted, .sortedKeys])
            try info.write(to: dir.appendingPathComponent("profile.json"))
            if let t = template, FileManager.default.fileExists(atPath: t.personalityFile.path) {
                try FileManager.default.copyItem(at: t.personalityFile, to: dir.appendingPathComponent("Personality.md"))
            }
        } catch {
            NSLog("Rick: couldn't create profile: \(error)")
            return nil
        }
        return read(dir, id: id, builtIn: false)
    }

    /// One-time move from the single-character setup to profiles:
    /// an existing sprite (and personality override) becomes a "Rick" profile, with your settings.
    static func migrateIfNeeded() {
        let fm = FileManager.default
        let base = MatrixStore.dir
        let oldSprite = base.appendingPathComponent("sprite.png")
        guard UserDefaults.standard.string(forKey: activeKey) == nil else { return }    // already on profiles
        guard fm.fileExists(atPath: oldSprite.path) else { return }                     // nothing to bring over

        let template = all().first { $0.id == defaultID }
        guard let rick = create(name: "Rick", icon: "🧪", template: template) else { return }
        for file in ["sprite.png", "sprite.json"] {
            let from = base.appendingPathComponent(file)
            if fm.fileExists(atPath: from.path) { try? fm.moveItem(at: from, to: rick.dir.appendingPathComponent(file)) }
        }
        let oldPersonality = base.appendingPathComponent("Personality.md")
        if fm.fileExists(atPath: oldPersonality.path) {
            try? fm.removeItem(at: rick.personalityFile)
            try? fm.moveItem(at: oldPersonality, to: rick.personalityFile)
        }
        // carry the old (global) settings over to Rick
        let d = UserDefaults.standard
        for k in ["muted", "stayStill", "antiGravity", "adhd"] where d.object(forKey: k) != nil {
            d.set(d.bool(forKey: k), forKey: "\(rick.id).\(k)")
        }
        activeID = rick.id
    }
}
