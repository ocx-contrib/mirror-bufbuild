# mirror-bufbuild

OCX mirrors for [Buf](https://buf.build) tooling. One repository, one spec
directory per package.

| Package | Spec | Publishes to | Announced as |
|---|---|---|---|
| Buf | [`buf/mirror.yml`](buf/mirror.yml) | `ghcr.io/ocx-contrib/bufbuild/buf` | [`ocx.sh/bufbuild/buf`](https://index.ocx.sh/bufbuild/buf) |

Each upstream release is discovered, re-bundled, smoke-tested per
`(version, platform)` and only then pushed with cascade tags, after which the
result is announced into the OCX index.

The bundle is upstream's own FHS archive, not the standalone `buf` binary: it
carries `bin/buf` **plus** `bin/protoc-gen-buf-breaking` and
`bin/protoc-gen-buf-lint`, the shell completions and the man pages. The `buf`
executable inside it is byte-identical to the raw `buf-<OS>-<ARCH>` asset — the
archive is a strict superset, so nothing is traded away for the extra content.

## Layout

`mirror-base.yml` at the root holds the repo-wide policy every spec inherits
via `extends:`. `extends:` is a **shallow** merge — a spec that sets a
top-level key replaces that block whole. `platforms:` deliberately stays in the
spec, because the container matrix is downstream of the per-package libc
measurement recorded there.

## Editing

| File | Edit | Regenerate after |
|------|------|------------------|
| `mirror-base.yml`, `buf/mirror.yml` | hand | `ocx-mirror package pipeline generate ci --spec buf/mirror.yml` |
| `buf/tests/smoke.star` | hand | — |
| `buf/metadata.json`, `buf/CATALOG.md`, `logo.*` | hand | — |
| `.github/workflows/*.yml` | **generated — never hand-edit** | re-run when a spec changes |

`--spec` **appends** rather than replaces, so the regenerate command must name
every spec in the repo — today that is the one above.

The repo root is inferred from the enclosing git repository, so `--repo-root`
is needed only when generating outside a checkout.

CI fails on drift via `ocx-mirror package pipeline generate ci --check`.

## Required secrets

| Secret | Use |
|--------|-----|
| `OCX_ANNOUNCE_TOKEN` | opens the index PR from the `ocx-contrib/index` fork |
| `OCX_MIRROR_DISCORD_HOOK` | notify-stage Discord webhook URL |

(Inherited from the `ocx-contrib` org with visibility ALL. GHCR pushes use the
run's own `GITHUB_TOKEN` — no registry secret needed.)

## License

Apache-2.0 — see [`LICENSE`](LICENSE). Upstream assets are out of
scope; see [`NOTICE.md`](NOTICE.md).
