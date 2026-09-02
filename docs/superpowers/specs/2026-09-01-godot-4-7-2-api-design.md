# Godot 4.7.2 Custom Fork API Update

## Goal

Update SwiftGodot's checked-in GDExtension API snapshot to the Cafecito Games
custom Godot release `v4.7.2-20260826.1` and require Godot 4.7 for the sample
and test extensions.

## Source of Truth

Generate the API files from the installed custom editor binary at
`/Users/christian/bin/godot`. The binary reports
`4.7.2.stable.cafecito_dc0a505af.ed1daf0bf`, matching the requested published
release. Generated output is authoritative; no API declarations will be
edited manually.

## Changes

- Replace `Sources/ExtensionApi/extension_api.json` using
  `--dump-extension-api-with-docs`.
- Replace `Sources/GDExtension/include/gdextension_interface.h` using
  `--dump-gdextension-interface`.
- Change `compatibility_minimum` from `4.6` to `4.7` in the sample and test
  `.gdextension` manifests.

## Validation

- Assert that the generated JSON header identifies Godot 4.7.2 and a Cafecito
  build.
- Assert that both `.gdextension` manifests require Godot 4.7.
- Build `SwiftGodot` from a clean scratch directory so code generation consumes
  the new API snapshot.
- Run the Swift package test suite.

The existing untracked files in the primary worktree are outside this update
and will remain untouched.
