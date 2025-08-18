//
//  Settings.swift
//  IconFinder
//
//  A tiny Swift wrapper to present a modern settings window with Swift UI controls
//  while the app remains Objective-C.
//

import Cocoa

// Bridge notification name directly by raw value to avoid type coercion issues
extension Notification.Name {
    static let JRAppSettingsDidChange = Notification.Name("AppSettingsDidChange")
}

@objc class JRSettings: NSObject {
    @objc static let shared = JRSettings()

    private var windowController: NSWindowController?

    @objc func showSettings() {
        if windowController == nil {
            windowController = buildWindow()
        }
        windowController?.showWindow(nil)
        windowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    // AppKit convention uses `showPreferences:` for the menu action.
    // Provide an Objective-C-visible shim that maps to our implementation.
    @objc func showPreferences() {
        showSettings()
    }

    private func buildWindow() -> NSWindowController {
        let vc = SettingsViewController()
        let window = NSWindow(contentViewController: vc)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 480))
        window.contentMinSize = NSSize(width: 560, height: 420)
        return NSWindowController(window: window)
    }
}

final class SettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let deepScanSwitch = NSSwitch()
    private let hideDupSwitch = NSSwitch()
    private let excludeExternalSwitch = NSSwitch()

    // Exclude list (single list per mock)
    private var excludedRoots: [String] = []
    private let excludedTable = NSTableView()
    private let excludedScroll = NSScrollView()

    override func loadView() {
        // Give the root view a concrete frame; let it use autoresizing masks.
        // This avoids ambiguous layout when hosted by NSWindow.
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        // Do NOT disable autoresizing mask on the root view.

        let title1 = rowLabel("Enable Deep Scan")
        let title2 = rowLabel("Hide Duplicates")
        let title3 = rowLabel("Exclude External Volumes")
        let desc = wrappingLabel(
            "Deep Scan walks the filesystem for images. It may take significantly longer than the default fast scan (Spotlight)."
        )

        deepScanSwitch.target = self
        deepScanSwitch.action = #selector(deepScanToggled(_:))
        hideDupSwitch.target = self
        hideDupSwitch.action = #selector(hideDuplicatesToggled(_:))
        excludeExternalSwitch.target = self
        excludeExternalSwitch.action = #selector(excludeExternalToggled(_:))

        let row1 = makeTrailingRow(label: title1, control: deepScanSwitch)
        let row2 = makeTrailingRow(label: title2, control: hideDupSwitch)
        let row3 = makeTrailingRow(label: title3, control: excludeExternalSwitch)

        // Card for toggles
        let togglesCard = card()
        let sep = NSBox()
        sep.boxType = .separator
        let sep2 = NSBox()
        sep2.boxType = .separator
        let togglesStack = NSStackView(views: [row1, desc, sep, row2, sep2, row3])
        togglesStack.orientation = .vertical
        togglesStack.spacing = 12
        togglesStack.alignment = .leading
        // Allow autoresizing within NSBox to avoid collapse/overlap.
        togglesStack.translatesAutoresizingMaskIntoConstraints = true
        togglesCard.contentView = togglesStack

        // Exclude list UI
        configureTable(excludedTable)
        excludedScroll.documentView = excludedTable
        excludedScroll.hasVerticalScroller = true
        excludedScroll.hasHorizontalScroller = false
        // Lighter, modern look inside the card
        excludedScroll.drawsBackground = false
        excludedScroll.borderType = .noBorder
        excludedScroll.translatesAutoresizingMaskIntoConstraints = false
        excludedScroll.heightAnchor.constraint(equalToConstant: 240).isActive = true
        excludedScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        excludedScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        excludedScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        excludedScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true

        let listsHeader = sectionTitle("Exclude from Scan")

        let excludedButtons = buttonRow(
            addSelector: #selector(addExcluded), removeSelector: #selector(removeExcluded))
        let excludedCard = card()
        let excludedStack = NSStackView(views: [excludedScroll, excludedButtons])
        excludedStack.orientation = .vertical
        excludedStack.spacing = 8
        excludedStack.alignment = .leading
        // Allow autoresizing within NSBox so the scroll view lays out correctly.
        excludedStack.translatesAutoresizingMaskIntoConstraints = true
        excludedCard.contentView = excludedStack

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 14
        container.alignment = .leading
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setHuggingPriority(.defaultLow, for: .horizontal)
        container.setHuggingPriority(.defaultLow, for: .vertical)
        container.addArrangedSubview(togglesCard)
        container.addArrangedSubview(listsHeader)
        container.addArrangedSubview(excludedCard)

        // Done button aligned right
        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeSettings))
        doneButton.bezelStyle = .rounded
        // Make it the default action (blue button, Return key)
        doneButton.keyEquivalent = "\r"
        doneButton.keyEquivalentModifierMask = []
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        let footer = NSStackView(views: [NSView(), doneButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        container.addArrangedSubview(footer)

        view.addSubview(container)

        // Make cards expand to full available width in the container
        togglesCard.translatesAutoresizingMaskIntoConstraints = false
        excludedCard.translatesAutoresizingMaskIntoConstraints = false
        togglesCard.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        excludedCard.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            container.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let d = UserDefaults.standard
        deepScanSwitch.state = d.bool(forKey: "DeepScanEnabled") ? .on : .off
        hideDupSwitch.state = d.bool(forKey: "HideDuplicates") ? .on : .off
        // Exclude External Volumes is ON when IncludeExternalVolumes is false or missing (default exclude)
        let includeExternal = d.object(forKey: "IncludeExternalVolumes") as? Bool ?? false
        excludeExternalSwitch.state = includeExternal ? .off : .on
        excludedRoots = d.stringArray(forKey: "DeniedRoots") ?? defaultDeniedRoots()
        excludedTable.reloadData()
    }

    private func label(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.setContentCompressionResistancePriority(.init(251), for: .horizontal)
        return tf
    }
    private func rowLabel(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        return tf
    }
    private func sectionTitle(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        return tf
    }
    private func makeTrailingRow(label: NSTextField, control: NSView) -> NSStackView {
        // Spacer forces the control (switch) to align at the trailing edge
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }
    private func card() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        // Avoid deprecated borderType; use no visible border
        box.borderWidth = 0
        box.borderColor = .clear
        box.fillColor = NSColor.controlBackgroundColor
        box.cornerRadius = 8
        box.contentViewMargins = NSSize(width: 16, height: 16)
        return box
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let tf = NSTextField(wrappingLabelWithString: text)
        tf.textColor = .secondaryLabelColor
        tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
        return tf
    }

    @objc private func deepScanToggled(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: "DeepScanEnabled")
        NotificationCenter.default.post(name: Notification.Name.JRAppSettingsDidChange, object: nil)
    }

    @objc private func hideDuplicatesToggled(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: "HideDuplicates")
        NotificationCenter.default.post(name: Notification.Name.JRAppSettingsDidChange, object: nil)
    }

    @objc private func excludeExternalToggled(_ sender: NSSwitch) {
        // Store the inverse on the existing key to maintain compatibility
        // Exclude External Volumes (ON) => IncludeExternalVolumes = false
        let include = (sender.state == .on) ? false : true
        UserDefaults.standard.set(include, forKey: "IncludeExternalVolumes")
        NotificationCenter.default.post(name: Notification.Name.JRAppSettingsDidChange, object: nil)
    }

    @objc private func closeSettings() {
        view.window?.close()
    }

    // MARK: - Exclude list helpers
    private func configureTable(_ table: NSTableView) {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        col.resizingMask = .autoresizingMask
        col.minWidth = 200
        col.width = 800
        table.addTableColumn(col)
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = self
        table.dataSource = self
    }

    private func buttonRow(addSelector: Selector, removeSelector: Selector) -> NSStackView {
        let add = NSButton()
        add.image = NSImage(named: NSImage.addTemplateName)
        add.imagePosition = .imageOnly
        add.isBordered = false
        add.bezelStyle = .texturedRounded
        add.controlSize = .small
        add.target = self
        add.action = addSelector

        let remove = NSButton()
        remove.image = NSImage(named: NSImage.removeTemplateName)
        remove.imagePosition = .imageOnly
        remove.isBordered = false
        remove.bezelStyle = .texturedRounded
        remove.controlSize = .small
        remove.target = self
        remove.action = removeSelector

        let row = NSStackView(views: [add, remove])
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    @objc private func addExcluded() {
        addPath {
            self.excludedRoots.append($0)
            self.persistExcluded()
        }
    }
    @objc private func removeExcluded() {
        removeSelected(from: excludedTable) { index in
            self.excludedRoots.remove(at: index)
            self.persistExcluded()
        }
    }

    private func addPath(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                completion(url.path)
                self.excludedTable.reloadData()
                NotificationCenter.default.post(
                    name: Notification.Name.JRAppSettingsDidChange, object: nil)
            }
        }
    }

    private func removeSelected(from table: NSTableView, update: (Int) -> Void) {
        let idx = table.selectedRow
        guard idx >= 0 else { return }
        update(idx)
        table.reloadData()
        NotificationCenter.default.post(name: Notification.Name.JRAppSettingsDidChange, object: nil)
    }

    private func persistExcluded() {
        UserDefaults.standard.set(excludedRoots, forKey: "DeniedRoots")
    }

    private func defaultDeniedRoots() -> [String] {
        let home = NSHomeDirectory()
        return [home + "/Library/Mobile Documents", "/Volumes/Time Machine Backups"]
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - NSTableView
    func numberOfRows(in tableView: NSTableView) -> Int {
        return excludedRoots.count
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let path = excludedRoots[row]
        let exists = FileManager.default.fileExists(atPath: path)
        let hstack = NSStackView()
        hstack.orientation = .horizontal
        hstack.spacing = 8
        let icon = NSImageView()
        if exists {
            icon.image = NSWorkspace.shared.icon(forFile: path)
        } else {
            icon.image = NSImage(named: NSImage.cautionName)
        }
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let label = NSTextField(labelWithString: displayPath(path))
        label.lineBreakMode = .byTruncatingMiddle
        if !exists { label.textColor = .systemRed }
        hstack.addArrangedSubview(icon)
        hstack.addArrangedSubview(label)
        return hstack
    }
}
