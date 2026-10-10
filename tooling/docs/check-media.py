#!/usr/bin/env python3
"""Check the media shipped with the README and guide. Requires ffprobe."""
from pathlib import Path
import json
import re
import struct
import subprocess

root = Path(__file__).resolve().parents[2]
for name in ['README.md', 'docs/USER_GUIDE.md', 'docs/DEVELOPMENT.md', 'docs/media/README.md']:
    document = root / name
    links = re.findall(r'(?:src|href)="([^"]+)"|\]\(([^)]+)\)', document.read_text())
    for alternatives in links:
        target = next(value for value in alternatives if value).split('#')[0]
        if not target or re.match(r'\w+://', target):
            continue
        assert (document.parent / target).exists(), f'{name}: missing {target}'

expected = {'panel': (600, 824), 'presets': (760, 880), 'diagnostics': (680, 1180),
            'shortcuts': (760, 1040), 'shortcut-editor': (760, 1040),
            'shortcut-listening': (760, 1040), 'shortcut-recorded': (760, 1040)}
for name, dimensions in expected.items():
    data = (root / f'docs/media/{name}.png').read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', name
    assert struct.unpack('>II', data[16:24]) == dimensions, name
    assert len(data) > 10_000, f'{name}: suspiciously empty image'

video = root / 'docs/media/walkthrough.mp4'
info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_format',
    '-show_streams', '-of', 'json', str(video)]))
stream = next(s for s in info['streams'] if s['codec_type'] == 'video')
assert stream['codec_name'] == 'h264'
assert (stream['width'], stream['height']) == (1280, 720)
assert abs(float(info['format']['duration']) - 24) < 0.1
gif = (root / 'docs/media/walkthrough.gif').read_bytes()
assert gif[:6] in (b'GIF87a', b'GIF89a')
assert struct.unpack('<HH', gif[6:10]) == (800, 450)
for item in (root / 'docs/media').iterdir():
    assert item.stat().st_size < 10 * 1024 * 1024, f'{item.name}: exceeds documentation size budget'
print('Documentation links, seven PNGs, GIF dimensions, MP4 codec/duration and file sizes pass.')
