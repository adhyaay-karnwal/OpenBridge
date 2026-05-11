import AppKit
import SwiftUI

public struct UploadMenuButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let disabled: Bool
    let draggingFile: Bool
    let onFileURLs: ([URL]) -> Void
    let additionalMenuItems: (() -> [NSMenuItem])?

    @State private var isHovered = false

    public init(
        disabled: Bool = false,
        draggingFile: Bool = false,
        onFileURLs: @escaping ([URL]) -> Void,
        additionalMenuItems: (() -> [NSMenuItem])? = nil
    ) {
        self.disabled = disabled
        self.draggingFile = draggingFile
        self.onFileURLs = onFileURLs
        self.additionalMenuItems = additionalMenuItems
    }

    public var body: some View {
        Button {
            guard !disabled else { return }
            showMenu()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .foregroundColor(.primary)
                .opacity(disabled ? ComposerControlStyle.disabledForegroundOpacity : 1)
                .scaleEffect(draggingFile ? 1.2 : 1)
                .background(buttonBackgroundColor)
                .clipShape(.circle)
                .animation(.spring(duration: 0.2, bounce: 0.3), value: draggingFile)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!disabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityIdentifier("chat.composer.uploadButton")
        .accessibilityLabel("Upload file")
    }

    private var buttonBackgroundColor: Color {
        let opacity = ComposerControlStyle.backgroundOpacity(
            isDarkMode: colorScheme == .dark,
            isActive: isHovered || draggingFile,
            isDisabled: disabled
        )
        return Color.primary.opacity(opacity)
    }

    private func showMenu() {
        let menu = NSMenu()

        let extraItems = additionalMenuItems?() ?? []
        if !extraItems.isEmpty {
            for item in extraItems {
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let imageItem = NSMenuItem(title: String(localized: "Upload Image"), action: nil, keyEquivalent: "")
        imageItem.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        imageItem.target = nil
        menu.addItem(imageItem)
        imageItem.representedObject = "image"

        let fileItem = NSMenuItem(title: String(localized: "Upload File"), action: nil, keyEquivalent: "")
        fileItem.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        menu.addItem(fileItem)
        fileItem.representedObject = "file"

        let handler = MenuActionHandler(
            imageAction: { [onFileURLs] in
                Task { @MainActor in
                    let urls = await FilePicker.pickImageURLs()
                    if !urls.isEmpty {
                        onFileURLs(urls)
                    }
                }
            },
            fileAction: { [onFileURLs] in
                Task { @MainActor in
                    let urls = await FilePicker.pickFileURLs()
                    if !urls.isEmpty {
                        onFileURLs(urls)
                    }
                }
            }
        )
        imageItem.target = handler
        imageItem.action = #selector(MenuActionHandler.pickImage)
        fileItem.target = handler
        fileItem.action = #selector(MenuActionHandler.pickFile)

        objc_setAssociatedObject(menu, "handler", handler, .OBJC_ASSOCIATION_RETAIN)

        let extraTargets = extraItems.compactMap(\.target)
        if !extraTargets.isEmpty {
            objc_setAssociatedObject(menu, "extraTargets", extraTargets, .OBJC_ASSOCIATION_RETAIN)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private class MenuActionHandler: NSObject {
    let imageAction: () -> Void
    let fileAction: () -> Void

    init(imageAction: @escaping () -> Void, fileAction: @escaping () -> Void) {
        self.imageAction = imageAction
        self.fileAction = fileAction
    }

    @objc func pickImage() {
        imageAction()
    }

    @objc func pickFile() {
        fileAction()
    }
}
