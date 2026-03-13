//
//  macOSViewController.swift
//  MyCanvas_Ver_0
//
//  Created by Shaun on 2026/3/13.
//

#if os(macOS)
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

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
    private let importButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Import image") {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = "+"
        }
        return button
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
        setupImportButton()
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
        view.addSubview(importButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            importButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            importButton.widthAnchor.constraint(equalToConstant: 44),
            importButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupImportButton() {
        importButton.target = self
        importButton.action = #selector(handleImportButtonClick)
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

    @objc
    private func handleImportButtonClick() {
        guard let window = view.window else {
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard
                response == .OK,
                let url = openPanel.url,
                let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else {
                return
            }

            self?.appendImportedImage(cgImage)
        }
    }

    private func appendImportedImage(_ cgImage: CGImage) {
        let item = CanvasImageItem(
            cgImage: cgImage,
            center: camera.center,
            size: normalizedDisplaySize(for: cgImage),
            zIndex: nextImageZIndex()
        )

        scene.append(item)
        refreshCanvas()
    }

    private func normalizedDisplaySize(for cgImage: CGImage) -> CGSize {
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let longestSide = max(pixelSize.width, pixelSize.height)
        guard longestSide > 0 else {
            return CGSize(width: 240, height: 240)
        }

        let targetLongestSide: CGFloat = 320
        let scale = targetLongestSide / longestSide
        return CGSize(
            width: pixelSize.width * scale,
            height: pixelSize.height * scale
        )
    }

    private func nextImageZIndex() -> CGFloat {
        (scene.orderedItems().last?.zIndex ?? -1) + 1
    }
}
#endif
