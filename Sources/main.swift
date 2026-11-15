import Cocoa

// Mochi: a pixel pet that wanders your screen. Click it to open your
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
        pet.urgentItems = { [weak self] in self?.matrix.urgentItems ?? [] }
        matrix.onVisibility = { [weak self] open in
            self?.pet.chatOpen = open
            if !open { self?.pet.celebrate() }
        }

        pet.start()
    }

    func applicationWillTerminate(_ notification: Notification) { matrix.flush() }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌱"
        menu.addItem(withTitle: "Open My List", action: #selector(openList), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide / Show Mochi", action: #selector(toggleHidden), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show List File in Finder", action: #selector(revealFile), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mochi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openList() {
        if !pet.window.isVisible { pet.window.orderFrontRegardless() }
        matrix.show(near: pet.window.frame)
    }
    @objc private func toggleHidden() {
        if pet.window.isVisible { pet.window.orderOut(nil) } else { pet.window.orderFrontRegardless() }
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
