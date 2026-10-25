# Contributing

- Small Conventional Commits on `main` (`feat:`, `fix:`, `docs:`, `chore:`), with a CHANGELOG.md line for anything user-facing.
- Before pushing: `tools/build.sh`, `tools/check-public.sh`, and test on a real Kindle 4 NT (`tools/doctor.sh` passes).
  For screen changes, attach a photo or `tools/sim show` output.
- Never commit personal or device data: serials, MACs, IPs, Wi-Fi names, keys, backups, or screenshots of Settings > Device Info.
- Tool options, output and exit codes are a contract (`docs/tools.md`). Change them only on purpose, and regenerate with `tools/gen-tools-doc.sh`.
- Device reports are welcome as issues: paste `tools/doctor.sh --markdown`.
- Releasing: add a `## vX.Y.Z` section to CHANGELOG.md, then tag `vX.Y.Z`. The README badges update on their own.
