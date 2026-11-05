# auto-wp

`auto-wp.py` creates a project directory pre-loaded with the Claude Code
skills and slash commands for a long-running formal-verification campaign:
C with [Frama-C/WP](https://frama-c.com), or Rust with
[Creusot](https://github.com/creusot-rs/creusot).

```
./auto-wp.py [--c|--rust] <directory-name>
```

The generated directory is stand-alone. It has its own `README.md` with the
quick start: clone the code to analyse next to the configuration, then run
Claude Code in a container (for example `/time-loop grub 72` for a 72-hour
campaign on GRUB). Python 3.10 or later, standard library only.

## Repository layout

| Path | Contents |
|---|---|
| `auto-wp.py` | The generator |
| `templates/` | What it copies: `common/` (all projects), `c/`, `rust/` |
| `sdks/` | [Workshop](https://ubuntu.com/workshop/docs/) SDKs with the toolchains: `frama-c-sdk`, `creusot`, `rocq`, `lean` ([`sdks/README.md`](sdks/README.md)) |
| `tests/` | Program, template, container and SDK tests ([`tests/README.md`](tests/README.md)) |
| `spec/` | The specifications |

## Specifications

- [`spec/auto-wp.md`](spec/auto-wp.md): `auto-wp.py`, the generated project, and its README
- [`spec/tests.md`](spec/tests.md): the test plan
- [`spec/workshop-autowp-c-base-spec.md`](spec/workshop-autowp-c-base-spec.md),
  [`spec/workshop-autowp-rust-base-spec.md`](spec/workshop-autowp-rust-base-spec.md): the Workshop SDKs
- [`spec/gzip-test.md`](spec/gzip-test.md): the GNU gzip 1.9 campaign test
- [`spec/fips-skill-spec.md`](spec/fips-skill-spec.md): the `fips-sl` skill (FIPS 140-3), draft
- [`spec/`](spec/): all of them, with review reports

## Tests

```
make test        # program and template tests (seconds)
make help        # every target: container tests, campaigns, SDK builds
```

## Licence

GPL-3.0 ([`LICENSE`](LICENSE)). The SDKs bundle third-party tools under
their own licences; Alt-Ergo, in `frama-c-sdk` and `creusot`, is for
non-commercial use only ([`sdks/README.md`](sdks/README.md)).
