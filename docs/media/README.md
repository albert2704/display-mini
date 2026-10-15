# Documentation media

These images are native SwiftUI interface examples generated from the production views with isolated sample data. Advanced and its schedule editor show the next update after Display Mini 0.3.0; the existing walkthrough shows the 0.3.0 shortcut workflow. They are not recordings of a user's desktop or proof of hardware support. The walkthrough animates transitions between its UI states, illustrates the recorded keys, and highlights Record Shortcut and Save. These are documentation annotations, with no audio or simulated pointer.

The renderer reuses the hardware substitutes from the store tests, disables monitoring and schedule timers, replaces display modes with sample descriptors, and redirects defaults to a temporary domain that it removes on exit. Sample schedules are disabled and no awake session starts. No real monitor control or personal preferences are used. Opaque system surfaces replace translucent materials because offscreen windows have no desktop backdrop. The production app source is not modified.

| File | Contents |
| --- | --- |
| `panel.png` | Two sample screens and the footer controls. |
| `presets.png` | Work and Evening preset examples. |
| `diagnostics.png` | Sample successful DDC brightness and volume reports. |
| `shortcuts.png` | Default action bindings. |
| `shortcut-editor.png` | Editor before recording. |
| `shortcut-listening.png` | Active recording prompt. |
| `shortcut-recorded.png` | Captured Control+Shift+K, before Save. |
| `display-settings.png` | Custom display name and favorite resolutions in light appearance. |
| `display-settings-dark.png` | The same example in dark appearance. |
| `advanced.png` | Selected brightness participants, timed awake sessions, preset schedules and monitor controls in light appearance. |
| `advanced-dark.png` | The Advanced tab in dark appearance. |
| `schedule-editor.png` | Preset, local time and recurrence in the compact schedule editor. |
| `walkthrough.gif` | Small inline preview for GitHub Markdown. |
| `walkthrough.mp4` | 24 second, 1280×720 H.264 walkthrough. |

## Regenerate

On macOS with Command Line Tools and Python 3:

```sh
python3 tooling/docs/render-screens.py
cd tooling/docs/walkthrough
node build.mjs
npm run check
npm run render -- --fps 24 --output ../../../docs/media/walkthrough.mp4
ffmpeg -y -i ../../../docs/media/walkthrough.mp4 -filter_complex '[0:v]fps=12,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' -loop 0 ../../../docs/media/walkthrough.gif
```

The optional video tooling uses Node, the pinned HyperFrames CLI, and FFmpeg. It is separate from the application build. Inspect every image and each video scene after regeneration; changes to the app's UI may require adjusting the fixture or captions. Run `python3 tooling/docs/check-media.py` to check links, dimensions and media metadata before committing.

All project-authored media uses the repository's MIT license. System controls and symbols retain Apple's visual design.
