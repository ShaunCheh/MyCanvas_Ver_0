import CoreGraphics
import Foundation
#if canImport(Metal)
import Metal
import MetalKit

enum HandDrawingGPUCommittedCanvasBackendError: LocalizedError {
    case metalUnavailable
    case failedToCreateCommandQueue
    case failedToCreateTexture(width: Int, height: Int)
    case failedToCreateCommandBuffer
    case failedToCreateRenderEncoder
    case failedToCreateBitmapContext(width: Int, height: Int)
    case failedToCreateStrokeImage
    case failedToCreateImageBuffer
    case failedToCreateImageDataProvider
    case failedToCreateCanvasImage
    case pipelineFunctionMissing
    case commandBufferFailed

    var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Metal committed canvas backend is unavailable on this device."
        case .failedToCreateCommandQueue:
            return "Failed to create the Metal command queue for the committed canvas backend."
        case let .failedToCreateTexture(width, height):
            return "Failed to create the Metal committed canvas texture: \(width)x\(height)."
        case .failedToCreateCommandBuffer:
            return "Failed to create the Metal command buffer for the committed canvas backend."
        case .failedToCreateRenderEncoder:
            return "Failed to create the Metal render encoder for the committed canvas backend."
        case let .failedToCreateBitmapContext(width, height):
            return "Failed to create the hand drawing bitmap context: \(width)x\(height)."
        case .failedToCreateStrokeImage:
            return "Failed to create the intermediate hand drawing stroke image."
        case .failedToCreateImageBuffer:
            return "Failed to allocate the committed canvas image buffer."
        case .failedToCreateImageDataProvider:
            return "Failed to create the committed canvas image provider."
        case .failedToCreateCanvasImage:
            return "Failed to create the committed canvas image."
        case .pipelineFunctionMissing:
            return "Failed to load the Metal committed canvas shader functions."
        case .commandBufferFailed:
            return "The Metal committed canvas command buffer failed."
        }
    }
}

final class HandDrawingGPUCommittedCanvasBackend: HandDrawingCommittedCanvasBackend {
    static var isSupported: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    private let backgroundColor: HandDrawingColor?
    private let cpuGraphRenderer = HandDrawingCPURenderGraphRenderer()
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let clearPipelineState: MTLRenderPipelineState
    private let compositePipelineState: MTLRenderPipelineState
    private let textureLoader: MTKTextureLoader
    private var paperSize: CGSize
    private var texture: MTLTexture

    init(
        paperSize: CGSize,
        backgroundColor: HandDrawingColor? = nil,
        device: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) throws {
        guard let device else {
            throw HandDrawingGPUCommittedCanvasBackendError.metalUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw HandDrawingGPUCommittedCanvasBackendError.failedToCreateCommandQueue
        }

        self.backgroundColor = backgroundColor
        self.device = device
        self.commandQueue = commandQueue
        clearPipelineState = try Self.makeClearPipelineState(device: device)
        compositePipelineState = try Self.makeCompositePipelineState(
            device: device
        )
        textureLoader = MTKTextureLoader(device: device)
        self.paperSize = paperSize
        texture = try Self.makeTexture(device: device, size: paperSize)
    }

    func render(
        request: HandDrawingCommittedCanvasRenderRequest
    ) throws -> HandDrawingCommittedCanvasRenderOutput {
        let effectiveRequest = try prepareTextureIfNeeded(for: request)
        try renderIntoTexture(request: effectiveRequest)
        return .bitmap(try Self.makeOwnedImage(from: texture))
    }

    private func prepareTextureIfNeeded(
        for request: HandDrawingCommittedCanvasRenderRequest
    ) throws -> HandDrawingCommittedCanvasRenderRequest {
        guard paperSize != request.document.paper.size else {
            return request
        }

        paperSize = request.document.paper.size
        texture = try Self.makeTexture(device: device, size: paperSize)
        return HandDrawingCommittedCanvasRenderRequest(
            document: request.document,
            dirtyRegion: request.document.paperBounds
        )
    }

    private func renderIntoTexture(
        request: HandDrawingCommittedCanvasRenderRequest
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw HandDrawingGPUCommittedCanvasBackendError.failedToCreateCommandBuffer
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store

        guard
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: descriptor
            )
        else {
            throw HandDrawingGPUCommittedCanvasBackendError.failedToCreateRenderEncoder
        }

        let renderRegion = request.renderRegion
        let renderGraph = HandDrawingRenderGraphBuilder.graph(
            for: request.document,
            renderRegion: renderRegion
        )
        renderEncoder.setScissorRect(
            Self.makeScissorRect(
                for: renderRegion,
                textureWidth: texture.width,
                textureHeight: texture.height
            )
        )

        drawClearQuad(with: renderEncoder)

        for snapshot in renderGraph.renderedStrokeSnapshotsInOrder {
            try drawStrokeTexture(
                snapshot,
                paperTransform: renderGraph.paperTransform,
                canvasSize: request.document.paper.size,
                using: renderEncoder
            )
        }

        renderEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed else {
            throw HandDrawingGPUCommittedCanvasBackendError.commandBufferFailed
        }
    }

    private func drawClearQuad(with renderEncoder: MTLRenderCommandEncoder) {
        var color = Self.premultipliedColorVector(from: backgroundColor)
        renderEncoder.setRenderPipelineState(clearPipelineState)
        renderEncoder.setFragmentBytes(
            &color,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 0
        )
        renderEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
    }

    // Keep stroke pixels canonical on CPU while GPU owns the committed
    // canvas texture lifetime, partial clear, and layer compositing.
    private func drawStrokeTexture(
        _ snapshot: HandDrawingStrokeRenderSnapshot,
        paperTransform: CGAffineTransform,
        canvasSize: CGSize,
        using renderEncoder: MTLRenderCommandEncoder
    ) throws {
        let strokeImage = try cpuGraphRenderer.makeImage(
            for: snapshot,
            paperTransform: paperTransform,
            canvasPixelSize: canvasSize
        )
        let strokeTexture = try textureLoader.newTexture(
            cgImage: strokeImage,
            options: Self.textureLoaderOptions
        )
        renderEncoder.setRenderPipelineState(compositePipelineState)
        renderEncoder.setFragmentTexture(strokeTexture, index: 0)
        renderEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
    }

    private static func premultipliedColorVector(
        from color: HandDrawingColor?
    ) -> SIMD4<Float> {
        guard let color else {
            return .zero
        }
        let alpha = Float(color.alpha)
        return SIMD4<Float>(
            Float(color.red) * alpha,
            Float(color.green) * alpha,
            Float(color.blue) * alpha,
            alpha
        )
    }

    private static func makeScissorRect(
        for renderRegion: CGRect,
        textureWidth: Int,
        textureHeight: Int
    ) -> MTLScissorRect {
        let minX = max(Int(floor(renderRegion.minX)), 0)
        let minY = max(Int(floor(renderRegion.minY)), 0)
        let maxX = min(Int(ceil(renderRegion.maxX)), textureWidth)
        let maxY = min(Int(ceil(renderRegion.maxY)), textureHeight)
        return MTLScissorRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1),
            height: max(maxY - minY, 1)
        )
    }

    private static func makeTexture(
        device: MTLDevice,
        size: CGSize
    ) throws -> MTLTexture {
        let width = max(Int(ceil(size.width)), 1)
        let height = max(Int(ceil(size.height)), 1)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw HandDrawingGPUCommittedCanvasBackendError.failedToCreateTexture(
                width: width,
                height: height
            )
        }
        return texture
    }

    private static func makeClearPipelineState(
        device: MTLDevice
    ) throws -> MTLRenderPipelineState {
        let library = try makeLibrary(device: device)
        guard
            let vertexFunction = library.makeFunction(
                name: "handDrawingCommittedClearVertex"
            ),
            let fragmentFunction = library.makeFunction(
                name: "handDrawingCommittedClearFragment"
            )
        else {
            throw HandDrawingGPUCommittedCanvasBackendError.pipelineFunctionMissing
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = false
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeCompositePipelineState(
        device: MTLDevice
    ) throws -> MTLRenderPipelineState {
        let library = try makeLibrary(device: device)
        guard
            let vertexFunction = library.makeFunction(
                name: "handDrawingCommittedCompositeVertex"
            ),
            let fragmentFunction = library.makeFunction(
                name: "handDrawingCommittedCompositeFragment"
            )
        else {
            throw HandDrawingGPUCommittedCanvasBackendError.pipelineFunctionMissing
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeLibrary(
        device: MTLDevice
    ) throws -> MTLLibrary {
        try device.makeLibrary(source: shaderSource, options: nil)
    }

    private static func makeOwnedImage(
        from texture: MTLTexture
    ) throws -> CGImage {
        let bytesPerRow = texture.width * 4
        let byteCount = bytesPerRow * texture.height
        guard let copiedBuffer = malloc(byteCount) else {
            throw HandDrawingGPUCommittedCanvasBackendError.failedToCreateImageBuffer
        }
        texture.getBytes(
            copiedBuffer,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )

        let releaseData: CGDataProviderReleaseDataCallback = { _, data, _ in
            free(UnsafeMutableRawPointer(mutating: data))
        }
        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: copiedBuffer,
            size: byteCount,
            releaseData: releaseData
        ) else {
            free(copiedBuffer)
            throw HandDrawingGPUCommittedCanvasBackendError
                .failedToCreateImageDataProvider
        }

        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
        guard let image = CGImage(
            width: texture.width,
            height: texture.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw HandDrawingGPUCommittedCanvasBackendError.failedToCreateCanvasImage
        }
        return image
    }

    private static let textureLoaderOptions: [MTKTextureLoader.Option: Any] = [
        .SRGB: false,
        .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
        .textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
    ]

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct TexturedQuadOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex float4 handDrawingCommittedClearVertex(
        uint vertexID [[vertex_id]]
    ) {
        float2 clipQuad[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        return float4(clipQuad[vertexID], 0.0, 1.0);
    }

    vertex TexturedQuadOut handDrawingCommittedCompositeVertex(
        uint vertexID [[vertex_id]]
    ) {
        float2 clipQuad[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        float2 texQuad[4] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(1.0, 0.0)
        };
        TexturedQuadOut out;
        out.position = float4(clipQuad[vertexID], 0.0, 1.0);
        out.texCoord = texQuad[vertexID];
        return out;
    }

    fragment half4 handDrawingCommittedClearFragment(
        constant float4 &color [[buffer(0)]]
    ) {
        return half4(half3(color.rgb), half(color.a));
    }

    fragment half4 handDrawingCommittedCompositeFragment(
        TexturedQuadOut in [[stage_in]],
        texture2d<half> strokeTexture [[texture(0)]]
    ) {
        constexpr sampler textureSampler(
            address::clamp_to_edge,
            filter::nearest
        );
        return strokeTexture.sample(textureSampler, in.texCoord);
    }
    """
}
#endif
