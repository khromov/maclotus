import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let bleManager = BLEManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (backup to LSUIElement in Info.plist)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lightbulb.fill",
                                   accessibilityDescription: "MacLotus")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .semitransient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MainPopoverView()
                .environmentObject(bleManager)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return !NSColorPanel.shared.isVisible
    }

    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.post(name: Notification.Name("PopoverDidClose"), object: nil)
    }
}
