// ComposerEditor Framework
//
// A standalone chat composer component with attachment support
//
// Main components:
// - ComposerView: The main composer UI with text input and attachments
// - ComposerViewModel: Observable view model for managing composer state
// - ChatAttachment: Model for file/image attachments
// - AttachmentPreviewRow: UI component for displaying attachment previews
// - GrowingTextEditor: Auto-growing text editor component
// - UploadMenuButton: Button for uploading files/images
//
// Usage:
//   import ComposerEditor
//
//   @State var viewModel = ComposerViewModel()
//
//   ComposerView(viewModel: viewModel)
//     .onSubmit { submission in
//       // Handle submission
//     }

import Foundation
