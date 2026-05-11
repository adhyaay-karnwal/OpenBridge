# Migration Guide

## API Changes

### ComposerView API

**Old API (deprecated):**
```swift
// Using mode enum
ComposerView(viewModel: vm, mode: .compact)

// Using standalone bool
ComposerView(viewModel: vm, standalone: true)
```

**New API:**
```swift
// Using appearance
ComposerView(viewModel: vm, appearance: .compact)
ComposerView(viewModel: vm, appearance: .standalone)
ComposerView(viewModel: vm, appearance: .embedded)
```

### Migration Steps

1. Replace `mode: .standalone` → `appearance: .standalone`
2. Replace `mode: .embedded` → `appearance: .embedded`
3. Replace `mode: .compact` → `appearance: .compact`
4. Replace `standalone: true` → `appearance: .standalone`
5. Replace `standalone: false` → `appearance: .embedded`

### Custom Appearance

You can now customize appearance:

```swift
let custom = ComposerAppearance(
    showBackground: true,
    showBorder: false,
    showShadow: true,
    cornerRadius: 12,
    padding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
)

ComposerView(viewModel: vm, appearance: custom)
```

## Code Structure Changes

Files have been reorganized for better maintainability:

- `ComposerView.swift` - Main view and appearance config
- `ComposerView+Layout.swift` - Layout logic
- `ComposerView+Handlers.swift` - Event handlers
- `AttachmentPreviewRow.swift` - Simplified preview component
- `ComposerViewModel.swift` - Simplified view model

No API changes for these components, only internal improvements.
