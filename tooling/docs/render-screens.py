#!/usr/bin/env python3
"""Render production SwiftUI views with isolated sample data, never live displays."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
build = root / '.build/docs'
build.mkdir(parents=True, exist_ok=True)
source = root / 'Sources/DisplayMini'
stubs = (root / 'Tests/DisplayStoreTests/StoreTests.swift').read_text().split('@main struct StoreTests')[0]
files = ['DisplayStore.swift', 'ShortcutController.swift', 'ShortcutPreferences.swift',
         'ShortcutRecorder.swift', 'CompactSlider.swift', 'PanelView.swift', 'PresetsView.swift', 'ShortcutsView.swift']
swift = '\n'.join([stubs] + [(source / name).read_text() for name in files])
# Replace the hardware mode model only in this temporary documentation executable.
start = swift.index('struct DisplayMode: Identifiable {')
end = swift.index('@MainActor final class DisplayDevice', start)
swift = swift[:start] + '''struct DisplayMode: Identifiable {
    let id: Int32; let width: Int; let height: Int
    init(id: Int32, width: Int, height: Int) { self.id = id; self.width = width; self.height = height }
    init(native: CGDisplayMode) { fatalError("Documentation cannot discover display modes") }
    var native: CGDisplayMode { fatalError("Documentation cannot change display modes") }
    var descriptor: ModeDescriptor { .init(id: id, width: width, height: height, pixelWidth: width * 2, refresh: 60) }
    var size: String { "\\(width) × \\(height)" }
    var detail: String { "HiDPI · 60 Hz" }
}
''' + swift[end:]
swift = swift.replace('UserDefaults.standard', 'DocumentationDefaults.shared')
# An offscreen window has no desktop behind its material. Use the same opaque
# system surface for documentation, so footer text cannot show through it.
swift = swift.replace('.background(.ultraThinMaterial)', '.background(Color(nsColor: .windowBackgroundColor))')
swift += '\n' + (root / 'tooling/docs/RenderDocumentation.swift').read_text()
(build / 'DocumentationViews.swift').write_text(swift)
subprocess.run(['bash', str(root / 'tooling/docs/render-screens.sh')], cwd=root, check=True)
