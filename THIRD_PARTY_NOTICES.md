# Third party notices

Display Mini bundles m1ddc, copyright Istvan Toth (waydabber) and contributors, under the MIT license. The full license is in Vendor/LICENSE and in the app's Resources folder.

Source: https://github.com/waydabber/m1ddc
Downloaded: 2026-10-08, main branch archive. The archive revision is recorded in Vendor/SOURCE.txt. Local fix: i2c.m uses sizeof(maxValue) and sizeof(curValue) for its two 16-bit reads instead of sizeof(2), which incorrectly requested four bytes into a two-byte destination.

Additional local transport fixes: derive packet size from its length byte, preserve zero checksums, prepare repeatable request checksums, wait 50 ms before reading 11 bytes at offset zero, validate reply headers/status/VCP/checksum, and retry reads up to three times. Protocol behavior was cross checked against MonitorControl and ddcutil. No code from those projects is bundled.

The SkyLight connection control signatures were researched using the independently published screen_tune and MacDisplay source. Display Mini implements its own connection and recovery logic.
