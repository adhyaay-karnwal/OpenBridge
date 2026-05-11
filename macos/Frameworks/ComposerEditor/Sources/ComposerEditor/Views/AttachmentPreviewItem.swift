//
//  AttachmentPreviewItem.swift
//  ComposerEditor
//
//  Created by qaq on 7/1/2026.
//

import AppKit
import SwiftUI

struct AttachmentPreviewItem: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void
    let onRetry: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering: Bool = false
    @State private var isHoveringRemove: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if attachment.isImage { imagePreview } else { filePreview }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .black))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        Color(nsColor: .controlBackgroundColor),
                        Color.primary.opacity(0.8)
                    )
                    .opacity(isHoveringRemove ? 1 : 0.8)
                    .contentShape(Circle())
            }
            .opacity(isHoveringRemove || isHovering || ComposerRuntimeEnvironment.isE2EMode ? 1 : 0)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("chat.composer.attachment.removeButton")
            .accessibilityLabel("Remove attachment")
            .padding([.trailing, .top], -4)
            .onHover { isHoveringRemove = $0 }
        }
        .padding([.top, .trailing], 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .task(id: attachment.uploadState) {
            await loadThumbnail()
        }
        .help(attachment.errorMessage ?? attachment.filename)
        .accessibilityIdentifier("chat.composer.attachment.item")
        .accessibilityLabel(attachment.filename)
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() async {
        if attachment.isImage {
            // Generate from local data if available
            if let localThumbnail = attachment.thumbnail() {
                thumbnail = localThumbnail
            }
            // Remote images are handled by AsyncImage in the view
        } else {
            thumbnail = attachment.fileIcon()
        }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: ComposerLayout.previewSize, height: ComposerLayout.previewSize)
                    .background(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let remoteURL = remoteImageURL {
                // Remote image from editing - use AsyncImage for https URLs
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: ComposerLayout.previewSize, height: ComposerLayout.previewSize)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        placeholderView
                    case .empty:
                        loadingView
                    @unknown default:
                        loadingView
                    }
                }
            } else {
                loadingView
            }
            uploadStateOverlay(width: ComposerLayout.previewSize)
        }
    }

    private var remoteImageURL: URL? {
        guard attachment.data.isEmpty,
              let publicURL = attachment.publicURL,
              let url = URL(string: publicURL),
              url.scheme == "https" || url.scheme == "http"
        else {
            return nil
        }
        return url
    }

    private var loadingView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(width: ComposerLayout.previewSize, height: ComposerLayout.previewSize)
            .overlay {
                ProgressView()
                    .scaleEffect(0.6)
            }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(width: ComposerLayout.previewSize, height: ComposerLayout.previewSize)
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
    }

    // MARK: - File Preview

    private var filePreview: some View {
        ZStack {
            HStack(spacing: 8) {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let fileTypeLabel {
                        Text(fileTypeLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(width: ComposerLayout.filePreviewWidth, height: ComposerLayout.previewSize)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))

            uploadStateOverlay(width: ComposerLayout.filePreviewWidth)
        }
    }

    private var fileExtension: String {
        let ext = (attachment.filename as NSString).pathExtension
        return ext.isEmpty ? "" : ".\(ext.lowercased())"
    }

    private var fileTypeLabel: String? {
        if attachment.isDirectory {
            return String(localized: "Folder")
        }
        return fileExtension
    }

    // MARK: - Upload State Overlay

    @ViewBuilder
    private func uploadStateOverlay(width: CGFloat) -> some View {
        switch attachment.uploadState {
        case .pending:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
                .frame(width: width, height: ComposerLayout.previewSize)
                .overlay {
                    VStack(spacing: 4) {
                        ProgressView()
                            .progressViewStyle(CircularProgressStyle())
                            .controlSize(.small)
                    }
                }

        case let .uploading(progress):
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
                .frame(width: width, height: ComposerLayout.previewSize)
                .overlay {
                    VStack(spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(CircularProgressStyle())
                            .controlSize(.small)
                    }
                }

        case .uploaded:
            EmptyView()

        case .failed:
            Button(action: onRetry) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.sRGB, red: 1.0, green: 0.286, blue: 0.298, opacity: 0.6))
                    .frame(width: width, height: ComposerLayout.previewSize)
                    .overlay {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
    }
}
