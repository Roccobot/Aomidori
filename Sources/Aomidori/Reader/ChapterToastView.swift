import AppKit
import AomidoriCore

/// The low, bottom-centred Liquid Glass capsule offered at the edge of a chapter: "Go to next
/// chapter", "Go to previous chapter" or "End of book". Clicking it goes there; the reader
/// also asks whether the pointer is over it, since a second push then goes there too.
@MainActor
final class ChapterToastView: NSView {
    enum Kind: Equatable {
        case next
        case previous
        case endOfBook

        var title: String {
            switch self {
            case .next: L10n.string("reader.toast.next")
            case .previous: L10n.string("reader.toast.previous")
            case .endOfBook: L10n.string("reader.toast.end")
            }
        }

        var symbolName: String {
            switch self {
            case .next: "chevron.down"
            case .previous: "chevron.up"
            case .endOfBook: "book.closed"
            }
        }
    }

    var onClick: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    private(set) var kind: Kind?
    private(set) var isShown = false

    private let glass = NSGlassEffectView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hoverArea: NSTrackingArea?

    static let height: CGFloat = 36

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alphaValue = 0
        isHidden = true
        setAccessibilityRole(.button)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        glass.cornerRadius = Self.height / 2
        glass.contentView = stack
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            // The capsule is as wide as its content.
            stack.topAnchor.constraint(equalTo: glass.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ kind: Kind) {
        self.kind = kind
        label.stringValue = kind.title
        icon.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
        setAccessibilityLabel(kind.title)
        guard !isShown else { return }
        isShown = true
        isHidden = false
        animator().alphaValue = 1
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        animator().alphaValue = 0
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !self.isShown else { return }
            self.isHidden = true
        }
    }

    /// Whether the pointer is over the capsule now (it may have appeared under a still pointer,
    /// which sends no `mouseEntered`).
    var containsPointer: Bool {
        guard isShown, let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isShown ? super.hitTest(point).map { _ in self } : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func mouseDown(with event: NSEvent) {}

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
