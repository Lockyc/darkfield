import CoreGraphics
import DarkfieldCore
import IOSurface

/// Everything a canvas view draws, shared by every view of the canvas (the output window and the
/// panel preview). Views register and are re-rendered on each change.
@MainActor
final class CanvasModel {
    struct Tile: Equatable {
        let id: CGWindowID
        var surface: IOSurface?
        var canvasFrame: CGRect
    }

    var backgroundImage: CGImage?
    var backgroundSurface: IOSurface?
    var tiles: [Tile] = []
    var placed: [PlacedWindow] = []

    /// The audience pointer, in canvas points; nil when the mouse is over no shared window.
    var pointer: CGPoint?
    /// The system cursor drawn at `pointer`: its image, size and hot spot in screen points, and
    /// the shared window's scale on the canvas. Shown while the audience pointer is on; it never
    /// fades, only the locator halo behind it does.
    var cursor: (image: CGImage, size: CGSize, hotSpot: CGPoint)?
    var cursorScale: CGFloat = 1
    var showCursor = false
    /// The locator halo's opacity.
    var pointerOpacity = 0.0
    var pointerScale = 1.0
    var ripples: [Ripple] = []

    private var views: [Weak] = []
    private struct Weak { weak var view: CanvasLayer? }

    func register(_ view: CanvasLayer) {
        views.removeAll { $0.view == nil }
        views.append(Weak(view: view))
        view.render(self)
    }

    func changed() {
        views.removeAll { $0.view == nil }
        for v in views { v.view?.render(self) }
    }
}
