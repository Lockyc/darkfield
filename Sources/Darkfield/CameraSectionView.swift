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
                    .disabled(model.settings.camera.deviceID == nil)
                    .help(model.settings.camera.deviceID == nil ? "Choose a camera first" : "")
                Spacer()
                Toggle("Mirror preview", isOn: settings.mirrorPreview)
                    .help("Flips only this preview. The call always sees you unflipped.")
            }
            statusLine
            relayLine
            HStack {
                Text("Camera").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: source) {
                    if camera.cameras.isEmpty && model.settings.camera.deviceID == nil {
                        Text("No cameras connected").tag(String?.none)
                    }
                    ForEach(camera.cameras, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    if let id = model.settings.camera.deviceID, !camera.cameras.contains(where: { $0.id == id }) {
                        Text("\(model.settings.camera.deviceName ?? "Chosen camera") (not connected)").tag(Optional(id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                .disabled(camera.cameras.isEmpty && model.settings.camera.deviceID == nil)
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

    private var source: Binding<String?> {
        Binding(
            get: { model.settings.camera.deviceID },
            set: { id in
                model.settings.camera.deviceID = id
                model.settings.camera.deviceName = camera.cameras.first { $0.id == id }?.name ?? model.settings.camera.deviceName
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
