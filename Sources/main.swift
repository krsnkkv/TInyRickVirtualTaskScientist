import Cocoa
import ServiceManagement
import EventKit

// Rick: a pixel pet that wanders your screen. Click it to open your
// Urgent/Important list, which is saved automatically.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pet = PetController()
    private let matrix = MatrixController()
    private let calendar = CalendarSync()
    private var calendarTimer: Timer?
    private var announced = Set<String>()          // meeting heads-ups already given ("id|soon", "id|now")
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Profiles.migrateIfNeeded()            // one-time: old single-character setup → profiles
        Personality.reload()
        pet.reloadSettings()
        buildMenu()
        buildEditMenu()

        pet.onClick = { [weak self] in
            guard let self else { return }
            self.matrix.toggle(near: self.pet.window.frame)
        }
        pet.onRightClick = { [weak self] e in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.menu, with: e, for: self.pet.view)
        }
        pet.reminder = { [weak self] in self?.matrix.nextReminder() }
        pet.setSprite(SpriteStore.load())
        matrix.onVisibility = { [weak self] open in
            guard let self else { return }
            self.pet.chatOpen = open
            self.pet.touched()
            self.pet.say(Personality.line(open ? .listOpened : .listClosed), for: 3.5)
            if !open { self.pet.celebrate() }
        }

        // Calendar: Today strip, two-way sync for linked tasks, heads-ups before meetings
        calendar.onChange = { [weak self] in self?.refreshCalendar() }
        matrix.onAddToCalendar = { [weak self] task in self?.addToCalendar(task) }
        refreshCalendar()
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.calendarTick() }
        calendarTimer?.tolerance = 10
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            self?.announced.removeAll(); self?.refreshCalendar()
        }

        // Global shortcuts: ⌃⌘R = send Rick away / bring him back, ⌃⌘C = open/close the checklist
        HotKeys.controlCommand(.r) { [weak self] in self?.toggleHidden() }
        HotKeys.controlCommand(.c) { [weak self] in self?.toggleList() }

        pet.start()
    }

    func applicationWillTerminate(_ notification: Notification) { matrix.flush() }

    /// A (hidden) main menu so the usual editing shortcuts work in the list, plus ⌘⇧X = mark done.
    private func buildEditMenu() {
        let main = NSMenu()
        let appItem = main.addItem(withTitle: "Pet", action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu(title: "Pet")
        appItem.submenu?.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Mark Done / Not Done", action: #selector(ListTextView.toggleDone(_:)), keyEquivalent: "X")
        edit.addItem(withTitle: "Add to Calendar", action: #selector(ListTextView.addToCalendar(_:)), keyEquivalent: "E")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        rebuildMenu()
    }

    /// (Re)builds the 🧪 menu for the active profile: its name and icon appear throughout.
    private func rebuildMenu() {
        let p = Profiles.active
        statusItem.button?.title = p.icon
        matrix.panel.title = "\(p.name)'s List \(p.icon)"
        menu.removeAllItems()

        addShortcutItem("Open / Close My List", #selector(toggleList), "c")
        menu.addItem(withTitle: "What's Due Soon?", action: #selector(remind), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Clean Up Done Tasks", action: #selector(cleanUp), keyEquivalent: "").target = self
        addShortcutItem("Hide / Show \(p.name)", #selector(toggleHidden), "r")
        menu.addItem(.separator())
        addToggle("Mute \(p.name)", #selector(toggleMute), pet.muted)
        addToggle("Stay Still", #selector(toggleStill), pet.stayStill)
        addToggle("Anti-Gravity", #selector(toggleGravity), pet.antiGravity)
        addToggle("ADHD Mode", #selector(toggleADHD), pet.adhd)
        menu.addItem(withTitle: "Loner \(p.name)", action: #selector(demoSad), keyEquivalent: "").target = self
        menu.addItem(.separator())

        menu.addItem(withTitle: "Calendar", action: nil, keyEquivalent: "").submenu = calendarMenu()

        // Profile: who the pet is
        let profiles = NSMenu(title: "Profile")
        for other in Profiles.all() {
            let item = profiles.addItem(withTitle: "\(other.icon)  \(other.name)", action: #selector(switchProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = other.id
            item.state = other.id == p.id ? .on : .off
        }
        profiles.addItem(.separator())
        func addP(_ title: String, _ action: Selector) { profiles.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
        addP("New Profile…", #selector(newProfile))
        addP("Edit \(p.name)'s Personality…", #selector(editPersonality))
        addP("Choose Sprite…", #selector(chooseSprite))
        addP("Use Built-in Look", #selector(resetSprite))
        addP("Show Profiles Folder", #selector(revealProfiles))
        menu.addItem(withTitle: "Profile: \(p.name)", action: nil, keyEquivalent: "").submenu = profiles

        // Options: set-and-forget stuff, tucked away
        let options = NSMenu(title: "Options")
        func add(_ title: String, _ action: Selector) { options.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
        add("Choose List Background…", #selector(chooseBackground))
        add("Remove List Background", #selector(removeBackground))
        add("Show List File in Finder", #selector(revealFile))
        options.addItem(.separator())
        let login = options.addItem(withTitle: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add("Restart \(p.name)", #selector(restart))
        menu.addItem(withTitle: "Options", action: nil, keyEquivalent: "").submenu = options

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: calendar

    private func calendarMenu() -> NSMenu {
        let m = NSMenu(title: "Calendar")
        func item(_ title: String, _ action: Selector?, on: Bool? = nil, object: Any? = nil, indent: Int = 0) {
            let i = m.addItem(withTitle: title, action: action, keyEquivalent: "")
            i.target = action == nil ? nil : self
            i.representedObject = object
            i.indentationLevel = indent
            if let on { i.state = on ? .on : .off }
        }
        guard calendar.isConnected else {
            if calendar.wasDenied {
                item("Calendar Access Is Off: Open Settings…", #selector(openCalendarPrivacy))
            } else {
                item("Connect Calendar…", #selector(connectCalendar))
            }
            m.addItem(.separator())
            item("Tip: add Google in System Settings ▸ Internet Accounts", nil)
            return m
        }
        item("Add Selected Task to Calendar", #selector(addSelectedToCalendar))
        m.items.last?.keyEquivalent = "E"
        m.items.last?.keyEquivalentModifierMask = [.command, .shift]
        m.addItem(.separator())
        item("Show Today in List", #selector(toggleShowToday), on: calendar.showToday)
        item("Heads-Up Before Meetings", #selector(toggleHeadsUp), on: calendar.headsUp)
        m.addItem(.separator())
        item("Show Events From:", nil)
        for c in calendar.calendars {
            item(c.title, #selector(toggleCalendarShown(_:)), on: !calendar.hiddenCalendarIDs.contains(c.calendarIdentifier),
                 object: c.calendarIdentifier, indent: 1)
            if let color = c.color { m.items.last?.attributedTitle = dot(color, c.title) }
        }
        m.addItem(.separator())
        let target = NSMenu(title: "Add Tasks To")
        for c in calendar.calendars where c.allowsContentModifications {
            let i = target.addItem(withTitle: c.title, action: #selector(setTargetCalendar(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = c.calendarIdentifier
            i.state = c.calendarIdentifier == calendar.targetCalendar?.calendarIdentifier ? .on : .off
        }
        m.addItem(withTitle: "Add Tasks To", action: nil, keyEquivalent: "").submenu = target
        return m
    }

    private func dot(_ color: NSColor, _ title: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: color, .font: NSFont.menuFont(ofSize: 0)])
        s.append(NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        return s
    }

    @objc private func connectCalendar() {
        NSApp.activate(ignoringOtherApps: true)
        calendar.connect { [weak self] ok in
            guard let self else { return }
            self.pet.say(Personality.line(ok ? .calendarConnected : .calendarDenied), for: 5)
            self.rebuildMenu()
            self.refreshCalendar()
        }
    }

    @objc private func openCalendarPrivacy() { calendar.openPrivacySettings() }
    @objc private func toggleShowToday() { calendar.showToday.toggle(); rebuildMenu(); refreshCalendar() }
    @objc private func toggleHeadsUp() { calendar.headsUp.toggle(); rebuildMenu() }

    @objc private func toggleCalendarShown(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        var hidden = calendar.hiddenCalendarIDs
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        calendar.hiddenCalendarIDs = hidden
        rebuildMenu(); refreshCalendar()
    }

    @objc private func setTargetCalendar(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        calendar.targetCalendar = calendar.store.calendar(withIdentifier: id)
        rebuildMenu()
    }

    @objc private func addSelectedToCalendar() { addToCalendar(matrix.selectedTask()) }

    /// Creates an event for the task (or tells you why it can't).
    private func addToCalendar(_ task: TaskItem?) {
        if !pet.isShown { pet.show() }
        guard calendar.isConnected else { connectCalendar(); return }
        guard let task, task.due != nil else { pet.say(Personality.line(.needsDate), for: 5); return }
        let name = DueParser.stripDateAndTimeWords(task.title)
        if let existing = task.externalID, calendar.eventInfo(existing) != nil {
            pet.say(Personality.line(.addedToCalendar, item: name, when: whenText(task)), for: 4)
            return                                                   // already there
        }
        do {
            let id = try calendar.addEvent(for: task)
            matrix.link(task.id, toEvent: id)
            pet.say(Personality.line(.addedToCalendar, item: name, when: whenText(task)), for: 5)
            refreshCalendar()
        } catch {
            pet.say(error.localizedDescription, for: 5)
        }
    }

    private func whenText(_ t: TaskItem) -> String {
        guard let due = t.due else { return "" }
        let day = DueParser.describe(due)
        return t.time.map { "\(day) at \(DueParser.timeLabel($0))" } ?? day
    }

    /// Re-reads the calendar: syncs linked tasks and fills the Today strip.
    private func refreshCalendar() {
        guard calendar.isConnected else { matrix.setToday([]); return }
        matrix.reconcile(with: calendar)
        matrix.setToday(calendar.showToday ? calendar.today() : [])
    }

    /// Once a minute: heads-up before meetings. Does nothing while the pet is hidden.
    private func calendarTick() {
        guard pet.isShown, calendar.isConnected, calendar.headsUp else { return }
        let now = Date()
        let soon = calendar.events(from: now.addingTimeInterval(-60), to: now.addingTimeInterval(Double(calendar.headsUpMinutes + 1) * 60))
        for e in soon where !e.allDay {
            let minutes = Int((e.start.timeIntervalSince(now) / 60).rounded())
            if minutes <= 0, minutes >= -1, announced.insert(e.id + "|now").inserted {
                pet.say(Personality.line(.meetingNow, item: e.title), for: 7)
                pet.touched()
            } else if minutes > 0, minutes <= calendar.headsUpMinutes, announced.insert(e.id + "|soon").inserted {
                pet.say(Personality.line(.meetingSoon, item: e.title, when: "in \(minutes) minute\(minutes == 1 ? "" : "s")"), for: 7)
            }
        }
        matrix.setToday(calendar.showToday ? calendar.today() : [])  // dims meetings that are over
    }

    // MARK: profiles

    @objc private func switchProfile(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, id != Profiles.activeID else { return }
        activate(id)
    }

    /// Makes a profile the active one: new look, voice and settings, right away.
    private func activate(_ id: String) {
        Profiles.activeID = id
        Personality.reload()
        pet.setSprite(SpriteStore.load())
        pet.reloadSettings()
        rebuildMenu()
        if !pet.isShown { pet.show() }
        pet.say(Personality.line(.greeting), for: 5)
    }

    @objc private func newProfile() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "New profile"
        alert.informativeText = "Give your new character a name and a menu-bar emoji. It starts with Mochi's personality; edit it afterwards with “Edit Personality…”."
        let name = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        name.placeholderString = "Name (e.g. Coach)"
        let icon = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
        icon.placeholderString = "🙂"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        box.addSubview(name); box.addSubview(icon)
        alert.accessoryView = box
        alert.addButton(withTitle: "Create & Choose Sprite…")
        alert.addButton(withTitle: "Create (Built-in Look)")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        let choice = alert.runModal()
        guard choice != .alertThirdButtonReturn else { return }
        let title = name.stringValue.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let emoji = icon.stringValue.trimmingCharacters(in: .whitespaces)
        let template = Profiles.all().first { $0.id == Profiles.defaultID }
        guard let created = Profiles.create(name: title, icon: emoji.isEmpty ? "🙂" : emoji, template: template) else { return }
        activate(created.id)
        if choice == .alertFirstButtonReturn { chooseSprite() }
    }

    @objc private func editPersonality() {
        let p = Profiles.writable(Profiles.active)          // built-ins get a personal copy to edit
        NSWorkspace.shared.open(p.personalityFile)
        pet.say("Edit away, then pick \"Restart \(p.name)\" from Options to hear it.", for: 5)
    }

    @objc private func revealProfiles() {
        try? FileManager.default.createDirectory(at: Profiles.userDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Profiles.userDir)
    }

    /// Menu item that shows its global ⌃⌘ shortcut.
    private func addShortcutItem(_ title: String, _ action: Selector, _ key: String) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.control, .command]
        item.target = self
    }

    /// Quit and reopen (fresh start: lands again, re-reads Personality.md and the sprite).
    @objc private func restart() {
        matrix.flush()
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    /// Loner Rick: the "ignored for a while" sulk, right now. Hover or click him to cheer him up.
    @objc private func demoSad() {
        if !pet.isShown { pet.show() }
        // Wait for the menu to close (and the mouse to leave him), or the hover would cancel it at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.pet.sulk() }
    }

    /// Clears struck-through tasks out of the list (kept in done-log.json).
    @objc private func cleanUp() {
        if !pet.isShown { pet.show() }
        let n = matrix.cleanUpDone()
        pet.say(n == 0 ? Personality.line(.cleanNothing) : Personality.line(.cleaned, item: "\(n)"), for: 4)
    }

    @objc private func toggleList() {
        if matrix.isOpen { matrix.toggle(near: pet.window.frame) } else { openList() }
    }

    @objc private func toggleLogin(_ item: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Rick: login item change failed: \(error)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        item.state = service.status == .enabled ? .on : .off
    }

    private func addToggle(_ title: String, _ action: Selector, _ on: Bool) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
    }

    @objc private func toggleMute(_ item: NSMenuItem) {
        pet.muted.toggle(); item.state = pet.muted ? .on : .off
    }
    @objc private func toggleStill(_ item: NSMenuItem) {
        pet.stayStill.toggle(); item.state = pet.stayStill ? .on : .off
    }
    @objc private func toggleGravity(_ item: NSMenuItem) {
        pet.antiGravity.toggle(); item.state = pet.antiGravity ? .on : .off
    }
    @objc private func toggleADHD(_ item: NSMenuItem) {
        pet.adhd.toggle(); item.state = pet.adhd ? .on : .off
    }

    @objc private func openList() {
        if !pet.isShown { pet.show() }
        matrix.show(near: pet.window.frame)
    }
    @objc private func toggleHidden() {
        if pet.isShown {
            pet.hide()
        } else {
            pet.show()
            pet.say(Personality.line(.summoned), for: 3)
        }
    }
    @objc private func remind() {
        if !pet.isShown { pet.show() }
        let items = matrix.rundown()
        if items.isEmpty {
            pet.sayInOrder([Personality.line(.rundownEmpty)], each: 4)
        } else {
            pet.sayInOrder([Personality.line(.rundownStart)] + items + [Personality.line(.rundownEnd)], each: 3.5)
        }
    }
    @objc private func chooseSprite() {
        NSApp.activate(ignoringOtherApps: true)
        let open = NSOpenPanel()
        open.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        open.message = "Pick a pixel-art sprite facing right. A solid background is removed automatically."
        guard open.runModal() == .OK, let url = open.url else { return }
        let set = SpriteStore.install(from: url)
        if !set.isEmpty {
            pet.setSprite(set)
            pet.say(Personality.line(.newSprite), for: 4)
        } else {
            pet.say("Hmm, I couldn't read that image 😕", for: 4)
        }
    }
    @objc private func chooseBackground() {
        NSApp.activate(ignoringOtherApps: true)
        let open = NSOpenPanel()
        open.allowedContentTypes = [.png, .jpeg, .webP, .heic, .gif]
        open.message = "Pick a picture to show behind your list."
        guard open.runModal() == .OK, let url = open.url else { return }
        if matrix.setBackground(from: url) {
            openList()
        } else {
            pet.say("Hmm, I couldn't read that image 😕", for: 4)
        }
    }
    @objc private func removeBackground() { matrix.setBackground(from: nil) }

    @objc private func resetSprite() {
        SpriteStore.remove()
        pet.setSprite(SpriteSet())
    }
    @objc private func revealFile() {
        matrix.flush()
        NSWorkspace.shared.activateFileViewerSelecting([MatrixStore.file])
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
