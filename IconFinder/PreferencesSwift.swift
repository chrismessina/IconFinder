//
//  PreferencesSwift.swift
//  IconFinder
//
//  A tiny Swift wrapper to present a modern preferences window with Swift UI controls
//  while the app remains Objective-C.
//

import Cocoa

@objc class JRPreferencesSwift: NSObject {
    @objc static let shared = JRPreferencesSwift()

    private var windowController: NSWindowController?

    @objc func showPreferences() {
        if windowController == nil {
            windowController = buildWindow()
        }
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() -> NSWindowController {
        let vc = PreferencesViewController()
        let window = NSWindow(contentViewController: vc)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 200))
        return NSWindowController(window: window)
    }
}

final class PreferencesViewController: NSViewController {
    private let deepScanSwitch = NSSwitch()
    private let hideDupSwitch = NSSwitch()

    override func loadView() {
        self.view = NSView()
        self.view.translatesAutoresizingMaskIntoConstraints = false

        let title1 = label("Enable Deep Scan")
        let title2 = label("Hide Duplicates")
        let desc = wrappingLabel("Deep Scan walks the filesystem for images. It may take significantly longer than the default fast scan (Spotlight).")

        deepScanSwitch.target = self
        deepScanSwitch.action = #selector(deepScanToggled(_:))
        hideDupSwitch.target = self
        hideDupSwitch.action = #selector(hideDuplicatesToggled(_:))

        let row1 = NSStackView(views: [title1, deepScanSwitch])
        row1.orientation = .horizontal
        row1.spacing = 8
        row1.alignment = .firstBaseline

        let row2 = NSStackView(views: [title2, hideDupSwitch])
        row2.orientation = .horizontal
        row2.spacing = 8
        row2.alignment = .firstBaseline

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 10
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(row1)
        container.addArrangedSubview(desc)
        container.addArrangedSubview(row2)

        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let d = UserDefaults.standard
        deepScanSwitch.state = d.bool(forKey: "DeepScanEnabled") ? .on : .off
        hideDupSwitch.state = d.bool(forKey: "HideDuplicates") ? .on : .off
    }

    private func label(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.setContentCompressionResistancePriority(.init(251), for: .horizontal)
        return tf
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let tf = NSTextField(wrappingLabelWithString: text)
        tf.textColor = .secondaryLabelColor
        tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
        return tf
    }

    @objc private func deepScanToggled(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: "DeepScanEnabled")
        NotificationCenter.default.post(name: Notification.Name(rawValue: JRAppSettingsDidChangeNotification), object: nil)
    }

    @objc private func hideDuplicatesToggled(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: "HideDuplicates")
        NotificationCenter.default.post(name: Notification.Name(rawValue: JRAppSettingsDidChangeNotification), object: nil)
    }
}

