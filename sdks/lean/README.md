# Lean 4 SDK for Workshop

This SDK provides the Lean 4 theorem prover for the auto-wp `lean` skill:
elan with the toolchain `leanprover/lean4:v4.35.0` preinstalled, Lake,
ripgrep for lemma search and the lean-lsp-mcp server for interactive proof
inspection. elan's home, with its toolchains, and Mathlib's cache are
persisted on the host across workshop updates. Mathlib itself is not
bundled.

---

## Reference workshop

A minimal workshop:

```yaml
# workshop.yaml
name: lean
base: ubuntu@24.04  # or ubuntu@26.04
sdks:
  - name: lean
    channel: latest/edge  # where CI uploads (spec section 8)

actions:
  build: lake build "$@"
  check: lake env lean "$@"
```

This demonstrates building a Lake project and checking single Lean files
with the pinned toolchain.

---

## Using the SDK

### Prerequisites, project layout

1. No prerequisite SDKs are required.
2. Put a Lake project (with `lakefile.toml` or `lakefile.lean`, and a
   `lean-toolchain` file) in the project directory:

   ```bash
   lake new myproject   # or clone an existing one
   ```

3. On the first launch, the SDK copies elan and the toolchain into
   `~/.elan`. It does not do it again afterwards: from then on `~/.elan`
   belongs to the user, and toolchains that projects select through their
   `lean-toolchain` file are added to it and kept across workshop updates.

### Build and check proofs

Once the workshop is ready:

```bash
workshop shell
cd /project/myproject
lake build
lake env lean MyProject/Basic.lean
```

Build outputs go to the project's `.lake/` directory. A proof is complete
when the build has no error and no `declaration uses 'sorry'` warning, and
`#print axioms` lists no axiom beyond `propext`, `Classical.choice` and
`Quot.sound`.

### Inspect proofs with lean-lsp-mcp

`lean-lsp-mcp` is on the `PATH`. To add it to Claude Code inside the
workshop:

```bash
workshop shell
claude mcp add lean-lsp -- lean-lsp-mcp
```

Its `lean_local_search` tool uses the bundled ripgrep. Run `lake build` once
before the first session, so the server starts on built imports.

### Use Mathlib

A project that requires Mathlib downloads Mathlib's prebuilt files once with
`lake exe cache get`; the cache in `~/.cache/mathlib` is kept across
workshop updates. The Mathlib version must match the toolchain (tag
`v4.35.0`).

---

## Plugs (resources this SDK consumes)

### `elan`

- Interface: `mount`
- Workshop target: `/home/workshop/.elan`
- Purpose: Persists elan, its settings and the installed Lean toolchains
  between workshop updates.

### `mathlib-cache`

- Interface: `mount`
- Workshop target: `/home/workshop/.cache/mathlib`
- Purpose: Persists Mathlib's downloaded build cache between workshop
  updates.

## Slots (resources this SDK provides)

This SDK doesn't define any slots.

---

## Documentation and guidance

- [Lean documentation](https://lean-lang.org/documentation/)
- [Lake](https://github.com/leanprover/lean4/tree/master/src/lake)
- [elan](https://github.com/leanprover/elan)
- [lean-lsp-mcp](https://github.com/oOo0oOo/lean-lsp-mcp)
- [Workshop documentation](https://ubuntu.com/workshop/docs/)

---

## Community and support

- Lean community: [Lean Zulip](https://leanprover.zulipchat.com/)
- Workshop forum: [Discourse](https://discourse.ubuntu.com/)
- Please review our
  [Code of Conduct](https://ubuntu.com/community/ethos/code-of-conduct) before
  participating.

---

## Contributions

All contributions, including code, documentation updates, and issue reports,
are welcome! Open issues or pull requests on the auto-wp repository.

To test changes, run `sdkcraft test` in this directory: it packs the SDK for
both bases and runs the spread tests in `tests/` (launch, a verified Lake
project, rejected proofs, lean-lsp-mcp and persistence).

---

## License and copyright

Copyright 2026 Fabrice Derepas.

This SDK is distributed under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

Shipped components: Lean 4 and Lake under the Apache License 2.0, elan under
the Apache License 2.0 or the MIT License, ripgrep under the MIT License or
the Unlicense, and lean-lsp-mcp under the MIT License.
