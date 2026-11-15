import Cocoa

// Rick: a pixel pet that wanders your screen. Click it to open your
// Urgent/Important list, which is saved automatically.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pet = PetController()
    private let matrix = MatrixController()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

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

        pet.start()
    }

    func applicationWillTerminate(_ notification: Notification) { matrix.flush() }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🧪"
        menu.addItem(withTitle: "Open My List", action: #selector(openList), keyEquivalent: "").target = self
        menu.addItem(withTitle: "What's Due Soon?", action: #selector(remind), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide / Show Rick", action: #selector(toggleHidden), keyEquivalent: "").target = self
        menu.addItem(.separator())
        addToggle("Mute Rick", #selector(toggleMute), pet.muted)
        addToggle("Stay Still", #selector(toggleStill), pet.stayStill)
        addToggle("Anti-Gravity", #selector(toggleGravity), pet.antiGravity)
        addToggle("ADHD Mode", #selector(toggleADHD), pet.adhd)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Choose Sprite…", action: #selector(chooseSprite), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Use Built-in Look", action: #selector(resetSprite), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show List File in Finder", action: #selector(revealFile), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Rick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
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
        if !pet.window.isVisible { pet.window.orderFrontRegardless() }
        matrix.show(near: pet.window.frame)
    }
    @objc private func toggleHidden() {
        if pet.window.isVisible { pet.window.orderOut(nil) } else { pet.window.orderFrontRegardless() }
    }
    @objc private func remind() {
        if !pet.window.isVisible { pet.window.orderFrontRegardless() }
        if !pet.remindNow() { pet.say(Personality.line(.nothingDue), for: 5) }
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
