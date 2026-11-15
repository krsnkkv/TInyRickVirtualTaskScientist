import Cocoa
import ServiceManagement

// Rick: a pixel pet that wanders your screen. Click it to open your
// Urgent/Important list, which is saved automatically.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pet = PetController()
    private let matrix = MatrixController()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // Global shortcuts: ⌃⌘R = send Rick away / bring him back, ⌃⌘C = open/close the checklist
        HotKeys.controlCommand(.r) { [weak self] in self?.toggleHidden() }
        HotKeys.controlCommand(.c) { [weak self] in self?.toggleList() }

        pet.start()
    }

    func applicationWillTerminate(_ notification: Notification) { matrix.flush() }

    /// A (hidden) main menu so the usual editing shortcuts work in the list, plus ⌘⇧X = mark done.
    private func buildEditMenu() {
        let main = NSMenu()
        let appItem = main.addItem(withTitle: "Rick", action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu(title: "Rick")
        appItem.submenu?.addItem(withTitle: "Quit Rick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🧪"
        addShortcutItem("Open / Close My List", #selector(toggleList), "c")
        menu.addItem(withTitle: "What's Due Soon?", action: #selector(remind), keyEquivalent: "").target = self
        addShortcutItem("Hide / Show Rick", #selector(toggleHidden), "r")
        menu.addItem(.separator())
        addToggle("Mute Rick", #selector(toggleMute), pet.muted)
        addToggle("Stay Still", #selector(toggleStill), pet.stayStill)
        addToggle("Anti-Gravity", #selector(toggleGravity), pet.antiGravity)
        addToggle("ADHD Mode", #selector(toggleADHD), pet.adhd)
        menu.addItem(withTitle: "Loner Rick", action: #selector(demoSad), keyEquivalent: "").target = self
        menu.addItem(.separator())

        // Options: set-and-forget stuff, tucked away
        let options = NSMenu(title: "Options")
        func add(_ title: String, _ action: Selector) { options.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
        add("Choose Sprite…", #selector(chooseSprite))
        add("Use Built-in Look", #selector(resetSprite))
        options.addItem(.separator())
        add("Choose List Background…", #selector(chooseBackground))
        add("Remove List Background", #selector(removeBackground))
        add("Show List File in Finder", #selector(revealFile))
        options.addItem(.separator())
        let login = options.addItem(withTitle: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add("Restart Rick", #selector(restart))
        menu.addItem(withTitle: "Options", action: nil, keyEquivalent: "").submenu = options

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Rick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
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
