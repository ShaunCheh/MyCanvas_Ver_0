import CoreGraphics
import Foundation

#if os(iOS)
import UIKit

final class CanvasInputIndicatorHostView: UIView {
    private enum Layout {
        static let itemSpacing: CGFloat = 8
        static let insertionTranslationY: CGFloat = 12
        static let animationDuration: TimeInterval = 0.22
    }

    private let layoutSolver = CanvasInputIndicatorLayoutSolver()
    private let formatter = CanvasInputIndicatorFormatter()
    private let queue = CanvasInputIndicatorQueue()
    private let containerView = UIView()
    private let stackView = UIStackView()
    private var containerLeadingConstraint: NSLayoutConstraint!
    private var containerTopConstraint: NSLayoutConstraint!
    private var containerWidthConstraint: NSLayoutConstraint!
    private var containerHeightConstraint: NSLayoutConstraint!
    private var itemViewsByID: [UUID: iOSCanvasInputIndicatorItemView] = [:]
    private var currentSnapshot = CanvasInputIndicatorQueueSnapshot()
    private var currentLayoutContext: CanvasChromeLayoutContext?
    private var refreshTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        isUserInteractionEnabled = false

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear
        containerView.isHidden = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = Layout.itemSpacing

        addSubview(containerView)
        containerView.addSubview(stackView)
        containerLeadingConstraint = containerView.leadingAnchor.constraint(equalTo: leadingAnchor)
        containerTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
        containerWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: 0)
        containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            containerLeadingConstraint,
            containerTopConstraint,
            containerWidthConstraint,
            containerHeightConstraint,
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTimer?.invalidate()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    func record(event: CanvasInputIndicatorEvent) {
        let snapshot = queue.enqueue(event)
        applySnapshot(snapshot, animated: window != nil)
        updateRefreshTimerIfNeeded()
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        currentLayoutContext = layoutContext
        applyLayout()
        layoutIfNeeded()
    }

    private func handleRefreshTimerTick() {
        let snapshot = queue.snapshot()
        let currentIDs = currentSnapshot.items.map(\.id)
        let nextIDs = snapshot.items.map(\.id)
        applySnapshot(
            snapshot,
            animated: currentIDs != nextIDs && window != nil
        )
        updateRefreshTimerIfNeeded()
    }

    private func updateRefreshTimerIfNeeded() {
        if currentSnapshot.isEmpty {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }

        guard refreshTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: queue.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.handleRefreshTimerTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func applySnapshot(
        _ snapshot: CanvasInputIndicatorQueueSnapshot,
        animated: Bool
    ) {
        let previousIDs = Set(currentSnapshot.items.map(\.id))
        let nextIDs = Set(snapshot.items.map(\.id))
        let removedIDs = previousIDs.subtracting(nextIDs)
        removedIDs.forEach(removeItemView)

        if snapshot.isEmpty {
            currentSnapshot = snapshot
            stackView.arrangedSubviews.forEach { arrangedSubview in
                stackView.removeArrangedSubview(arrangedSubview)
                arrangedSubview.removeFromSuperview()
            }
            itemViewsByID.removeAll()
            containerView.isHidden = true
            isHidden = true
            applyLayout()
            return
        }

        var orderedViews: [iOSCanvasInputIndicatorItemView] = []
        for item in snapshot.items {
            let view: iOSCanvasInputIndicatorItemView
            if let existingView = itemViewsByID[item.id] {
                view = existingView
            } else {
                let newView = iOSCanvasInputIndicatorItemView()
                newView.alpha = 0
                newView.transform = CGAffineTransform(
                    translationX: 0,
                    y: Layout.insertionTranslationY
                )
                itemViewsByID[item.id] = newView
                view = newView
            }
            view.apply(text: formatter.text(for: item.event))
            orderedViews.append(view)
        }

        stackView.arrangedSubviews.forEach { arrangedSubview in
            stackView.removeArrangedSubview(arrangedSubview)
        }
        orderedViews.forEach { view in
            stackView.addArrangedSubview(view)
        }

        currentSnapshot = snapshot
        containerView.isHidden = false
        isHidden = false

        let applyVisualState = {
            for item in snapshot.items {
                guard let view = self.itemViewsByID[item.id] else {
                    continue
                }
                view.alpha = item.opacity
                view.transform = .identity
            }
            self.applyLayout()
            self.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: Layout.animationDuration,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                applyVisualState()
            }
        } else {
            applyVisualState()
        }
    }

    private func removeItemView(id: UUID) {
        guard let view = itemViewsByID.removeValue(forKey: id) else {
            return
        }

        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    private func applyLayout() {
        guard
            currentSnapshot.isEmpty == false,
            let currentLayoutContext
        else {
            updateContainerConstraints(.zero)
            return
        }

        let preferredSize = preferredContainerSize()
        guard let frame = layoutSolver.resolveHostFrame(
            preferredSize: preferredSize,
            layoutContext: currentLayoutContext
        ) else {
            updateContainerConstraints(.zero)
            return
        }

        updateContainerConstraints(frame)
    }

    private func updateContainerConstraints(_ frame: CGRect) {
        let standardizedFrame = frame.standardized
        containerLeadingConstraint.constant = standardizedFrame.minX
        containerTopConstraint.constant = standardizedFrame.minY
        containerWidthConstraint.constant = max(0, standardizedFrame.width)
        containerHeightConstraint.constant = max(0, standardizedFrame.height)
    }

    private func preferredContainerSize() -> CGSize {
        let stackSize = stackView.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize
        )
        return CanvasChromeLayoutGeometry.sanitizedSize(stackSize)
    }
}

private final class iOSCanvasInputIndicatorItemView: UIView {
    private enum Layout {
        static let horizontalInset: CGFloat = 14
        static let verticalInset: CGFloat = 8
        static let cornerRadius: CGFloat = 18
    }

    private let backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.94)
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
        return view
    }()
    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        addSubview(backgroundView)
        addSubview(label)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalInset)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(text: String) {
        label.text = text
        accessibilityLabel = text
    }
}
#elseif os(macOS)
import AppKit

final class CanvasInputIndicatorHostView: NSView {
    private enum Layout {
        static let itemSpacing: CGFloat = 8
        static let animationDuration: TimeInterval = 0.22
    }

    private let layoutSolver = CanvasInputIndicatorLayoutSolver()
    private let formatter = CanvasInputIndicatorFormatter()
    private let queue = CanvasInputIndicatorQueue()
    private let containerView = NSView()
    private let stackView = NSStackView()
    private var itemViewsByID: [UUID: macOSCanvasInputIndicatorItemView] = [:]
    private var currentSnapshot = CanvasInputIndicatorQueueSnapshot()
    private var currentLayoutContext: CanvasChromeLayoutContext?
    private var refreshTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.isHidden = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.distribution = .gravityAreas
        stackView.spacing = Layout.itemSpacing

        addSubview(containerView)
        containerView.addSubview(stackView)
        containerView.frame = .zero
        stackView.frame = .zero
    }

    override var isFlipped: Bool {
        true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        refreshTimer?.invalidate()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func record(event: CanvasInputIndicatorEvent) {
        let snapshot = queue.enqueue(event)
        applySnapshot(snapshot, animated: window != nil)
        updateRefreshTimerIfNeeded()
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        currentLayoutContext = layoutContext
        applyLayout()
        layoutSubtreeIfNeeded()
    }

    private func handleRefreshTimerTick() {
        let snapshot = queue.snapshot()
        let currentIDs = currentSnapshot.items.map(\.id)
        let nextIDs = snapshot.items.map(\.id)
        applySnapshot(
            snapshot,
            animated: currentIDs != nextIDs && window != nil
        )
        updateRefreshTimerIfNeeded()
    }

    private func updateRefreshTimerIfNeeded() {
        if currentSnapshot.isEmpty {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }

        guard refreshTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: queue.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.handleRefreshTimerTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func applySnapshot(
        _ snapshot: CanvasInputIndicatorQueueSnapshot,
        animated: Bool
    ) {
        let previousIDs = Set(currentSnapshot.items.map(\.id))
        let nextIDs = Set(snapshot.items.map(\.id))
        let removedIDs = previousIDs.subtracting(nextIDs)
        removedIDs.forEach(removeItemView)

        if snapshot.isEmpty {
            currentSnapshot = snapshot
            stackView.arrangedSubviews.forEach { arrangedSubview in
                stackView.removeArrangedSubview(arrangedSubview)
                arrangedSubview.removeFromSuperview()
            }
            itemViewsByID.removeAll()
            containerView.isHidden = true
            isHidden = true
            applyLayout()
            return
        }

        var orderedViews: [macOSCanvasInputIndicatorItemView] = []
        for item in snapshot.items {
            let view: macOSCanvasInputIndicatorItemView
            if let existingView = itemViewsByID[item.id] {
                view = existingView
            } else {
                let newView = macOSCanvasInputIndicatorItemView()
                newView.alphaValue = 0
                itemViewsByID[item.id] = newView
                view = newView
            }
            view.apply(text: formatter.text(for: item.event))
            orderedViews.append(view)
        }

        stackView.arrangedSubviews.forEach { arrangedSubview in
            stackView.removeArrangedSubview(arrangedSubview)
        }
        orderedViews.forEach { view in
            stackView.addArrangedSubview(view)
        }

        currentSnapshot = snapshot
        containerView.isHidden = false
        isHidden = false

        let applyVisualState = {
            for item in snapshot.items {
                guard let view = self.itemViewsByID[item.id] else {
                    continue
                }
                view.alphaValue = item.opacity
            }
            self.applyLayout()
            self.layoutSubtreeIfNeeded()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Layout.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for item in snapshot.items {
                    guard let view = self.itemViewsByID[item.id] else {
                        continue
                    }
                    view.animator().alphaValue = item.opacity
                }
                self.applyLayout()
                self.layoutSubtreeIfNeeded()
            }
        } else {
            applyVisualState()
        }
    }

    private func removeItemView(id: UUID) {
        guard let view = itemViewsByID.removeValue(forKey: id) else {
            return
        }

        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    private func applyLayout() {
        guard currentSnapshot.isEmpty == false else {
            hideContainer(resetFrame: true)
            return
        }

        let preferredSize = preferredContainerSize()
        guard preferredSize.width > 0, preferredSize.height > 0 else {
            hideContainer(resetFrame: true)
            return
        }

        guard let currentLayoutContext else {
            hideContainer(usingPreferredSize: preferredSize)
            return
        }

        guard let frame = layoutSolver.resolveHostFrame(
            preferredSize: preferredSize,
            layoutContext: currentLayoutContext
        ) else {
            hideContainer(usingPreferredSize: preferredSize)
            return
        }

        containerView.isHidden = false
        isHidden = false
        updateContainerFrame(frame)
    }

    private func hideContainer(
        resetFrame: Bool = false,
        usingPreferredSize preferredSize: CGSize? = nil
    ) {
        containerView.isHidden = true
        isHidden = true

        guard
            resetFrame == false,
            let preferredSize,
            preferredSize.width > 0,
            preferredSize.height > 0
        else {
            updateContainerFrame(.zero)
            return
        }

        // Keep a legal non-zero content frame while hidden so AppKit never
        // re-measures the live stack inside a 0x0 parent container.
        updateContainerFrame(
            CGRect(origin: .zero, size: preferredSize)
        )
    }

    private func updateContainerFrame(_ frame: CGRect) {
        let standardizedFrame = frame.standardized
        let sanitizedSize = CanvasChromeLayoutGeometry.sanitizedSize(
            standardizedFrame.size
        )
        containerView.frame = CGRect(
            x: standardizedFrame.minX,
            y: standardizedFrame.minY,
            width: sanitizedSize.width,
            height: sanitizedSize.height
        )
        stackView.frame = CGRect(origin: .zero, size: sanitizedSize)
    }

    private func preferredContainerSize() -> CGSize {
        let itemSizes = currentSnapshot.items.compactMap { item in
            itemViewsByID[item.id]?.measuredSize()
        }
        guard itemSizes.isEmpty == false else {
            return .zero
        }

        let maximumWidth = itemSizes.map(\.width).max() ?? 0
        let totalHeight = itemSizes.reduce(CGFloat(0)) { partialResult, size in
            partialResult + size.height
        }
        let spacingHeight = CGFloat(max(itemSizes.count - 1, 0)) * Layout.itemSpacing
        return CanvasChromeLayoutGeometry.sanitizedSize(
            CGSize(
                width: maximumWidth,
                height: totalHeight + spacingHeight
            )
        )
    }
}

private final class macOSCanvasInputIndicatorItemView: NSView {
    private enum Layout {
        static let horizontalInset: CGFloat = 14
        static let verticalInset: CGFloat = 8
        static let cornerRadius: CGFloat = 18
    }

    private let backgroundView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.94).cgColor
        view.layer?.cornerRadius = Layout.cornerRadius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        return view
    }()
    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(backgroundView)
        addSubview(label)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalInset)
        ])
    }

    override var isFlipped: Bool {
        true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func apply(text: String) {
        label.stringValue = text
        setAccessibilityLabel(text)
    }

    func measuredSize() -> CGSize {
        let labelSize = CanvasChromeLayoutGeometry.sanitizedSize(label.fittingSize)
        return CanvasChromeLayoutGeometry.sanitizedSize(
            CGSize(
                width: labelSize.width + Layout.horizontalInset * 2,
                height: labelSize.height + Layout.verticalInset * 2
            )
        )
    }
}
#endif
