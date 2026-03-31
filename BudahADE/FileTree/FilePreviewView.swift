import SwiftUI
import AVKit
import PDFKit

struct FilePreviewView: View {
    let path: String
    let kind: FileKind

    var body: some View {
        Group {
            switch kind {
            case .image:    imagePreview
            case .video:    videoPreview
            case .pdf:      pdfPreview
            case .code, .markup, .data: textPreview
            default:        fileInfoPreview
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Image

    @ViewBuilder
    private var imagePreview: some View {
        if let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 200)
                .background(Color.black.opacity(0.3))
        } else {
            fileInfoPreview
        }
    }

    // MARK: - Video

    private var videoPreview: some View {
        VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: path)))
            .frame(height: 160)
    }

    // MARK: - PDF

    private var pdfPreview: some View {
        PDFPreviewNSView(path: path)
            .frame(height: 220)
    }

    // MARK: - Text / Code

    private var textPreview: some View {
        ScrollView([.vertical], showsIndicators: false) {
            Text(previewContent)
                .font(Theme.code(10.5))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 180)
        .background(Theme.appBackground)
    }

    // MARK: - Fallback

    private var fileInfoPreview: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 22))
                .foregroundColor(Theme.textMuted)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                if let size = fileSize {
                    Text(size)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.elevated)
    }

    // MARK: - Helpers

    private var previewContent: String {
        let maxBytes = 8_000
        guard let data = FileManager.default.contents(atPath: path),
              let str = String(data: data.prefix(maxBytes), encoding: .utf8)
                     ?? String(data: data.prefix(maxBytes), encoding: .isoLatin1)
        else { return "(binary file)" }
        return str
    }

    private var fileSize: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - PDFKit NSViewRepresentable

private struct PDFPreviewNSView: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = Theme.nsAppBackground
        if let doc = PDFDocument(url: URL(fileURLWithPath: path)) {
            view.document = doc
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}
