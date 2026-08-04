---
title: Buf
description: Protobuf toolchain — lint, detect breaking changes, and build Protocol Buffer schemas
keywords: buf,protobuf,protoc,grpc,lint,breaking-change,schema,api
---

# Buf

Buf is a modern replacement for `protoc`: it builds, lints and formats Protocol
Buffer schemas, detects breaking changes against a previous version of an API,
and generates code through local or remote plugins — all driven by a `buf.yaml`
module config instead of hand-rolled `protoc` invocations.

Alongside the CLI, this package ships the two `protoc` plugins Buf publishes for
teams that still drive code generation through `protoc` itself, so `buf lint`
and `buf breaking` rules can run inside an existing `protoc` pipeline.

## What's included

- **buf** — the CLI: `build`, `lint`, `format`, `breaking`, `generate`,
  `ls-files`, and the Buf Schema Registry commands
- **protoc-gen-buf-breaking** — `protoc` plugin running Buf's breaking-change
  detection against an `against_input` image
- **protoc-gen-buf-lint** — `protoc` plugin running Buf's lint rules

## Links

- [Buf Documentation](https://buf.build/docs)
- [Buf on GitHub](https://github.com/bufbuild/buf)
