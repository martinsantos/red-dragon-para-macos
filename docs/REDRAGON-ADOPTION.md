# Engineering handoff to Redragon

**RED DRAGON PARA MACOS** is an independent native macOS configuration application for the S136 kit (K628 keyboard and M693 mouse). We are making the source available free of charge under the repository's MIT license so Redragon can evaluate, adapt, integrate and distribute it as part of official macOS support.

Repository: https://github.com/martinsantos/red-dragon-para-macos

The MIT license grants reuse rights subject to retaining the copyright and license notices. Redragon has not endorsed the project or accepted this handoff. This is a community preview, not a certified production release.

## Implemented and tested

- Interactive physical keyboard and mouse diagrams, including per-key palette preview.
- Native SwiftUI desktop interface, no kernel extension or Windows runtime.
- IOKit HID configuration transport, with non-exclusive device access.
- Current-profile configuration and key/button mapping.
- Keyboard RGB settings and first per-key custom palette.
- Five verified M693 DPI presets and USB polling configuration.
- Automatic local backup before writes, stale-state checks, readback verification and rollback verification.
- Macro memory read/write and binding, with a sequence editor that checks balanced press/release events.

Hardware write/readback/restore tests passed for receiver `320F:50B8` with the K628 in 2.4 GHz mode, and M693 USB `320F:2225`. The configuration app successfully read the K628 after its macOS Input Monitoring permission was refreshed.

## Validation required before official distribution

1. Confirm the recovered protocol and structures against firmware documentation and every supported revision.
2. Confirm physical macro execution and event types. The memory and binding round trips passed, but the F13 physical test was not observed by the monitor.
3. Validate remapped-key output, physical RGB effects, sensor DPI and polling, not only the stored bytes.
4. Test the wireless mouse, Bluetooth and wired keyboard; current tested scope is narrower.
5. Validate disconnects, power loss, rollback and recovery from a saved backup on production units.
6. Supply stable Developer ID signing and notarization for public macOS distribution, and review permission onboarding.
7. Decide the official support, update and firmware compatibility policy.

We invite Redragon's engineering team to use this starting point and complete those checks for official production support. Firmware protocol documentation would help resolve the remaining items.

The repository contains our implementation and documentation. It does not distribute the manufacturer's Windows executable or extracted assets. [Validation notes](VALIDATION.md) describe the static analysis and hardware experiments.
