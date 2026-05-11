# ComposerEditor

A self-contained Swift package for macOS providing a rich chat composer component with text input, file attachments, and drag-and-drop support.

## Features

- ✅ Three display modes: Standalone, Embedded, Compact
- ✅ Auto-growing text editor
- ✅ Image and file attachment support
- ✅ Drag-and-drop file handling
- ✅ Paste image/file support
- ✅ Attachment preview with thumbnails
- ✅ Event-driven architecture with Combine publishers
- ✅ MainActor-safe design
- ✅ Fully self-contained, no external dependencies

## Requirements

- macOS 14.0+
- Swift 6.2+

## Installation

```swift
dependencies: [
    .package(path: "path/to/ComposerEditor")
]
```

## Usage

### Basic Setup

```swift
import SwiftUI
import ComposerEditor
import Combine

struct ContentView: View {
    @State var viewModel = ComposerViewModel()
    @State var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ComposerView(
            viewModel: viewModel,
            accentColor: .blue,
            placeholder: "Type a message...",
            appearance: .standalone
        )
        .onAppear {
            viewModel.eventPublisher
                .sink { event in
                    if case .submitted(let submission) = event {
                        print("Message: \(submission.text ?? "")")
                        viewModel.text = ""
                        viewModel.clearAttachments()
                    }
                }
                .store(in: &cancellables)
        }
    }
}
```

### Three Appearance Modes

**Standalone** - With background, border, and shadow:
```swift
ComposerView(
    viewModel: viewModel,
    appearance: .standalone
)
```

**Embedded** - Transparent, integrates seamlessly:
```swift
ComposerView(
    viewModel: viewModel,
    appearance: .embedded
)
```

**Compact** - Single line horizontal layout `[+] [Text Input] [↑]`:
```swift
ComposerView(
    viewModel: viewModel,
    appearance: .compact
)
// Auto-expands when attachments added
```

### Custom Appearance

```swift
let custom = ComposerAppearance(
    showBackground: true,
    showBorder: false,
    showShadow: true,
    cornerRadius: 12,
    padding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
)

ComposerView(viewModel: viewModel, appearance: custom)
```

### Event Handling

```swift
viewModel.eventPublisher
    .sink { event in
        switch event {
        case .submitted(let submission):
            handleMessage(submission)
        case .attachmentAdded(let attachment, let source):
            print("Added: \(attachment.filename)")
        case .attachmentUploadProgress(let id, let progress):
            print("Progress: \(Int(progress * 100))%")
        default:
            break
        }
    }
    .store(in: &cancellables)
```

### Available Events

- `submitted(Submission)` - Message submitted
- `escaped` - Escape key pressed
- `attachmentAdded/Removed` - Attachment lifecycle
- `attachmentUploadStarted/Progress/Completed/Failed` - Upload states
- `textChanged(String)` - Text content changed
- `focusChanged(Bool)` - Focus state changed
- `stopRequested` - Stop streaming

## Command Menu (Example)

The Example project includes a reusable command menu component for inserting tokens via `/` trigger. This is a pure AppKit implementation with keyboard navigation support.

### Components

- `CommandItem` - Data model for menu items
- `CommandMenuDataSource` - Protocol for providing menu items
- `CommandTokenAttachment` - NSTextAttachment for inline tokens
- `CommandMenuView` - Pure AppKit menu with keyboard navigation
- `CommandMenuController` - Manages menu lifecycle and positioning
- `CommandTextView` - Text view with `/` trigger support

### Usage

```swift
import AppKit

// 1. Define your data source
final class MyCommandDataSource: CommandMenuDataSource {
    private let commands: [CommandItem] = [
        CommandItem(
            id: "commit",
            name: "commit",
            plainTextContentRepresentation: "<command:commit />"
        ),
        CommandItem(
            id: "review",
            name: "review",
            plainTextContentRepresentation: "<command:review />"
        ),
    ]

    func commandMenuItems() -> [CommandItem] {
        commands
    }
}

// 2. Create and configure the text view
let textView = CommandTextView(frame: .zero)
textView.dataSource = MyCommandDataSource()
textView.placeholder = "Type / to see commands..."

// 3. Handle submission (tokens converted to plainTextContentRepresentation)
textView.onSend = { plainText in
    print("Submitted: \(plainText)")
    // e.g. "Hello <command:commit /> world"
    textView.clear()
}
```

### Features

- Trigger menu by typing `/` at start or after whitespace
- Keyboard navigation: `↑` `↓` to navigate, `Enter` to select, `Esc` to cancel
- Click outside or window resign to dismiss
- Tokens display as `/name` but submit as `plainTextContentRepresentation`
- Supports light/dark mode automatically

## Architecture

```
ComposerEditor/
├── Models/
│   ├── ChatAttachment.swift
│   └── AttachmentSource.swift
├── Events/
│   └── ComposerEvent.swift
├── Views/
│   ├── ComposerView.swift
│   ├── ComposerView+Layout.swift
│   ├── ComposerView+Handlers.swift
│   └── AttachmentPreviewRow.swift
├── Components/
│   ├── GrowingTextEditor.swift
│   └── UploadMenuButton.swift
├── Utilities/
│   └── NSExtensions.swift
└── ComposerViewModel.swift
```

## Building

```bash
cd ComposerEditor
swift build
```

## License

Part of the OpenBridge project.
