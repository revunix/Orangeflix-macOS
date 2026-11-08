import AppKit
import Libmpv
import OpenGL.GL3
import SwiftUI

/// The picture of mpv. The view only draws; clicks and the pointer go to
/// the controls of SwiftUI above it.
///
/// SwiftUI only places a slot. The picture itself is one view per player
/// that moves into the slot shown last. When the layout changes (the
/// chat moves) the new slot takes the picture over at once: the
/// OpenGL layer and the render context of mpv stay as they are. A new render
/// context would make mpv rebuild its video output and wait seconds for the
/// next keyframe of the stream, with a black picture until then.
struct MPVVideoView: NSViewRepresentable {
    let player: MPVPlayer

    func makeNSView(context: Context) -> MPVVideoSlot {
        MPVVideoSlot(player: player)
    }

    func updateNSView(_ slot: MPVVideoSlot, context: Context) {}

    static func dismantleNSView(_ slot: MPVVideoSlot, coordinator: ()) {
        slot.handOver()
    }
}

/// A place for the picture of a player. The newest slot in a window holds it.
final class MPVVideoSlot: NSView {
    private let player: MPVPlayer
    /// The order of the slot among all; higher is newer.
    private let serial: Int

    private static var slots: [WeakSlot] = []
    private static var nextSerial = 0
    /// The one picture of each player.
    private static var videos: [ObjectIdentifier: MPVVideoNSView] = [:]

    init(player: MPVPlayer) {
        self.player = player
        Self.nextSerial += 1
        serial = Self.nextSerial
        super.init(frame: .zero)
        Self.slots.removeAll { $0.slot == nil }
        Self.slots.append(WeakSlot(slot: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The picture of the player, made once.
    private var video: MPVVideoNSView {
        let key = ObjectIdentifier(player)
        if let video = Self.videos[key] { return video }
        let video = MPVVideoNSView(player: player)
        Self.videos[key] = video
        return video
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { adopt() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { handOver() }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Takes the picture into this slot.
    private func adopt() {
        let video = video
        guard video.superview !== self else { return }
        video.frame = bounds
        video.autoresizingMask = [.width, .height]
        addSubview(video)
    }

    /// Gives the picture to the newest other slot of the player that is
    /// still in a window. Without one the picture leaves with this slot and
    /// frees its render context.
    func handOver() {
        guard video.superview === self else { return }
        let next = Self.slots.compactMap(\.slot)
            .filter { $0 !== self && $0.player === player && $0.window != nil }
            .max { $0.serial < $1.serial }
        next?.adopt()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A slot held without keeping it alive.
private struct WeakSlot {
    weak var slot: MPVVideoSlot?
}

/// Hosts the OpenGL layer mpv renders into.
final class MPVVideoNSView: NSView {
    private let player: MPVPlayer
    private let videoLayer: MPVVideoLayer

    init(player: MPVPlayer) {
        self.player = player
        videoLayer = MPVVideoLayer(mpv: player.handle)
        super.init(frame: .zero)
        videoLayer.onReady = { [weak player] in player?.renderContextAttached() }
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { videoLayer }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { detach() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A view that comes back may draw again.
        if window != nil { videoLayer.revive() }
    }

    /// Frees the render context before the view goes away and hands it to
    /// the picture that is still shown, if there is one.
    func detach() {
        let owned = videoLayer.retire()
        if owned, MPVVideoLayer.wakeSuccessor(for: player.handle) == false {
            player.renderContextDetached()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The layer mpv draws every frame into (the OpenGL render API of libmpv).
/// mpv allows one render context per core, so the layer that is shown takes
/// it over from the one that drew before (the player window or the Live
/// screen).
final class MPVVideoLayer: CAOpenGLLayer, @unchecked Sendable {
    /// Called on the main thread once the render context exists.
    var onReady: (@MainActor () -> Void)?

    private let mpv: OpaquePointer
    private var renderContext: OpaquePointer?
    private var glContext: CGLContextObj?
    /// Each mpv core has its own render context; a preview must not take
    /// the context away from the main player.
    nonisolated(unsafe) private static var owners: [OpaquePointer: WeakLayer] = [:]
    /// Every layer that may show the picture, oldest first. When the screen
    /// changes its layout (the chat), SwiftUI builds the new
    /// picture while the old one is still fading out. The newest one wins:
    /// an older layer must not take the render context back, or the new
    /// picture stays black once the old one is gone.
    nonisolated(unsafe) private static var layers: [WeakLayer] = []
    nonisolated(unsafe) private static var nextSerial = 0
    /// The order of the layer among all; higher is newer.
    private let serial: Int
    /// True once the view of the layer left its window.
    private var isRetired = false

    init(mpv: OpaquePointer) {
        self.mpv = mpv
        Self.nextSerial += 1
        serial = Self.nextSerial
        super.init()
        Self.layers.removeAll { $0.layer == nil }
        Self.layers.append(WeakLayer(layer: self))
        isAsynchronous = false
        // The header dropped this property; the layer still has it. The
        // picture is presented in the same transaction that moves the
        // layer, so it stays with the page instead of lagging a frame.
        setValue(true, forKey: "presentsWithTransaction")
        needsDisplayOnBoundsChange = true
        backgroundColor = NSColor.black.cgColor
    }

    override init(layer: Any) {
        mpv = (layer as! MPVVideoLayer).mpv
        serial = (layer as! MPVVideoLayer).serial
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            kCGLPFAColorSize, CGLPixelFormatAttribute(32),
            CGLPixelFormatAttribute(0),
        ]
        var format: CGLPixelFormatObj?
        var count: GLint = 0
        if CGLChoosePixelFormat(attributes, &format, &count) == kCGLNoError, let format {
            return format
        }
        return super.copyCGLPixelFormat(forDisplayMask: mask)
    }

    override func copyCGLContext(forPixelFormat format: CGLPixelFormatObj) -> CGLContextObj {
        let context = super.copyCGLContext(forPixelFormat: format)
        var swapInterval: GLint = 1
        CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval)
        glContext = context
        CGLSetCurrentContext(context)
        createRenderContext()
        return context
    }

    private func createRenderContext() {
        guard renderContext == nil else { return }
        if let previous = Self.owners[mpv]?.layer, previous !== self {
            _ = previous.tearDown()
            if let glContext { CGLSetCurrentContext(glContext) }
        }
        var initParameters = mpv_opengl_init_params(get_proc_address: mpvGLProcAddress, get_proc_address_ctx: nil)
        let apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)
        defer { free(apiType) }
        var created: OpaquePointer?
        let status = withUnsafeMutablePointer(to: &initParameters) { initPointer in
            var parameters = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
                mpv_render_param(),
            ]
            return mpv_render_context_create(&created, mpv, &parameters)
        }
        guard status >= 0, let created else {
            NSLog("mpv_render_context_create: %@", String(cString: mpv_error_string(status)))
            return
        }
        renderContext = created
        Self.owners[mpv] = WeakLayer(layer: self)
        mpv_render_context_set_update_callback(created, mpvRenderUpdate, Unmanaged.passUnretained(self).toOpaque())
        let reference = LayerReference(layer: self)
        DispatchQueue.main.async {
            let layer = reference.layer
            guard !layer.isRetired, layer.renderContext != nil,
                  Self.owners[layer.mpv]?.layer === layer else { return }
            layer.onReady?()
        }
    }

    override func canDraw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                          forLayerTime time: CFTimeInterval, displayTime: UnsafePointer<CVTimeStamp>?) -> Bool {
        // A layer that lost the render context to another view takes it back
        // as soon as it is shown again.
        if renderContext == nil, glContext != nil, !isRetired, Self.newest(for: mpv) === self {
            CGLSetCurrentContext(context)
            createRenderContext()
        }
        return renderContext != nil
    }

    override func draw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                       forLayerTime time: CFTimeInterval, displayTime: UnsafePointer<CVTimeStamp>?) {
        guard let renderContext else { return }
        var framebuffer: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &framebuffer)
        var viewport: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        var target = mpv_opengl_fbo(fbo: Int32(framebuffer), w: Int32(viewport[2]), h: Int32(viewport[3]), internal_format: 0)
        var flip: CInt = 1
        withUnsafeMutablePointer(to: &target) { targetPointer in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                var parameters = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(targetPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param(),
                ]
                _ = mpv_render_context_render(renderContext, &parameters)
            }
        }
        // The superclass flushes when the scroll transaction commits, so
        // the frame stays with the page.
        super.draw(inCGLContext: context, pixelFormat: pixelFormat, forLayerTime: time, displayTime: displayTime)
    }

    /// The newest layer whose view is still shown.
    private static func newest(for mpv: OpaquePointer) -> MPVVideoLayer? {
        layers.removeAll { $0.layer == nil }
        return layers.compactMap(\.layer).filter { !$0.isRetired && $0.mpv == mpv }.max { $0.serial < $1.serial }
    }

    /// Asks the picture still shown to take the render context; false when
    /// there is none.
    @discardableResult
    static func wakeSuccessor(for mpv: OpaquePointer) -> Bool {
        guard let next = newest(for: mpv) else { return false }
        next.setNeedsDisplay()
        return true
    }

    /// The view left its window: the layer gives up the render context and
    /// no longer asks for it. True when it held it.
    func retire() -> Bool {
        isRetired = true
        return tearDown()
    }

    /// The view is shown again and may take the render context.
    func revive() {
        guard isRetired else { return }
        isRetired = false
        setNeedsDisplay()
    }

    /// Frees the render context; false when there was none.
    func tearDown() -> Bool {
        guard let renderContext else { return false }
        if let glContext { CGLSetCurrentContext(glContext) }
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
        if Self.owners[mpv]?.layer === self { Self.owners.removeValue(forKey: mpv) }
        CGLSetCurrentContext(nil)
        return true
    }
}

/// mpv asks for a new frame; the layer draws on the next pass.
private func mpvRenderUpdate(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let reference = LayerReference(layer: Unmanaged<MPVVideoLayer>.fromOpaque(context).takeUnretainedValue())
    DispatchQueue.main.async { reference.layer.setNeedsDisplay() }
}

/// A layer held without keeping it alive.
private struct WeakLayer {
    weak var layer: MPVVideoLayer?
}

/// Carries the layer to the main thread; CALayer may be touched from there.
private struct LayerReference: @unchecked Sendable {
    let layer: MPVVideoLayer
}

/// Resolves the OpenGL functions for mpv.
private func mpvGLProcAddress(_ context: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name,
          let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString),
          let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
    else { return nil }
    return CFBundleGetFunctionPointerForName(bundle, symbol)
}
