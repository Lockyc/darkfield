import CoreGraphics

/// Which parts of a shared window's ring other windows cover. The ring floats above normal windows,
/// so it is cut away wherever a window in front of the shared one overlaps it, to look as if it
/// sat directly above its window.
public enum RingCover {
    /// The rects of `ring` (CG global) covered by windows in front of `shared` in `stack` (every
    /// on-screen window, front to back), skipping `ignoring`. Returned in ring-local points with a
    /// bottom-left origin, y up, as the ring's layer draws.
    public static func covers(ring: CGRect, shared: CGWindowID, stack: [OnScreenWindow],
                              ignoring: Set<CGWindowID> = []) -> [CGRect] {
        guard let index = stack.firstIndex(where: { $0.id == shared }) else { return [] }
        return stack[..<index].compactMap { w in
            guard !ignoring.contains(w.id) else { return nil }
            let cut = w.frame.intersection(ring)
            guard !cut.isNull, !cut.isEmpty else { return nil }
            return CGRect(x: cut.minX - ring.minX, y: ring.maxY - cut.maxY, width: cut.width, height: cut.height)
        }
    }
}
