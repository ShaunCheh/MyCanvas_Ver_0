import CoreGraphics
import Foundation

#if os(iOS)
import UIKit

final class SelectionAccessoryHostView: UIView {
    var onCommandSelected: ((CanvasCommandID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = SelectionAccessoryLayoutSolver()
    private let containerView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
    )
    private let stackView = UIStackView()
    private var containerLeadingConstraint: NSLayoutConstraint!
    private var containerTopConstraint: NSLayoutConstraint!
    private var containerWidthConstraint: NSLayoutConstraint!
    private var containerHeightConstraint: NSLayoutConstraint!
    private var commandIDs: [CanvasCommandID] = []
    private(set) var currentState: SelectionAccessoryState?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        isUserInteractionEnabled = true

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 16
        containerView.clipsToBounds = true
        containerView.isHidden = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 6

        addSubview(containerView)
        containerView.contentView.addSubview(stackView)
        containerLeadingConstraint = containerView.leadingAnchor.constraint(equalTo: leadingAnchor)
        containerTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
        containerWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: 0)
        containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            containerLeadingConstraint,
            containerTopConstraint,
            containerWidthConstraint,
            containerHeightConstraint,
            stackView.topAnchor.constraint(equalTo: containerView.contentView.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: containerView.contentView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: containerView.contentView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: containerView.contentView.bottomAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard currentState != nil, isHidden == false else {
            return nil
        }

        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard
            currentState != nil,
            let touch = touches.first
        else {
            super.touchesEnded(touches, with: event)
            return
        }

        let location = touch.location(in: self)
        if containerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    func apply(
        state: SelectionAccessoryState?,
        layoutContext: CanvasChromeLayoutContext
    ) {
        currentState = state

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildButtons(for: state)
        isHidden = false
        containerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        guard let currentState else {
            return
        }

        let preferredSize = preferredAccessorySize()
        guard let accessoryFrame = layoutSolver.resolveAccessoryFrame(
            anchorRect: currentState.anchorRect,
            preferredSize: preferredSize,
            layoutContext: layoutContext
        ) else {
            updateContainerConstraints(.zero)
            return
        }

        updateContainerConstraints(accessoryFrame.integral)
        layoutIfNeeded()
    }

    func dismiss() {
        currentState = nil
        commandIDs = []
        stackView.arrangedSubviews.forEach { arrangedSubview in
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        updateContainerConstraints(.zero)
        containerView.isHidden = true
        isHidden = true
    }

    private func rebuildButtons(for state: SelectionAccessoryState) {
        commandIDs = []
        stackView.arrangedSubviews.forEach { arrangedSubview in
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for actionState in state.actionStates {
            let button = makeActionButton(for: actionState)
            button.tag = commandIDs.count
            commandIDs.append(actionState.commandID)
            stackView.addArrangedSubview(button)
        }
    }

    private func makeActionButton(
        for actionState: SelectionAccessoryActionState
    ) -> UIButton {
        let descriptor = actionState.descriptor
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        button.layer.cornerRadius = 10
        button.layer.masksToBounds = true
        button.backgroundColor = descriptor.isActive
            ? UIColor.systemOrange.withAlphaComponent(0.14)
            : .clear
        button.isEnabled = descriptor.isEnabled

        var configuration = UIButton.Configuration.plain()
        configuration.title = descriptor.title
        configuration.image = UIImage(systemName: descriptor.systemImageName)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 6
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 10,
            bottom: 8,
            trailing: 10
        )
        configuration.baseForegroundColor = descriptor.isEnabled
            ? (descriptor.isActive ? .systemOrange : .label)
            : .secondaryLabel
        button.configuration = configuration
        button.addTarget(self, action: #selector(handleActionButtonTap(_:)), for: .touchUpInside)
        return button
    }

    @objc
    private func handleActionButtonTap(_ sender: UIButton) {
        let index = sender.tag
        guard commandIDs.indices.contains(index) else {
            return
        }

        onCommandSelected?(commandIDs[index])
    }

    private func preferredAccessorySize() -> CGSize {
        let stackSize = stackView.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize
        )
        return CGSize(
            width: stackSize.width + 16,
            height: stackSize.height + 16
        )
    }

    private func updateContainerConstraints(_ frame: CGRect) {
        let standardizedFrame = frame.standardized
        containerLeadingConstraint.constant = standardizedFrame.minX
        containerTopConstraint.constant = standardizedFrame.minY
        containerWidthConstraint.constant = max(0, standardizedFrame.width)
        containerHeightConstraint.constant = max(0, standardizedFrame.height)
    }
}

#elseif os(macOS)
import AppKit

final class SelectionAccessoryHostView: NSView {
    private static let isTraceLoggingEnabled = false

    var onCommandSelected: ((CanvasCommandID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = SelectionAccessoryLayoutSolver()
    private let containerView = NSVisualEffectView()
    private let stackView = NSStackView()
    private var commandIDs: [CanvasCommandID] = []
    private(set) var currentState: SelectionAccessoryState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.material = .menu
        containerView.blendingMode = .withinWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        containerView.isHidden = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .gravityAreas
        stackView.spacing = 6

        addSubview(containerView)
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
    }

    override var isFlipped: Bool {
        true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard currentState != nil, isHidden == false else {
            return nil
        }

        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    override func mouseDown(with event: NSEvent) {
        guard currentState != nil else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if containerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard currentState != nil else {
            super.rightMouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if containerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    func apply(
        state: SelectionAccessoryState?,
        layoutContext: CanvasChromeLayoutContext
    ) {
        currentState = state
        logApply(
            state: state,
            layoutContext: layoutContext
        )

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildButtons(for: state)
        isHidden = false
        containerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        guard let currentState else {
            return
        }

        let preferredSize = preferredAccessorySize()
        let resolvedAccessoryFrame = layoutSolver.resolveAccessoryFrame(
            anchorRect: currentState.anchorRect,
            preferredSize: preferredSize,
            layoutContext: layoutContext
        )
        logLayout(
            state: currentState,
            layoutContext: layoutContext,
            preferredSize: preferredSize,
            resolvedAccessoryFrame: resolvedAccessoryFrame
        )
        guard let accessoryFrame = resolvedAccessoryFrame else {
            containerView.frame = .zero
            return
        }

        containerView.frame = accessoryFrame.integral
        synchronizeLayoutAfterFrameChange()
    }

    func dismiss() {
        currentState = nil
        commandIDs = []
        stackView.arrangedSubviews.forEach { arrangedSubview in
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        containerView.frame = .zero
        containerView.isHidden = true
        isHidden = true
    }

    private func rebuildButtons(for state: SelectionAccessoryState) {
        commandIDs = []
        stackView.arrangedSubviews.forEach { arrangedSubview in
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for actionState in state.actionStates {
            let button = makeActionButton(for: actionState)
            button.tag = commandIDs.count
            commandIDs.append(actionState.commandID)
            stackView.addArrangedSubview(button)
        }
    }

    private func makeActionButton(
        for actionState: SelectionAccessoryActionState
    ) -> NSButton {
        let descriptor = actionState.descriptor
        let button = NSButton(
            title: descriptor.title,
            target: self,
            action: #selector(handleActionButtonClick(_:))
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.image = NSImage(
            systemSymbolName: descriptor.systemImageName,
            accessibilityDescription: descriptor.title
        )
        button.imagePosition = .imageLeading
        button.alignment = .center
        button.contentTintColor = descriptor.isEnabled
            ? (descriptor.isActive ? .systemOrange : .labelColor)
            : .secondaryLabelColor
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.isEnabled = descriptor.isEnabled
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = descriptor.isActive
            ? NSColor.systemOrange.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
        return button
    }

    @objc
    private func handleActionButtonClick(_ sender: NSButton) {
        let index = sender.tag
        guard commandIDs.indices.contains(index) else {
            return
        }

        onCommandSelected?(commandIDs[index])
    }

    private func preferredAccessorySize() -> CGSize {
        let stackSize = stackView.fittingSize
        return CGSize(
            width: stackSize.width + 16,
            height: stackSize.height + 16
        )
    }

    private func synchronizeLayoutAfterFrameChange() {
        // AppKit will otherwise leave the stack view at zero size on the first
        // presentation after a manual frame update, so flush the layout now.
        needsLayout = true
        containerView.needsLayout = true
        stackView.needsLayout = true
        layoutSubtreeIfNeeded()
        containerView.layoutSubtreeIfNeeded()
    }

    private func logApply(
        state: SelectionAccessoryState?,
        layoutContext: CanvasChromeLayoutContext
    ) {
        guard Self.isTraceLoggingEnabled else {
            return
        }

        let resolvedActionStates = state?.actionStates.map {
            "\(String(describing: $0.commandID)) enabled=\($0.descriptor.isEnabled)"
        }.joined(separator: ", ") ?? "nil"
        print(
            "[Canvas macOS][MarkdownAccessoryHost] " +
            "event=apply " +
            "stateItemID=\(state.map { $0.itemID.uuidString } ?? "nil") " +
            "stateAnchorRect=\(state.map { Self.describe(rect: $0.anchorRect) } ?? "nil") " +
            "stateIsEmpty=\(state?.isEmpty ?? true) " +
            "actionCount=\(state?.actionStates.count ?? 0) " +
            "actionStates=[\(resolvedActionStates)] " +
            "layoutSafeBounds=\(Self.describe(rect: layoutContext.safeBounds)) " +
            "hostBounds=\(Self.describe(rect: bounds)) " +
            "hostFrame=\(Self.describe(rect: frame)) " +
            "containerFrame=\(Self.describe(rect: containerView.frame))"
        )
    }

    private func logLayout(
        state: SelectionAccessoryState,
        layoutContext: CanvasChromeLayoutContext,
        preferredSize: CGSize,
        resolvedAccessoryFrame: CGRect?
    ) {
        guard Self.isTraceLoggingEnabled else {
            return
        }

        print(
            "[Canvas macOS][MarkdownAccessoryHost] " +
            "event=layout " +
            "stateItemID=\(state.itemID.uuidString) " +
            "anchorRect=\(Self.describe(rect: state.anchorRect)) " +
            "preferredSize=\(Self.describe(size: preferredSize)) " +
            "stackFittingSize=\(Self.describe(size: stackView.fittingSize)) " +
            "stackFrame=\(Self.describe(rect: stackView.frame)) " +
            "layoutSafeBounds=\(Self.describe(rect: layoutContext.safeBounds)) " +
            "occupiedRectCount=\(layoutContext.occupiedRects.count) " +
            "hostBounds=\(Self.describe(rect: bounds)) " +
            "hostFrame=\(Self.describe(rect: frame)) " +
            "resolvedAccessoryFrame=\(resolvedAccessoryFrame.map { Self.describe(rect: $0) } ?? "nil")"
        )
    }

    private static func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private static func describe(size: CGSize) -> String {
        "{\(formatCoordinate(size.width)), \(formatCoordinate(size.height))}"
    }

    private static func describe(rect: CGRect) -> String {
        "{{\(formatCoordinate(rect.origin.x)), \(formatCoordinate(rect.origin.y))}, {\(formatCoordinate(rect.size.width)), \(formatCoordinate(rect.size.height))}}"
    }
}

#endif
