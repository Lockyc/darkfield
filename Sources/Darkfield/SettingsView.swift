import AppKit
import DarkfieldCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    static let fadeChoices: [TimeInterval?] = [5, 10, 20, 30, nil]

    var body: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Share or unshare window") {
                    HotKeyRecorder(spec: $model.settings.windowHotKey, listeners: $model.listeningRecorders,
                                   refused: model.windowHotKeyRefused)
                }
                LabeledContent("Resize window to fit unscaled") {
                    HotKeyRecorder(spec: $model.settings.fitHotKey, listeners: $model.listeningRecorders,
                                   refused: model.fitHotKeyRefused)
                }
                LabeledContent("Audience pointer on/off") {
                    HotKeyRecorder(spec: $model.settings.pointerHotKey, listeners: $model.listeningRecorders,
                                   refused: model.pointerHotKeyRefused)
                }
            }
            Section("Audience pointer") {
                Picker("Fade when still for", selection: $model.settings.idleFade) {
                    ForEach(Self.fadeChoices, id: \.self) { s in
                        Text(s.map { "\(Int($0)) seconds" } ?? "Never").tag(s)
                    }
                }
            }
            Section("Background") {
                Picker("Wallpaper", selection: wallpaperChoice) {
                    Text("Primary display").tag(WallpaperSource.primary)
                    ForEach(model.displays.filter { $0.id != CGMainDisplayID() }) { d in
                        Text(d.name).tag(WallpaperSource.display(d.id))
                    }
                    if case .image(let url) = model.settings.wallpaper {
                        Text(url.lastPathComponent).tag(WallpaperSource.image(url))
                    }
                }
                Button("Choose image…", action: chooseImage)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Quit darkfield") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        // A grouped Form is a scroll view with no ideal height; without this the window shrinks to
        // its title bar.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 440)
    }

    private var wallpaperChoice: Binding<WallpaperSource> {
        Binding(get: { model.settings.wallpaper }, set: { model.settings.wallpaper = $0 })
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.settings.wallpaper = .image(url) }
    }
}
