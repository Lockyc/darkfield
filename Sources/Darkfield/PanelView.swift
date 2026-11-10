import AppKit
import DarkfieldCore
import SwiftUI

/// The status-item panel: everything used while presenting, top to bottom, in a fixed layout.
struct PanelView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.canCapture {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("darkfield needs Screen Recording permission").font(.callout)
                    Spacer()
                    Button("Open Settings") { model.openScreenRecordingSettings() }
                }
            }
            if let notice = model.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }

            CanvasPreview(canvas: model.canvas)
                .frame(width: 320, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Show Preview Window") { model.showPreview?() }
                    .controlSize(.small)
                    .disabled(model.previewShown || model.settings.output != .meeting)
                    .help(model.settings.output != .meeting ? "Presenting to the projector"
                          : model.previewShown ? "The preview window is open" : "")
            }

            windowList

            LabeledContent("Present to") {
                HStack {
                    Picker("", selection: outputKind) {
                        Text("Meeting").tag(0)
                        Text("Projector").tag(1).disabled(model.projectorDisplays.isEmpty)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Picker("", selection: projectorDisplay) {
                        ForEach(model.projectorDisplays) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .disabled(model.projectorDisplays.isEmpty || outputKind.wrappedValue == 0)
                }
            }
            if model.projectorDisplays.isEmpty {
                Text("Connect a second display to present to a projector").font(.caption).foregroundStyle(.secondary)
            }

            LabeledContent("Margin") {
                Slider(value: $model.settings.margin, in: 0...120, step: 4)
            }
            Toggle("Audience pointer", isOn: $model.settings.pointerEnabled)

            HStack {
                Button("Settings…", action: openSettings)
                Button("Check for Updates…") { model.updater?.checkForUpdates(nil) }
                    .disabled(model.updater == nil)
                    .help(model.updater == nil ? "Updates work in the installed app" : "")
                Spacer()
                Button("Quit darkfield") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 348)
    }

    private var windowList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Shared windows").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add Window…") {
                    Task {
                        let menu = await model.addWindowMenu()
                        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                    }
                }
                .controlSize(.small)
            }
            if model.windowHotKeyRefused, let key = model.settings.windowHotKey {
                Text("\(key.display) isn't available — another app uses it. Change it in Settings.")
                    .font(.caption).foregroundStyle(.red)
            }
            List {
                if model.rows.isEmpty {
                    Text("Press \(model.settings.windowHotKey?.display ?? "the window hotkey") in a window to share it")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.rows) { row in
                    HStack {
                        if let icon = row.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        VStack(alignment: .leading) {
                            Text(row.title.isEmpty ? row.appName : row.title).lineLimit(1)
                            if let reason = row.availability?.reason {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            } else if row.availability == nil {
                                Text("Starting…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .opacity(row.availability == .available ? 1 : 0.5)
                        Spacer()
                        Button { model.captures.remove(row.id) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .help("Stop sharing")
                    }
                }
            }
            .frame(height: 120)
        }
    }

    private var outputKind: Binding<Int> {
        Binding(
            get: { if case .projector = model.settings.output { 1 } else { 0 } },
            set: { kind in
                if kind == 1, let first = model.projectorDisplays.first { model.settings.output = .projector(first.id) }
                else { model.settings.output = .meeting }
            })
    }

    private var projectorDisplay: Binding<CGDirectDisplayID?> {
        Binding(
            get: { if case .projector(let id) = model.settings.output { id } else { model.projectorDisplays.first?.id } },
            set: { if let id = $0, case .projector = model.settings.output { model.settings.output = .projector(id) } })
    }
}

/// A live, scaled-down view of the canvas, rendering the same model as the output.
struct CanvasPreview: NSViewRepresentable {
    let canvas: CanvasModel
    func makeNSView(context: Context) -> CanvasView { CanvasView(model: canvas) }
    func updateNSView(_ view: CanvasView, context: Context) {}
}
