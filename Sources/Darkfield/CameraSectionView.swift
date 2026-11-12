import AppKit
import AVFoundation
import DarkfieldCore
import SwiftUI

/// The panel's Darkfield Camera section: source, effects, and a preview of what a call receives.
struct CameraSectionView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var camera: CameraController
    @ObservedObject var relay: CameraRelay

    private var settings: Binding<CameraSettings> { $model.settings.camera }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CameraPreview(layer: camera.previewLayer, mirrored: model.settings.camera.mirrorPreview)
                .frame(width: 320, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Toggle("Preview", isOn: $camera.demand.preview)
                    .disabled(model.settings.camera.preferred.isEmpty)
                    .help(model.settings.camera.preferred.isEmpty ? "Choose a camera first" : "")
                Spacer()
                Toggle("Mirror preview", isOn: settings.mirrorPreview)
                    .help("Flips only this preview. The call always sees you unflipped.")
            }
            statusLine
            relayLine
            HStack {
                Text("Camera").font(.caption).foregroundStyle(.secondary)
                Spacer()
                choicePicker(slot: 0, none: camera.cameras.isEmpty ? "No cameras connected" : nil)
                    .disabled(camera.cameras.isEmpty && preferred.isEmpty)
            }
            HStack {
                Text("When it's unplugged").font(.caption).foregroundStyle(.secondary)
                Spacer()
                choicePicker(slot: 1, none: "Show a dark frame")
                    .disabled(preferred.isEmpty)
            }
            HStack {
                Toggle("Blur", isOn: settings.blur).frame(width: 80, alignment: .leading)
                Slider(value: settings.blurStrength, in: 0...1)
                    .disabled(!model.settings.camera.blur)
            }
            HStack {
                Toggle("Framing", isOn: settings.framing).frame(width: 80, alignment: .leading)
                Text("Wide").font(.caption).foregroundStyle(.secondary)
                Slider(value: settings.framingTightness, in: 0...1)
                    .disabled(!model.settings.camera.framing)
                Text("Tight").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if camera.permission == .denied || camera.permission == .restricted {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("darkfield needs Camera permission").font(.caption)
                Spacer()
                Button("Open Settings") { camera.openCameraSettings() }.controlSize(.small)
            }
        } else {
            switch camera.status {
            case .fallback(let missing, let using):
                Text("\(missing) isn't connected — using \(using)")
                    .font(.caption).foregroundStyle(.secondary)
            case .missing(let name):
                Text("\(name) isn't connected — Darkfield Camera is showing a dark frame")
                    .font(.caption).foregroundStyle(.secondary)
            case .noCameraChosen:
                Text("Choose a camera").font(.caption).foregroundStyle(.secondary)
            case .off, .live:
                EmptyView()
            }
        }
    }

    /// Whether video apps can pick Darkfield Camera. Preview works regardless.
    @ViewBuilder private var relayLine: some View {
        switch relay.state {
        case .notInThisBuild:
            Text("This build doesn't include Darkfield Camera. Preview still works.")
                .font(.caption).foregroundStyle(.secondary)
        case .activating:
            Text("Setting up Darkfield Camera…").font(.caption).foregroundStyle(.secondary)
        case .needsApproval:
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Allow Darkfield Camera in System Settings").font(.caption)
                Spacer()
                Button("Open Settings") { relay.openApprovalSettings() }.controlSize(.small)
            }
        case .failed(let message):
            Text("Darkfield Camera couldn't start: \(message)").font(.caption).foregroundStyle(.red)
        case .ready:
            Text("Pick “Darkfield Camera” as the camera in your video app.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var preferred: [CameraInfo] { model.settings.camera.preferred }

    /// A picker for one place in the preference order: the connected cameras, the camera already in
    /// that place while it is unplugged, and `none` (choosing it clears the place) when given.
    private func choicePicker(slot: Int, none: String?) -> some View {
        let current = preferred.indices.contains(slot) ? preferred[slot] : nil
        return Picker("", selection: choice(slot: slot)) {
            if let none { Text(none).tag(String?.none) }
            ForEach(camera.cameras, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            if let current, !camera.cameras.contains(where: { $0.id == current.id }) {
                Text("\(current.name) (not connected)").tag(Optional(current.id))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
    }

    /// Choosing the camera already in the other place swaps the two rather than listing it twice.
    private func choice(slot: Int) -> Binding<String?> {
        Binding(
            get: { preferred.indices.contains(slot) ? preferred[slot].id : nil },
            set: { id in
                var list = Array(preferred.prefix(2))
                if let id {
                    if let j = list.firstIndex(where: { $0.id == id }) {
                        if slot < list.count { list.swapAt(j, slot) }
                    } else if let cam = camera.cameras.first(where: { $0.id == id }) {
                        if slot < list.count { list[slot] = cam } else { list.append(cam) }
                    }
                } else if slot < list.count {
                    list.remove(at: slot)
                }
                model.settings.camera.preferred = list
            })
    }
}

/// Hosts the controller's display layer, which shows the same processed frames a call gets.
struct CameraPreview: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let mirrored: Bool

    func makeNSView(context: Context) -> NSView {
        let view = LayerHost()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        layer.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
    }

    private final class LayerHost: NSView {
        override func layout() {
            super.layout()
            layer?.sublayers?.forEach { $0.frame = bounds }
        }
    }
}
