# Security and privacy

Connection reports use an explicit field allowlist and omit monitor UUIDs, serials, names, registry paths, local paths and raw helper output. Reports are copied only when requested and are never uploaded. The DDC process runner caps output at 64 KiB and bounds both execution and pipe cleanup.

## Reporting a vulnerability

Use [GitHub's private vulnerability report](https://github.com/albert2704/display-mini/security/advisories/new) for security issues. Include the affected version, reproduction, impact, and a minimal example. Do not publish credentials, personal hardware identifiers, or an exploit affecting other people in a public issue.

There is no promised response time or long term support window for this early project. Reports should target the latest preview or main branch; older preview builds are not separately maintained.

## Local data

The app has no accounts, analytics, network requests, cloud storage, or automatic updater. It stores local preferences and recovery records in the `dev.albert.DisplayMini` UserDefaults domain.

Those records include display UUIDs, vendor/model/serial identities, software dimming preferences, owned disconnections, a pending resolution, preset names and per-screen levels, last nonzero monitor volume, and the shortcut enable preference. They support recovery and are not uploaded. Treat exported preferences and detailed monitor diagnostics as identifying information when sharing publicly.

## Process and OS boundaries

DDC commands go to a helper bundled inside the app. The helper path is absolute, and arguments are passed to Process as an array. The app does not invoke a shell to construct monitor commands. Monitor processes have bounded timeouts.

The app uses private DisplayServices, SkyLight, IOAVService, and CoreDisplay interfaces. Those interfaces do not provide a stable compatibility contract. A missing or changed API can prevent control or recovery. Display configuration is a local system effect even though the app runs without an administrator prompt.

## Release integrity

Current archives are ad hoc signed, not Developer ID signed or notarized. Checksums accompany release downloads. A checksum can detect corruption but is not an independent publisher signature. No code signing private keys or notarization credentials are stored in this repository.

Use the documented build process when inspecting the source. Do not disable macOS security features as a workaround for this preview's distribution limitations.
