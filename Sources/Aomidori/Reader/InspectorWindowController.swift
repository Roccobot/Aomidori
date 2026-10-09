import AppKit
import EPUBKit

/// Book information: descriptive metadata and the cover image (`⌘I`).
@MainActor
final class InspectorWindowController: NSWindowController {
    init(publication: EPUBPublication) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .segmentedControlOnTop
        let metadata = NSTabViewItem(viewController: MetadataViewController(metadata: publication.book.metadata))
        metadata.label = L10n.string("inspector.metadata")
        let cover = NSTabViewItem(viewController: CoverViewController(image: Self.coverImage(of: publication)))
        cover.label = L10n.string("inspector.cover")
        tabs.addTabViewItem(metadata)
        tabs.addTabViewItem(cover)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.title = L10n.format("inspector.title", publication.book.title ?? "")
        window.setContentSize(NSSize(width: 520, height: 460))
        window.isRestorable = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func coverImage(of publication: EPUBPublication) -> NSImage? {
        guard let path = publication.book.coverPath, let data = try? publication.resource(at: path).data else { return nil }
        return NSImage(data: data)
    }
}

@MainActor
private final class MetadataViewController: NSViewController {
    private let metadata: EPUBMetadata

    init(metadata: EPUBMetadata) {
        self.metadata = metadata
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let language = metadata.language.map { code in
            Locale.current.localizedString(forIdentifier: code).map { "\(code) (\($0))" } ?? code
        }
        let rows: [(String, String?)] = [
            ("inspector.field.title", metadata.title),
            ("inspector.field.creator", metadata.creators.joined(separator: ", ").nilIfEmpty),
            ("inspector.field.contributor", metadata.contributors.joined(separator: ", ").nilIfEmpty),
            ("inspector.field.publisher", metadata.publisher),
            ("inspector.field.date", metadata.date),
            ("inspector.field.modified", metadata.modified),
            ("inspector.field.language", language),
            ("inspector.field.subjects", metadata.subjects.joined(separator: ", ").nilIfEmpty),
            ("inspector.field.rights", metadata.rights),
            ("inspector.field.identifier", metadata.identifier),
            ("inspector.field.description", metadata.description),
        ]
        let grid = NSGridView(views: rows.map { key, value in
            let label = NSTextField(labelWithString: L10n.string(key))
            label.textColor = .secondaryLabelColor
            let field = NSTextField(wrappingLabelWithString: value ?? "")
            field.isSelectable = true
            field.preferredMaxLayoutWidth = 340
            return [label, field]
        })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(grid)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = document
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -20),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        view = scrollView
    }
}

@MainActor
private final class CoverViewController: NSViewController {
    private let image: NSImage?

    init(image: NSImage?) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        guard let image else {
            let label = NSTextField(labelWithString: L10n.string("inspector.noCover"))
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            let container = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            view = container
            return
        }
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view = imageView
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
