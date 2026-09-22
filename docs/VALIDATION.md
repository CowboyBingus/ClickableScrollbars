# v2.8 validation

The regression harness reproduces the released bug: ordinary clicks without a visible native owner entered the pixel detector. The old v2.6 source fails the new no-capture contract.

Current checks cover:

- 1,000 gameplay clicks and 1,000 menu-content clicks with no capture, input injection, writes or log IO.
- 20,000 idle and held-button frames without repeated native menu searches.
- Hidden, unsupported, malformed and retired owners; no repeated initialization on an unsupported build.
- Native thumb and track presses, immutable grab offsets, sideways motion, both ends and reversal.
- Focus loss, changed owner/layout, ignored/refused writes, release and callback return tuples.
- Native read-back without screenshot verification, including small sub-row movement.
- Opt-in diagnostics with a write interval; no duplicate input work in render.
- The existing equipment/Career simulator, native-memory suite, platform and archive checks.

These are offline proofs. The native v2.6 implementation was user-verified in-game; that confirmation does not transfer to the new source. The build only marks the exact previously verified source hash as runtime-verified.

For in-game verification, test smooth dragging in equipment and Career, then fire and click repeatedly outside menus. Repeat with Clickable Scrollbars disabled for comparison. Check that drag cancellation and ordinary tab selection still work. Enable diagnostics only when collecting a log.

Build reports, logs and local captures are private outputs, excluded from publication.

The full-registry native regression now requires three reads with no owner and five with a hidden owner, with truncated snapshots refused.
