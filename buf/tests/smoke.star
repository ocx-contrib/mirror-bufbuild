# buf/tests/smoke.star — hermetic, offline, and asserting the CONTRACT.
#
# This package ships THREE executables and that is the whole reason it takes
# upstream's FHS tarball instead of the raw `buf` binary (see mirror.yml). A
# smoke test that only ran `buf --version` would green on a bundle missing both
# protoc plugins, so the checks below drive `buf` itself AND make `buf` resolve
# each plugin THROUGH PATH and run it — which is the only way the extra two
# binaries are reachable at all.
#
# Everything is hermetic: a `buf.yaml` module, two `.proto` files and a
# serialized image, all written by this script into scratch. No BSR call, no
# remote plugin, no dependency to resolve — container legs may have no egress.
#
# Nothing here asserts help text, a banner or a vendor string. The contracts
# asserted are: the version SHAPE, buf's documented lint/breaking exit code
# 100, its own machine-readable `--error-format json` records, and the stable
# rule ids inside them.
#
# `env=` is an OVERLAY on the composed bundle env, not a replacement, so PATH
# still resolves the bundled binaries. HOME is pointed at scratch because buf
# creates a cache directory under it on start-up and dies (`Failure: mkdir …:
# no such file or directory`, measured) when HOME names a path it cannot
# create — the shape an unset/foreign HOME takes in a bare container image.
BUF = "buf.exe" if ocx.target_platform.os == ocx.os.Windows else "buf"
ENV = {"HOME": ocx.scratch_root, "USERPROFILE": ocx.scratch_root}

# ── Tier 1 + 2: liveness and version SHAPE ─────────────────────────────────
# Not the exact version and not the word "buf" — a rebrand or a version bump
# must not red the mirror. Digits in the documented shape are the contract.
r_version = ocx.run(BUF, "--version", env=ENV)
expect.ok(r_version)
expect.matches(r_version.stdout, r"\d+\.\d+\.\d+")

# ── The hermetic module ────────────────────────────────────────────────────
# The directory MUST mirror the proto package or buf's own
# PACKAGE_DIRECTORY_MATCH rule fires and the "clean" baseline below would be
# dirty — that is upstream's rule doing its job, not a test bug.
ocx.mkdir("ocx/smoke/v1")
ocx.write_file("buf.yaml", """version: v2
modules:
  - path: .
lint:
  use:
    - STANDARD
""")
ocx.write_file("ocx/smoke/v1/pet.proto", """syntax = "proto3";
package ocx.smoke.v1;
message Pet {
  string name = 1;
}
""")

# ── Tier 3a: buf lints and builds a real module ────────────────────────────
# A clean module must produce NO findings. Asserting empty stdout (not merely
# exit 0) is what makes the violating run below meaningful: a `buf lint` that
# printed nothing either way would pass both halves.
r_clean = ocx.run(BUF, "lint", "--error-format", "json", env=ENV)
expect.ok(r_clean)
expect.eq(r_clean.stdout, "")

# Serialize the module to an image — the input the breaking checks compare
# against. buf writes this file itself; nothing here hand-rolls protobuf bytes.
r_build = ocx.run(BUF, "build", "-o", "image.binpb", env=ENV)
expect.ok(r_build)
expect.true(ocx.exists("image.binpb"))

# ── Tier 3b: the violating half — exit code 100 and the rule ids ───────────
# buf reserves exit 100 for "the check ran and found violations" and keeps 1
# for "the tool failed", so tolerating a RANGE of non-zero codes here would
# stop distinguishing a working linter from a broken binary. One JSON record
# per line, counted rather than pattern-scraped, so an extra or missing finding
# reds instead of being absorbed by a substring match.
ocx.write_file("ocx/smoke/v1/bad.proto", """syntax = "proto3";
package ocx.smoke.v1;
message bad_name {
  string Field_One = 1;
}
""")
r_bad = ocx.run(BUF, "lint", "--path", "ocx/smoke/v1/bad.proto",
                "--error-format", "json", env=ENV)
expect.eq(r_bad.exit_code, 100)
expect.eq(r_bad.stdout.count("\"type\":"), 2)
expect.contains(r_bad.stdout, "\"type\":\"MESSAGE_PASCAL_CASE\"")
expect.contains(r_bad.stdout, "\"type\":\"FIELD_LOWER_SNAKE_CASE\"")

# ── Tier 3c: protoc-gen-buf-lint, resolved through PATH and executed ───────
# `local:` makes buf look the plugin up on PATH exactly as protoc would, so
# these two runs fail unless `${installPath}/bin/protoc-gen-buf-lint` exists,
# is executable, and answers a CodeGeneratorRequest. The clean run proves it
# can succeed; the violating run proves the findings came from the PLUGIN
# (buf prefixes them with the plugin's own name) rather than from buf's
# built-in linter, which is a separate code path already covered above.
ocx.write_file("gen-lint.yaml", """version: v2
plugins:
  - local: protoc-gen-buf-lint
    out: gen
""")
r_plug_ok = ocx.run(BUF, "generate", "--template", "gen-lint.yaml",
                    "--path", "ocx/smoke/v1/pet.proto", env=ENV)
expect.ok(r_plug_ok)

r_plug_bad = ocx.run(BUF, "generate", "--template", "gen-lint.yaml",
                     "--path", "ocx/smoke/v1/bad.proto", env=ENV)
expect.eq(r_plug_bad.exit_code, 1)
expect.contains(r_plug_bad.stderr, "plugin protoc-gen-buf-lint:")
expect.contains(r_plug_bad.stderr, "should be PascalCase")

# ── Tier 3d: protoc-gen-buf-breaking, likewise ────────────────────────────
# Retype field 1 — a wire-incompatible change — then hold both the built-in
# `buf breaking` and the plugin against the image built before the edit.
ocx.write_file("ocx/smoke/v1/pet.proto", """syntax = "proto3";
package ocx.smoke.v1;
message Pet {
  int32 name = 1;
}
""")
r_breaking = ocx.run(BUF, "breaking", "--against", "image.binpb",
                     "--path", "ocx/smoke/v1/pet.proto",
                     "--error-format", "json", env=ENV)
expect.eq(r_breaking.exit_code, 100)
expect.eq(r_breaking.stdout.count("\"type\":"), 1)
expect.contains(r_breaking.stdout, "\"type\":\"FIELD_SAME_TYPE\"")

ocx.write_file("gen-breaking.yaml", """version: v2
plugins:
  - local: protoc-gen-buf-breaking
    out: gen
    opt: '{"against_input":"image.binpb"}'
""")
r_plug_break = ocx.run(BUF, "generate", "--template", "gen-breaking.yaml",
                       "--path", "ocx/smoke/v1/pet.proto", env=ENV)
expect.eq(r_plug_break.exit_code, 1)
expect.contains(r_plug_break.stderr, "plugin protoc-gen-buf-breaking:")
expect.contains(r_plug_break.stderr, "changed type from \"string\" to \"int32\"")

# ── NEGATIVE CONTROL for the two plugin checks above ──────────────────────
# Both plugin runs above are exit-1-with-a-message assertions, and a message
# is only evidence if the ABSENT case produces a different one. Name a plugin
# that is not on PATH and buf reports Go's exec lookup failure instead of any
# plugin output — so a bundle shipping only `buf` could never have produced
# the stderr the two checks above require.
ocx.write_file("gen-missing.yaml", """version: v2
plugins:
  - local: protoc-gen-buf-not-shipped
    out: gen
""")
r_missing = ocx.run(BUF, "generate", "--template", "gen-missing.yaml",
                    "--path", "ocx/smoke/v1/pet.proto", env=ENV)
expect.eq(r_missing.exit_code, 1)
expect.contains(r_missing.stderr, "executable file not found")
