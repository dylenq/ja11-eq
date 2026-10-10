<!-- GSD:project-start source:PROJECT.md -->

## Project

**JA11 EQ**

JA11 EQ is a native macOS app that programs the built-in 5-band parametric equalizer of a FiiO JadeAudio JA11 USB DAC dongle. It talks to the dongle over USB HID, so the EQ is stored in the DAC itself and follows it to a phone or another computer. It is a personal tool for the owner of the dongle, replacing FiiO's own configuration app on the Mac.

**Core Value:** Edit an EQ curve on the Mac, press Apply, and the JA11 plays with that curve — reliably, and without ever damaging the dongle's factory presets.

### Constraints

- **Tech stack**: Swift package, SwiftUI + IOKit HID + CoreAudio, macOS 14+, zero third-party dependencies — the Xcode toolchain is already installed and nothing else is needed
- **Hardware**: 5 bands, ±12 dB, Q 0.1–10, peak/shelf filters only — fixed by the dongle's firmware
- **Safety**: writes target slot 3 (USER1) only, and every value is clamped to device limits before encoding — the dongle is the user's only unit and factory presets cannot be re-created
- **Safety**: record the dongle's existing USER1 contents before the first write — so the original state can be restored
- **Compatibility**: open the HID device non-exclusively — the dongle's volume and play buttons must keep working
- **Distribution**: unsandboxed, ad-hoc signed local build — personal use only

<!-- GSD:project-end -->

<!-- GSD:stack-start source:STACK.md -->

## Technology Stack

Technology stack not yet documented. Will populate after codebase mapping or first phase.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
