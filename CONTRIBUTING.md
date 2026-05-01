# Contributing

Display Mini is an early preview focused on brightness, resolution, monitor volume, and display connection controls. Bug fixes, compatibility reports, accessibility improvements, and clear documentation are welcome.

## Before a change

Check existing [issues](https://github.com/albert2704/display-mini/issues). For a feature outside the four core controls, explain the use case in an issue before building a large addition. For a bug, include a small reproduction and what you expected to happen.

## Local workflow

1. Fork the repository, clone your fork, and create a focused branch.
2. Read [Architecture](docs/ARCHITECTURE.md) and [Development](docs/DEVELOPMENT.md).
3. Make the change. Keep hardware-independent logic in DisplayCore when practical.
4. Run `./scripts/test.sh` and `./scripts/build.sh`.
5. Describe relevant physical tests, or explicitly state when no compatible hardware was available.
6. Open a pull request with the problem, final behavior, validation, and any limitations.

## Review expectations

* Keep the last active display guard and recoverable resolution previews intact.
* Do not assume a disconnected screen retains its UUID, ID, or position in a list.
* Do not guess a monitor's identity or claim a hardware write succeeded without evidence.
* Keep blocking monitor communication away from the main actor.
* Preserve accessibility labels and keyboard operation when changing UI controls.
* Add a meaningful regression check for a concrete logic bug when possible.
* Keep changes small enough to review, and document new stored preferences or hardware assumptions.
* Preserve license attribution and record vendored changes.

CI verifies builds and logic, not real screen behavior. Never automate display disconnection on somebody else's workstation without authorization.

## Privacy in contributions

Use synthetic serial numbers, UUIDs, and identifiers in fixtures. Redact real hardware identities, usernames, credentials, and unrelated desktop content from public logs and screenshots. Do not commit `.build`, `dist`, preferences, signing credentials, or downloaded private files.

## License

Contributions are accepted under the repository's MIT license. Keep third party code under its original compatible license and include attribution. Be respectful, give reproducible evidence, and discuss the change rather than the person making it.
