import Cocoa

// MARK: - Chat window

final class ChatController: NSObject, NSWindowDelegate {
    enum Status { case thinking, talking, done, failed }

    let panel: NSPanel
    private let textView = NSTextView()
    private let input = NSTextField()
    private let sendButton = NSButton()
    private let client = ClaudeClient()
    private var entries: [(isUser: Bool, text: String)] = []

    var onStatus: ((Status) -> Void)?
    var onVisibility: ((Bool) -> Void)?
    var askForKey: (() -> String?)?

    var isOpen: Bool { panel.isVisible }

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "Mochi 🌱"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 300, height: 320)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        buildUI()
        greet()
    }

    private func buildUI() {
        let bg = NSVisualEffectView()
        bg.material = .popover
        bg.blendingMode = .behindWindow
        bg.state = .active
        panel.contentView = bg

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.frame = NSRect(x: 0, y: 0, width: 360, height: 100)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        let clear = NSButton(title: "New", target: self, action: #selector(newChat))
        clear.bezelStyle = .rounded
        clear.toolTip = "Start a new conversation"

        input.placeholderString = "Ask Mochi anything…"
        input.bezelStyle = .roundedBezel
        input.target = self
        input.action = #selector(send)
        input.font = .systemFont(ofSize: 13)

        sendButton.title = "Send"
        sendButton.bezelStyle = .rounded
        sendButton.bezelColor = .systemPink
        sendButton.target = self
        sendButton.action = #selector(send)

        for v in [scroll, clear, input, sendButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bg.addSubview(v)
        }
        clear.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: bg.topAnchor, constant: 30),
            scroll.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: input.topAnchor, constant: -10),

            clear.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 12),
            clear.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            input.leadingAnchor.constraint(equalTo: clear.trailingAnchor, constant: 6),
            input.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -14),
            input.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
            sendButton.leadingAnchor.constraint(equalTo: input.trailingAnchor, constant: 6),
            sendButton.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: input.centerYAnchor),
        ])
    }

    private func greet() {
        entries = [(false, "Hi there! I'm **Mochi** 🌱 What can I help you with today?")]
        render()
    }

    // MARK: show / hide

    func toggle(near petFrame: NSRect) {
        if isOpen { panel.orderOut(nil); onVisibility?(false); return }
        show(near: petFrame)
    }

    func show(near petFrame: NSRect) {
        let vf = (NSScreen.screens.first { $0.frame.intersects(petFrame) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        var x = petFrame.midX - size.width / 2
        var y = petFrame.minY + 150
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(input)
        onVisibility?(true)
    }

    func windowWillClose(_ notification: Notification) { onVisibility?(false) }

    // MARK: actions

    @objc func newChat() {
        client.reset()
        greet()
    }

    @objc private func send() {
        if client.isBusy { client.cancel(); return }
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let key = KeyStore.load() ?? askForKey?() else { return }

        input.stringValue = ""
        entries.append((true, text))
        entries.append((false, ""))
        render()
        setBusy(true)
        onStatus?(.thinking)

        var started = false
        client.send(text, apiKey: key, onText: { [weak self] chunk in
            guard let self else { return }
            if !started { started = true; self.onStatus?(.talking) }
            self.entries[self.entries.count - 1].text += chunk
            self.render()
        }, onDone: { [weak self] error in
            guard let self else { return }
            if let error {
                let i = self.entries.count - 1
                let partial = self.entries[i].text
                self.entries[i].text = partial.isEmpty ? "⚠️ \(error)" : partial + "\n\n⚠️ \(error)"
            }
            self.render()
            self.setBusy(false)
            self.onStatus?(error == nil ? .done : .failed)
        })
    }

    private func setBusy(_ busy: Bool) {
        sendButton.title = busy ? "Stop" : "Send"
    }

    // MARK: rendering

    private func render() {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        let para = NSMutableParagraphStyle(); para.paragraphSpacing = 2; para.lineSpacing = 1.5
        for e in entries {
            out.append(NSAttributedString(string: (e.isUser ? "You" : "🌱 Mochi") + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: e.isUser ? NSColor.systemBlue : NSColor.systemPink,
            ]))
            let text = e.text.isEmpty && !e.isUser ? "…" : e.text
            let md = NSMutableAttributedString(attributedString: markdown(text, font: body))
            md.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: md.length))
            out.append(md)
            out.append(NSAttributedString(string: "\n\n", attributes: [.font: body]))
        }
        textView.textStorage?.setAttributedString(out)
        textView.scrollToEndOfDocument(nil)
    }

    private func markdown(_ s: String, font: NSFont) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        guard let attr = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: s, attributes: base)
        }
        let out = NSMutableAttributedString()
        for run in attr.runs {
            var a = base
            if let intent = run.inlinePresentationIntent {
                var f = font
                if intent.contains(.code) {
                    f = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
                    a[.backgroundColor] = NSColor.quaternaryLabelColor
                }
                if intent.contains(.stronglyEmphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
                a[.font] = f
            }
            if let link = run.link { a[.link] = link }
            out.append(NSAttributedString(string: String(attr[run.range].characters), attributes: a))
        }
        return out
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pet = PetController()
    private let chat = ChatController()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        pet.onClick = { [weak self] in
            guard let self else { return }
            self.chat.toggle(near: self.pet.window.frame)
        }
        pet.onRightClick = { [weak self] e in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.menu, with: e, for: self.pet.view)
        }
        chat.onVisibility = { [weak self] open in self?.pet.chatOpen = open }
        chat.askForKey = { [weak self] in self?.promptForKey() }
        chat.onStatus = { [weak self] status in
            guard let self else { return }
            switch status {
            case .thinking: self.pet.chatMood = .thinking; self.pet.say(nil, for: 0)
            case .talking: self.pet.chatMood = .talking
            case .done: self.pet.chatMood = nil; self.pet.celebrate()
            case .failed: self.pet.chatMood = nil
            }
        }

        pet.start()
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌱"
        menu.addItem(withTitle: "Chat with Mochi", action: #selector(openChat), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Conversation", action: #selector(newChat), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide / Show Mochi", action: #selector(toggleHidden), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Set API Key…", action: #selector(setKey), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mochi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openChat() {
        if !pet.window.isVisible { pet.window.orderFrontRegardless() }
        chat.show(near: pet.window.frame)
    }
    @objc private func newChat() { chat.newChat() }
    @objc private func toggleHidden() {
        if pet.window.isVisible { pet.window.orderOut(nil) } else { pet.window.orderFrontRegardless() }
    }
    @objc private func setKey() { _ = promptForKey() }

    private func promptForKey() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mochi needs a Claude API key"
        alert.informativeText = "Paste your Anthropic API key (from platform.claude.com). It's saved only on this Mac, in ~/Library/Application Support/MochiPet."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "sk-ant-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        KeyStore.save(key)
        return key
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
