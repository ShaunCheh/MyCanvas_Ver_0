import CoreGraphics
import Foundation

#if os(iOS)
import UIKit

final class BoardListActionPanelHostView: UIView {
    var onActionSelected: ((BoardListActionID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = BoardListActionPanelLayoutSolver()
    private let layoutConfiguration = BoardListActionPanelLayoutConfiguration()
    private let panelContainerView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
    )
    private let actionStackView = UIStackView()
    private var panelLeadingConstraint: NSLayoutConstraint!
    private var panelTopConstraint: NSLayoutConstraint!
    private var panelWidthConstraint: NSLayoutConstraint!
    private var panelHeightConstraint: NSLayoutConstraint!
    private var actionIDs: [BoardListActionID] = []
    private(set) var currentState: BoardListActionPanelState?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isHidden = true
        isUserInteractionEnabled = true

        panelContainerView.translatesAutoresizingMaskIntoConstraints = false
        panelContainerView.layer.cornerRadius = 16
        panelContainerView.clipsToBounds = true
        panelContainerView.isHidden = true

        actionStackView.translatesAutoresizingMaskIntoConstraints = false
        actionStackView.axis = .vertical
        actionStackView.alignment = .fill
        actionStackView.distribution = .fill
        actionStackView.spacing = 6

        addSubview(panelContainerView)
        panelContainerView.contentView.addSubview(actionStackView)
        panelLeadingConstraint = panelContainerView.leadingAnchor.constraint(equalTo: leadingAnchor)
        panelTopConstraint = panelContainerView.topAnchor.constraint(equalTo: topAnchor)
        panelWidthConstraint = panelContainerView.widthAnchor.constraint(equalToConstant: 0)
        panelHeightConstraint = panelContainerView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            panelLeadingConstraint,
            panelTopConstraint,
            panelWidthConstraint,
            panelHeightConstraint,
            actionStackView.topAnchor.constraint(equalTo: panelContainerView.contentView.topAnchor, constant: 10),
            actionStackView.leadingAnchor.constraint(equalTo: panelContainerView.contentView.leadingAnchor, constant: 10),
            actionStackView.trailingAnchor.constraint(equalTo: panelContainerView.contentView.trailingAnchor, constant: -10),
            actionStackView.bottomAnchor.constraint(equalTo: panelContainerView.contentView.bottomAnchor, constant: -10)
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
        if panelContainerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    func apply(
        state: BoardListActionPanelState?,
        layoutContext: BoardListActionPanelLayoutContext
    ) {
        currentState = state

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildActionButtons(for: state)
        isHidden = false
        panelContainerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }

    func updateLayout(layoutContext: BoardListActionPanelLayoutContext) {
        guard let currentState else {
            return
        }

        let preferredSize = preferredPanelSize()
        guard let panelFrame = layoutSolver.resolvePanelFrame(
            anchorPoint: currentState.layoutAnchorPoint,
            preferredSize: preferredSize,
            layoutContext: layoutContext,
            configuration: layoutConfiguration
        ) else {
            updatePanelContainerConstraints(.zero)
            return
        }

        updatePanelContainerConstraints(panelFrame.integral)
        layoutIfNeeded()
    }

    func dismiss() {
        currentState = nil
        actionIDs = []
        actionStackView.arrangedSubviews.forEach { arrangedSubview in
            actionStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        updatePanelContainerConstraints(.zero)
        panelContainerView.isHidden = true
        isHidden = true
    }

    private func rebuildActionButtons(
        for state: BoardListActionPanelState
    ) {
        actionIDs = []
        actionStackView.arrangedSubviews.forEach { arrangedSubview in
            actionStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for actionState in state.actionStates {
            let button = makeActionButton(for: actionState)
            button.tag = actionIDs.count
            actionIDs.append(actionState.id)
            actionStackView.addArrangedSubview(button)
        }
    }

    private func makeActionButton(
        for actionState: BoardListActionState
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        button.contentHorizontalAlignment = .leading
        button.isEnabled = actionState.isEnabled
        button.layer.cornerRadius = 10
        button.layer.masksToBounds = true
        button.backgroundColor = .clear

        var configuration = UIButton.Configuration.plain()
        configuration.title = actionState.title
        configuration.image = actionState.systemImageName.flatMap(UIImage.init(systemName:))
        configuration.imagePlacement = .leading
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 10,
            bottom: 8,
            trailing: 10
        )
        configuration.baseForegroundColor = foregroundColor(for: actionState)
        button.configuration = configuration
        button.addTarget(self, action: #selector(handleActionButtonTap(_:)), for: .touchUpInside)
        return button
    }

    @objc
    private func handleActionButtonTap(_ sender: UIButton) {
        let index = sender.tag
        guard actionIDs.indices.contains(index) else {
            return
        }

        onActionSelected?(actionIDs[index])
    }

    private func updatePanelContainerConstraints(_ frame: CGRect) {
        let standardizedFrame = frame.standardized
        panelLeadingConstraint.constant = standardizedFrame.minX
        panelTopConstraint.constant = standardizedFrame.minY
        panelWidthConstraint.constant = max(0, standardizedFrame.width)
        panelHeightConstraint.constant = max(0, standardizedFrame.height)
    }

    private func preferredPanelSize() -> CGSize {
        let stackSize = actionStackView.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize
        )
        return CGSize(
            width: stackSize.width + 20,
            height: stackSize.height + 20
        )
    }

    private func foregroundColor(
        for actionState: BoardListActionState
    ) -> UIColor {
        guard actionState.isEnabled else {
            return .secondaryLabel
        }

        switch actionState.role {
        case .standard:
            return .label
        case .destructive:
            return .systemRed
        }
    }
}
#elseif os(macOS)
import AppKit

final class BoardListActionPanelHostView: NSView {
    var onActionSelected: ((BoardListActionID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = BoardListActionPanelLayoutSolver()
    private let layoutConfiguration = BoardListActionPanelLayoutConfiguration()
    private let panelContainerView = NSVisualEffectView()
    private let actionStackView = NSStackView()
    private var actionIDs: [BoardListActionID] = []
    private(set) var currentState: BoardListActionPanelState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true

        panelContainerView.translatesAutoresizingMaskIntoConstraints = false
        panelContainerView.material = .menu
        panelContainerView.blendingMode = .withinWindow
        panelContainerView.state = .active
        panelContainerView.wantsLayer = true
        panelContainerView.layer?.cornerRadius = 14
        panelContainerView.layer?.masksToBounds = true
        panelContainerView.isHidden = true

        actionStackView.translatesAutoresizingMaskIntoConstraints = false
        actionStackView.orientation = .vertical
        actionStackView.alignment = .leading
        actionStackView.distribution = .gravityAreas
        actionStackView.spacing = 6

        addSubview(panelContainerView)
        panelContainerView.addSubview(actionStackView)
        NSLayoutConstraint.activate([
            actionStackView.topAnchor.constraint(equalTo: panelContainerView.topAnchor, constant: 10),
            actionStackView.leadingAnchor.constraint(equalTo: panelContainerView.leadingAnchor, constant: 10),
            actionStackView.trailingAnchor.constraint(equalTo: panelContainerView.trailingAnchor, constant: -10),
            actionStackView.bottomAnchor.constraint(equalTo: panelContainerView.bottomAnchor, constant: -10)
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
        if panelContainerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard currentState != nil else {
            super.rightMouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if panelContainerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    func apply(
        state: BoardListActionPanelState?,
        layoutContext: BoardListActionPanelLayoutContext
    ) {
        currentState = state

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildActionButtons(for: state)
        isHidden = false
        panelContainerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }

    func updateLayout(layoutContext: BoardListActionPanelLayoutContext) {
        guard let currentState else {
            return
        }

        let preferredSize = preferredPanelSize()
        guard let panelFrame = layoutSolver.resolvePanelFrame(
            anchorPoint: currentState.layoutAnchorPoint,
            preferredSize: preferredSize,
            layoutContext: layoutContext,
            configuration: layoutConfiguration
        ) else {
            panelContainerView.frame = .zero
            return
        }

        panelContainerView.frame = panelFrame.integral
    }

    func dismiss() {
        currentState = nil
        actionIDs = []
        actionStackView.arrangedSubviews.forEach { arrangedSubview in
            actionStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        panelContainerView.frame = .zero
        panelContainerView.isHidden = true
        isHidden = true
    }

    private func rebuildActionButtons(
        for state: BoardListActionPanelState
    ) {
        actionIDs = []
        actionStackView.arrangedSubviews.forEach { arrangedSubview in
            actionStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for actionState in state.actionStates {
            let button = makeActionButton(for: actionState)
            button.tag = actionIDs.count
            actionIDs.append(actionState.id)
            actionStackView.addArrangedSubview(button)
        }
    }

    private func makeActionButton(
        for actionState: BoardListActionState
    ) -> NSButton {
        let button = NSButton(
            title: actionState.title,
            target: self,
            action: #selector(handleActionButtonClick(_:))
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.image = actionState.systemImageName.flatMap {
            NSImage(
                systemSymbolName: $0,
                accessibilityDescription: actionState.title
            )
        }
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.contentTintColor = foregroundColor(for: actionState)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.isEnabled = actionState.isEnabled
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = NSColor.clear.cgColor
        return button
    }

    @objc
    private func handleActionButtonClick(_ sender: NSButton) {
        let index = sender.tag
        guard actionIDs.indices.contains(index) else {
            return
        }

        onActionSelected?(actionIDs[index])
    }

    private func preferredPanelSize() -> CGSize {
        let stackSize = actionStackView.fittingSize
        return CGSize(
            width: stackSize.width + 20,
            height: stackSize.height + 20
        )
    }

    private func foregroundColor(
        for actionState: BoardListActionState
    ) -> NSColor {
        guard actionState.isEnabled else {
            return .secondaryLabelColor
        }

        switch actionState.role {
        case .standard:
            return .labelColor
        case .destructive:
            return .systemRed
        }
    }
}
#endif
