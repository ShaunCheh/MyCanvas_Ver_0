import CoreGraphics
import Foundation

#if os(iOS)
import UIKit

final class CanvasContextMenuHostView: UIView {
    var onCommandSelected: ((CanvasCommandID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = CanvasContextMenuLayoutSolver()
    private let layoutConfiguration: CanvasContextMenuLayoutConfiguration = {
        var configuration = CanvasContextMenuLayoutConfiguration()
        configuration.placementStyle = .cursorPreferred
        return configuration
    }()
    private let menuContainerView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
    )
    private let commandStackView = UIStackView()
    private var menuLeadingConstraint: NSLayoutConstraint!
    private var menuTopConstraint: NSLayoutConstraint!
    private var menuWidthConstraint: NSLayoutConstraint!
    private var menuHeightConstraint: NSLayoutConstraint!
    private var commandIDs: [CanvasCommandID] = []
    private(set) var currentState: CanvasContextMenuState?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isHidden = true
        isUserInteractionEnabled = true

        menuContainerView.translatesAutoresizingMaskIntoConstraints = false
        menuContainerView.layer.cornerRadius = 16
        menuContainerView.clipsToBounds = true
        menuContainerView.isHidden = true

        commandStackView.translatesAutoresizingMaskIntoConstraints = false
        commandStackView.axis = .vertical
        commandStackView.alignment = .fill
        commandStackView.distribution = .fill
        commandStackView.spacing = 6

        addSubview(menuContainerView)
        menuContainerView.contentView.addSubview(commandStackView)
        menuLeadingConstraint = menuContainerView.leadingAnchor.constraint(equalTo: leadingAnchor)
        menuTopConstraint = menuContainerView.topAnchor.constraint(equalTo: topAnchor)
        menuWidthConstraint = menuContainerView.widthAnchor.constraint(equalToConstant: 0)
        menuHeightConstraint = menuContainerView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            menuLeadingConstraint,
            menuTopConstraint,
            menuWidthConstraint,
            menuHeightConstraint,
            commandStackView.topAnchor.constraint(equalTo: menuContainerView.contentView.topAnchor, constant: 10),
            commandStackView.leadingAnchor.constraint(equalTo: menuContainerView.contentView.leadingAnchor, constant: 10),
            commandStackView.trailingAnchor.constraint(equalTo: menuContainerView.contentView.trailingAnchor, constant: -10),
            commandStackView.bottomAnchor.constraint(equalTo: menuContainerView.contentView.bottomAnchor, constant: -10)
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
        return hitView === self ? self : hitView
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
        if menuContainerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    func apply(
        state: CanvasContextMenuState?,
        layoutContext: CanvasChromeLayoutContext
    ) {
        currentState = state

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildCommandButtons(for: state)
        isHidden = false
        menuContainerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        guard let currentState else {
            return
        }

        let preferredSize = preferredMenuSize()
        guard let menuFrame = layoutSolver.resolveMenuFrame(
            anchorPoint: currentState.layoutAnchorPoint,
            preferredSize: preferredSize,
            safeBounds: layoutContext.safeBounds,
            occupiedRects: layoutContext.occupiedRects,
            configuration: layoutConfiguration
        ) else {
            logContextMenuLayout(
                platform: "iOS",
                state: currentState,
                hostBounds: bounds,
                safeBounds: layoutContext.safeBounds,
                occupiedRects: layoutContext.occupiedRects,
                preferredSize: preferredSize,
                resolvedMenuFrame: nil
            )
            updateMenuContainerConstraints(.zero)
            return
        }

        logContextMenuLayout(
            platform: "iOS",
            state: currentState,
            hostBounds: bounds,
            safeBounds: layoutContext.safeBounds,
            occupiedRects: layoutContext.occupiedRects,
            preferredSize: preferredSize,
            resolvedMenuFrame: menuFrame
        )
        updateMenuContainerConstraints(menuFrame.integral)
        layoutIfNeeded()
    }

    func dismiss() {
        currentState = nil
        commandIDs = []
        commandStackView.arrangedSubviews.forEach { arrangedSubview in
            commandStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        updateMenuContainerConstraints(.zero)
        menuContainerView.isHidden = true
        isHidden = true
    }

    private func rebuildCommandButtons(for state: CanvasContextMenuState) {
        commandIDs = []
        commandStackView.arrangedSubviews.forEach { arrangedSubview in
            commandStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for commandState in state.commandStates {
            let button = makeCommandButton(for: commandState)
            button.tag = commandIDs.count
            commandIDs.append(commandState.commandID)
            commandStackView.addArrangedSubview(button)
        }
    }

    private func makeCommandButton(
        for commandState: CanvasContextMenuCommandState
    ) -> UIButton {
        let descriptor = commandState.descriptor
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        button.contentHorizontalAlignment = .leading
        button.isEnabled = descriptor.isEnabled
        button.layer.cornerRadius = 10
        button.layer.masksToBounds = true
        button.backgroundColor = descriptor.isActive
            ? UIColor.systemOrange.withAlphaComponent(0.14)
            : .clear

        var configuration = UIButton.Configuration.plain()
        configuration.title = descriptor.title
        configuration.image = UIImage(systemName: descriptor.systemImageName)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 8
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
        button.addTarget(self, action: #selector(handleCommandButtonTap(_:)), for: .touchUpInside)
        return button
    }

    @objc
    private func handleCommandButtonTap(_ sender: UIButton) {
        let index = sender.tag
        guard commandIDs.indices.contains(index) else {
            return
        }

        onCommandSelected?(commandIDs[index])
    }

    private func updateMenuContainerConstraints(_ frame: CGRect) {
        let standardizedFrame = frame.standardized
        menuLeadingConstraint.constant = standardizedFrame.minX
        menuTopConstraint.constant = standardizedFrame.minY
        menuWidthConstraint.constant = max(0, standardizedFrame.width)
        menuHeightConstraint.constant = max(0, standardizedFrame.height)
    }

    private func preferredMenuSize() -> CGSize {
        let stackSize = commandStackView.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize
        )
        return CGSize(
            width: stackSize.width + 20,
            height: stackSize.height + 20
        )
    }
}
#elseif os(macOS)
import AppKit

final class CanvasContextMenuHostView: NSView {
    var onCommandSelected: ((CanvasCommandID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = CanvasContextMenuLayoutSolver()
    private let layoutConfiguration: CanvasContextMenuLayoutConfiguration = {
        var configuration = CanvasContextMenuLayoutConfiguration()
        configuration.placementStyle = .cursorPreferred
        return configuration
    }()
    private let menuContainerView = NSVisualEffectView()
    private let commandStackView = NSStackView()
    private var commandIDs: [CanvasCommandID] = []
    private(set) var currentState: CanvasContextMenuState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true

        menuContainerView.translatesAutoresizingMaskIntoConstraints = false
        menuContainerView.material = .menu
        menuContainerView.blendingMode = .withinWindow
        menuContainerView.state = .active
        menuContainerView.wantsLayer = true
        menuContainerView.layer?.cornerRadius = 14
        menuContainerView.layer?.masksToBounds = true
        menuContainerView.isHidden = true

        commandStackView.translatesAutoresizingMaskIntoConstraints = false
        commandStackView.orientation = .vertical
        commandStackView.alignment = .leading
        commandStackView.distribution = .gravityAreas
        commandStackView.spacing = 6

        addSubview(menuContainerView)
        menuContainerView.addSubview(commandStackView)
        NSLayoutConstraint.activate([
            commandStackView.topAnchor.constraint(equalTo: menuContainerView.topAnchor, constant: 10),
            commandStackView.leadingAnchor.constraint(equalTo: menuContainerView.leadingAnchor, constant: 10),
            commandStackView.trailingAnchor.constraint(equalTo: menuContainerView.trailingAnchor, constant: -10),
            commandStackView.bottomAnchor.constraint(equalTo: menuContainerView.bottomAnchor, constant: -10)
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
        return hitView === self ? self : hitView
    }

    override func mouseDown(with event: NSEvent) {
        guard currentState != nil else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if menuContainerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard currentState != nil else {
            super.rightMouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if menuContainerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    func apply(
        state: CanvasContextMenuState?,
        layoutContext: CanvasChromeLayoutContext
    ) {
        currentState = state

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildCommandButtons(for: state)
        isHidden = false
        menuContainerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        guard let currentState else {
            return
        }

        let preferredSize = preferredMenuSize()
        guard let menuFrame = layoutSolver.resolveMenuFrame(
            anchorPoint: currentState.layoutAnchorPoint,
            preferredSize: preferredSize,
            safeBounds: layoutContext.safeBounds,
            occupiedRects: layoutContext.occupiedRects,
            configuration: layoutConfiguration
        ) else {
            logContextMenuLayout(
                platform: "macOS",
                state: currentState,
                hostBounds: bounds,
                safeBounds: layoutContext.safeBounds,
                occupiedRects: layoutContext.occupiedRects,
                preferredSize: preferredSize,
                resolvedMenuFrame: nil
            )
            menuContainerView.frame = .zero
            return
        }

        logContextMenuLayout(
            platform: "macOS",
            state: currentState,
            hostBounds: bounds,
            safeBounds: layoutContext.safeBounds,
            occupiedRects: layoutContext.occupiedRects,
            preferredSize: preferredSize,
            resolvedMenuFrame: menuFrame
        )
        menuContainerView.frame = menuFrame.integral
    }

    func dismiss() {
        currentState = nil
        commandIDs = []
        commandStackView.arrangedSubviews.forEach { arrangedSubview in
            commandStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        menuContainerView.frame = .zero
        menuContainerView.isHidden = true
        isHidden = true
    }

    private func rebuildCommandButtons(for state: CanvasContextMenuState) {
        commandIDs = []
        commandStackView.arrangedSubviews.forEach { arrangedSubview in
            commandStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for commandState in state.commandStates {
            let button = makeCommandButton(for: commandState)
            button.tag = commandIDs.count
            commandIDs.append(commandState.commandID)
            commandStackView.addArrangedSubview(button)
        }
    }

    private func makeCommandButton(
        for commandState: CanvasContextMenuCommandState
    ) -> NSButton {
        let descriptor = commandState.descriptor
        let button = NSButton(title: descriptor.title, target: self, action: #selector(handleCommandButtonClick(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.image = NSImage(
            systemSymbolName: descriptor.systemImageName,
            accessibilityDescription: descriptor.title
        )
        button.imagePosition = .imageLeading
        button.alignment = .left
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
    private func handleCommandButtonClick(_ sender: NSButton) {
        let index = sender.tag
        guard commandIDs.indices.contains(index) else {
            return
        }

        onCommandSelected?(commandIDs[index])
    }

    private func preferredMenuSize() -> CGSize {
        let stackSize = commandStackView.fittingSize
        return CGSize(
            width: stackSize.width + 20,
            height: stackSize.height + 20
        )
    }
}
#endif

private func logContextMenuLayout(
    platform: String,
    state: CanvasContextMenuState,
    hostBounds: CGRect,
    safeBounds: CGRect,
    occupiedRects: [CGRect],
    preferredSize: CGSize,
    resolvedMenuFrame: CGRect?
) {
    let occupiedRectsDescription = occupiedRects.isEmpty
        ? "[]"
        : occupiedRects.map(contextMenuHostDescribe).joined(separator: ", ")
    let commandIDsDescription = state.commandStates
        .map(\.commandID.rawValue)
        .joined(separator: ",")

    print(
        "[Canvas \(platform)][ContextMenuLayout] " +
        state.resolvedContext.debugSummary + " " +
        "layoutAnchorPoint=\(contextMenuHostDescribe(state.layoutAnchorPoint)) " +
        "hostBounds=\(contextMenuHostDescribe(hostBounds)) " +
        "safeBounds=\(contextMenuHostDescribe(safeBounds)) " +
        "preferredSize=\(contextMenuHostDescribe(preferredSize)) " +
        "resolvedMenuFrame=\(resolvedMenuFrame.map(contextMenuHostDescribe) ?? "nil") " +
        "occupiedRects=[\(occupiedRectsDescription)] " +
        "commandIDs=[\(commandIDsDescription)]"
    )
}

private func contextMenuHostDescribe(_ point: CGPoint) -> String {
    "{\(contextMenuHostFormat(point.x)), \(contextMenuHostFormat(point.y))}"
}

private func contextMenuHostDescribe(_ size: CGSize) -> String {
    "{\(contextMenuHostFormat(size.width)), \(contextMenuHostFormat(size.height))}"
}

private func contextMenuHostDescribe(_ rect: CGRect) -> String {
    "{{\(contextMenuHostFormat(rect.origin.x)), \(contextMenuHostFormat(rect.origin.y))}, {\(contextMenuHostFormat(rect.size.width)), \(contextMenuHostFormat(rect.size.height))}}"
}

private func contextMenuHostFormat(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
