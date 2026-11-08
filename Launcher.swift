import AppKit

struct AppChoice: Decodable {
    let text: String
    let bundleID: String
    let path: String
    let aliases: [String]?

    func rank(for query: String) -> Int? {
        let name = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if name == query { return 0 }
        let aliases = (aliases ?? []).map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        if aliases.contains(query) { return 1 }
        if name.hasPrefix(query) { return 2 }
        if query.count >= 2 && aliases.contains(where: { $0.hasPrefix(query) }) { return 3 }
        if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(query) }) { return 4 }
        if name.contains(query) { return 5 }
        var remaining = query[...]
        for letter in name where remaining.first == letter { remaining = remaining.dropFirst() }
        return remaining.isEmpty ? 6 : nil
    }
}

struct LearnedPick: Decodable {
    let query: String
    let bundleID: String
}

struct SearchIndex: Decodable {
    let choices: [AppChoice]?
    let recent: [String]?
    let learned: [LearnedPick]?
    let rules: [String: String]?
}

enum WindowMode: String, CaseIterable {
    case `switch`, new, bring
    var title: String {
        switch self {
        case .switch: return "Switch to the app"
        case .new: return "Open a new window here"
        case .bring: return "Bring an existing window here"
        }
    }
}

struct Selection: Encodable {
    let bundleID: String
    let shortQuery: String?
    let windows: WindowHints?
    let saveMode: String?
    let switchOnce: Bool?
}

struct WindowHints: Encodable {
    let pid: pid_t
    let ids: [CGWindowID]

    init?(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        self.init(app: app)
    }
    init?(app: NSRunningApplication) {
        guard let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], 0) as? [[String: Any]] else { return nil }
        pid = app.processIdentifier
        // Accessibility can omit an app's windows while their display shows another Space.
        ids = rows.compactMap { row in
            guard row[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  row[kCGWindowLayer as String] as? Int == 0,
                  let bounds = row[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 1, (bounds["Height"] ?? 0) > 1 else { return nil }
            return row[kCGWindowNumber as String] as? CGWindowID
        }
    }
}

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class SearchSurface: NSVisualEffectView {
    override var isFlipped: Bool { true }

    func roundCorners(radius: CGFloat) {
        let size = NSSize(width: radius * 2 + 2, height: radius * 2 + 2)
        let mask = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        maskImage = mask
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
    }
}

final class Launcher: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate,
                      NSTableViewDataSource, NSTableViewDelegate {
    private let index: SearchIndex
    private let surface = SearchSurface()
    private let field = NSTextField()
    private let searchIcon = NSImageView()
    private let separator = NSBox()
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let empty = NSTextField(labelWithString: "No matching apps")
    private let gear = NSButton()
    private let settingsTitle = NSTextField(labelWithString: "")
    private let settingsHelp = NSTextField(labelWithString: "Press 1–3 to save, or Esc to go back.")
    private var modeButtons: [NSButton] = []
    private var editing: AppChoice?
    private var keyMonitor: Any?
    private let panel = SearchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
    private let icons = NSCache<NSString, NSImage>()
    private var matches: [AppChoice] = []
    private var showingRecent = false
    private var screenFrame = NSRect.zero
    private var finishing = false

    init(index: SearchIndex) { self.index = index }

    private var query: String {
        field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            finish()
            return
        }
        screenFrame = screen.visibleFrame
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.title = "App Search"
        panel.delegate = self

        surface.material = .popover
        surface.blendingMode = .behindWindow
        surface.state = .active
        surface.roundCorners(radius: 18)
        panel.contentView = surface

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.setAccessibilityElement(false)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.font = .systemFont(ofSize: 23)
        field.placeholderString = "Search apps"
        field.setAccessibilityLabel("Search apps")
        field.delegate = self

        separator.boxType = .separator
        empty.font = .systemFont(ofSize: 14)
        empty.textColor = .secondaryLabelColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let column = NSTableColumn(identifier: .init("app"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 40
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.setAccessibilityLabel("Matching applications")
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(clickResult)
        scroll.documentView = table
        gear.bezelStyle = .accessoryBarAction
        gear.isBordered = false
        gear.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "App behavior")
        gear.contentTintColor = .secondaryLabelColor
        gear.toolTip = "Behavior for the selected app (⌘,)"
        gear.setAccessibilityLabel("Behavior for the selected app")
        gear.target = self
        gear.action = #selector(toggleSettings)
        settingsTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        settingsHelp.font = .systemFont(ofSize: 12)
        settingsHelp.textColor = .secondaryLabelColor
        [searchIcon, field, separator, scroll, empty, gear, settingsTitle, settingsHelp].forEach(surface.addSubview)
        modeButtons = WindowMode.allCases.enumerated().map { i, mode in
            let b = NSButton(radioButtonWithTitle: mode.title, target: self, action: #selector(saveBehavior(_:)))
            b.tag = i
            surface.addSubview(b)
            return b
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if flags == .command && event.charactersIgnoringModifiers == "," {
                self.toggleSettings(); return nil
            }
            if self.editing != nil {
                if flags.isEmpty, let key = event.charactersIgnoringModifiers,
                   let i = ["1", "2", "3"].firstIndex(of: key) {
                    self.saveBehavior(self.modeButtons[i]); return nil
                }
                if event.keyCode == 53 { self.toggleSettings(); return nil }
            } else if flags == .option && (event.keyCode == 36 || event.keyCode == 76) {
                self.choose(row: self.table.selectedRow, switchOnce: true); return nil
            }
            return event
        }
        layout()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(field)
    }

    private func layout() {
        let width = min(620, screenFrame.width - 40)
        let expanded = showingRecent || !query.isEmpty
        let listHeight = CGFloat(min(matches.count, 7)) * 42 + 20
        let height: CGFloat = 62 + (editing != nil ? 145 : (expanded ? (matches.isEmpty ? 44 : listHeight) : 0))
        let top = max(screenFrame.minY + height + 8, screenFrame.maxY - screenFrame.height * 0.24)
        panel.setFrame(NSRect(x: (screenFrame.midX - width / 2).rounded(), y: (top - height).rounded(),
                              width: width, height: height), display: true)
        searchIcon.frame = NSRect(x: 20, y: 18, width: 26, height: 26)
        field.frame = NSRect(x: 58, y: (62 - field.intrinsicContentSize.height) / 2,
                             width: width - 112, height: field.intrinsicContentSize.height)
        gear.isHidden = matches.isEmpty
        gear.frame = NSRect(x: width - 52, y: 17, width: 32, height: 28)
        settingsTitle.isHidden = editing == nil
        settingsHelp.isHidden = editing == nil
        settingsTitle.frame = NSRect(x: 23, y: 73, width: width - 46, height: 20)
        settingsHelp.frame = NSRect(x: 23, y: 181, width: width - 46, height: 18)
        for (i, button) in modeButtons.enumerated() {
            button.isHidden = editing == nil
            button.frame = NSRect(x: 21, y: 97 + 26 * CGFloat(i), width: width - 42, height: 23)
        }
        separator.frame = NSRect(x: 0, y: 61, width: width, height: 1)
        separator.isHidden = !expanded
        empty.stringValue = showingRecent ? "No recent apps yet" : "No matching apps"
        empty.isHidden = !expanded || !matches.isEmpty
        empty.frame = NSRect(x: 23, y: 74, width: width - 46, height: 20)
        scroll.isHidden = matches.isEmpty || editing != nil
        scroll.hasVerticalScroller = matches.count > 7
        scroll.frame = NSRect(x: 4, y: 62, width: width - 8, height: max(0, height - 62))
        table.sizeLastColumnToFit()
        panel.invalidateShadow()
    }

    func controlTextDidChange(_ notification: Notification) {
        editing = nil
        showingRecent = false
        refreshMatches()
    }

    private func refreshMatches() {
        let choices = index.choices ?? []
        let query = self.query
        if showingRecent {
            matches = (index.recent ?? []).compactMap { id in choices.first { $0.bundleID == id } }
        } else if query.isEmpty {
            matches = []
        } else {
            let preferred = index.learned?.first { $0.query == query }?.bundleID
            var ranked: [(rank: Int, app: AppChoice)] = []
            for app in choices {
                if let rank = app.rank(for: query) {
                    ranked.append((app.bundleID == preferred ? -1 : rank, app))
                }
            }
            ranked.sort { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.app.text.localizedStandardCompare(b.app.text) == .orderedAscending
            }
            matches = ranked.map { $0.app }
        }
        layout()
        table.reloadData()
        if !matches.isEmpty { select(0) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = matches[row]
        let cell = NSTableCellView()
        let image = NSImageView()
        let key = app.path as NSString
        if icons.object(forKey: key) == nil {
            icons.setObject(NSWorkspace.shared.icon(forFile: app.path), forKey: key)
        }
        image.image = icons.object(forKey: key)
        image.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: app.text)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        for view in [image, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = image
        cell.textField = label
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 30),
            image.heightAnchor.constraint(equalTo: image.widthAnchor),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 11),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8)
        ])
        return cell
    }

    private func select(_ row: Int) {
        guard matches.indices.contains(row) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        if editing != nil { return false }
        switch command {
        case #selector(NSResponder.moveDown(_:)):
            if query.isEmpty && !showingRecent {
                showingRecent = true
                refreshMatches()
            } else {
                select(min(matches.count - 1, table.selectedRow + 1))
            }
        case #selector(NSResponder.moveUp(_:)): select(max(0, table.selectedRow - 1))
        case #selector(NSResponder.insertNewline(_:)): choose(row: table.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)): finish()
        default: return false
        }
        return true
    }

    @objc private func toggleSettings() {
        if editing != nil {
            editing = nil
        } else if matches.indices.contains(table.selectedRow) {
            let app = matches[table.selectedRow]
            editing = app
            settingsTitle.stringValue = "When I choose " + app.text
            let current = index.rules?[app.bundleID] ?? WindowMode.switch.rawValue
            for (i, button) in modeButtons.enumerated() {
                button.state = WindowMode.allCases[i].rawValue == current ? .on : .off
            }
        }
        layout()
        panel.makeFirstResponder(field)
    }
    @objc private func saveBehavior(_ sender: NSButton) {
        guard let app = editing else { return }
        finish(app.bundleID, saveMode: WindowMode.allCases[sender.tag])
    }
    @objc private func clickResult() { choose(row: table.clickedRow) }
    private func choose(row: Int, switchOnce: Bool = false) {
        if editing == nil && matches.indices.contains(row) { finish(matches[row].bundleID, switchOnce: switchOnce) }
    }
    func windowDidResignKey(_ notification: Notification) { finish() }

    private func finish(_ bundleID: String? = nil, saveMode: WindowMode? = nil, switchOnce: Bool = false) {
        guard !finishing else { return }
        finishing = true
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        panel.orderOut(nil)
        if let bundleID {
            let selection = Selection(bundleID: bundleID, shortQuery: (1...4).contains(query.count) ? query : nil,
                                      windows: saveMode == nil ? WindowHints(bundleID: bundleID) : nil,
                                      saveMode: saveMode?.rawValue, switchOnce: switchOnce ? true : nil)
            if let data = try? JSONEncoder().encode(selection) { FileHandle.standardOutput.write(data) }
        }
        NSApp.terminate(nil)
    }
}

do {
    if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--windows" {
        guard let pid = pid_t(CommandLine.arguments[2]), pid > 0,
              let app = NSRunningApplication(processIdentifier: pid),
              let snapshot = WindowHints(app: app) else { exit(1) }
        FileHandle.standardOutput.write(try JSONEncoder().encode(snapshot))
        exit(0)
    }
    let index = try JSONDecoder().decode(SearchIndex.self, from: FileHandle.standardInput.readDataToEndOfFile())
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let launcher = Launcher(index: index)
    app.delegate = launcher
    withExtendedLifetime(launcher) { app.run() }
} catch {
    FileHandle.standardError.write(Data("Could not read the app list: \(error)\n".utf8))
    exit(1)
}
