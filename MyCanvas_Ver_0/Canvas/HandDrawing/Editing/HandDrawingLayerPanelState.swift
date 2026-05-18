import Foundation

struct HandDrawingLayerPanelRowState: Equatable {
    let id: UUID
    var name: String
    var subtitle: String?
    var isActive: Bool
    var isVisible: Bool
    var isLocked: Bool
    var canMoveUp: Bool
    var canMoveDown: Bool
    var canDelete: Bool
}

struct HandDrawingLayerPanelState: Equatable {
    var buttonTitle: String
    var buttonSubtitle: String
    var canAddLayer: Bool
    var layers: [HandDrawingLayerPanelRowState]
}

enum HandDrawingLayerPanelStateBuilder {
    static func makeState(
        from document: HandDrawingDocument
    ) -> HandDrawingLayerPanelState {
        let layers = document.layers
        return HandDrawingLayerPanelState(
            buttonTitle: "Layers (\(layers.count))",
            buttonSubtitle: document.activeLayer?.name ?? "Layer",
            canAddLayer: true,
            layers: layers.enumerated().reversed().map { index, layer in
                let isActive = layer.id == document.activeLayerID
                return HandDrawingLayerPanelRowState(
                    id: layer.id,
                    name: layer.name,
                    subtitle: layerRowSubtitle(for: layer, isActive: isActive),
                    isActive: isActive,
                    isVisible: layer.isVisible,
                    isLocked: layer.isLocked,
                    canMoveUp: index < layers.count - 1,
                    canMoveDown: index > 0,
                    canDelete: layers.count > 1
                )
            }
        )
    }

    private static func layerRowSubtitle(
        for layer: HandDrawingLayer,
        isActive: Bool
    ) -> String? {
        var components: [String] = []
        if isActive {
            components.append("Current")
        }
        if layer.isVisible == false {
            components.append("Hidden")
        }
        if layer.isLocked {
            components.append("Locked")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }
}
