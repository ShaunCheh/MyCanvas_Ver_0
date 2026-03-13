//
//  macOSViewController.swift
//  MyCanvas_Ver_0
//
//  Created by Shaun on 2026/3/13.
//

#if os(macOS)
import Foundation
import AppKit

final class macOSViewController: NSViewController {
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private let renderer = CanvasRenderer()
    private let canvasHostView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.masksToBounds = true
        return view
    }()
    private let canvasViewportView = macOSCanvasViewportView()
    private var canvasContentView: NSView?

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupCanvasViewport()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCameraViewportSizeIfNeeded()
    }

    // Future canvas viewport views should always be mounted through this host.
    func installCanvasContentView(_ contentView: NSView) {
        _ = view
        canvasContentView?.removeFromSuperview()

        contentView.translatesAutoresizingMaskIntoConstraints = false
        canvasHostView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: canvasHostView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: canvasHostView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: canvasHostView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: canvasHostView.bottomAnchor)
        ])

        canvasContentView = contentView
    }

    private func setupViewHierarchy() {
        view.addSubview(canvasHostView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupCanvasViewport() {
        canvasViewportView.onPan = { [weak self] translation in
            self?.handlePan(translation)
        }
        canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
            self?.handleZoom(scaleDelta, around: anchor)
        }

        installCanvasContentView(canvasViewportView)
        refreshCanvas()
    }

    private func updateCameraViewportSizeIfNeeded() {
        let viewportSize = canvasViewportView.bounds.size
        guard viewportSize != camera.viewportSize else {
            return
        }

        camera.setViewportSize(viewportSize)
        refreshCanvas()
    }

    private func handlePan(_ translation: CGPoint) {
        camera.pan(by: translation)
        refreshCanvas()
    }

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        camera.zoom(by: scaleDelta, around: anchor)
        refreshCanvas()
    }

    private func refreshCanvas() {
        let snapshot = renderer.makeSnapshot(scene: scene, camera: camera)
        canvasViewportView.apply(snapshot)
    }
}
#endif
