# swift-zfs-tools

ZFS snapshot management for the command line — create, consolidate, replicate, and automate snapshots.

Dry-run by default: the commands it would run are printed until you pass `--execute true`. Supports macOS 14+ and Linux with Swift 6.0+.

Built on [swift-argument-parser](https://github.com/apple/swift-argument-parser) and [swift-shell](https://github.com/jaredmbourgeois/swift-shell). The core logic ships as an importable library, `ZFSToolsModel`.

## Install

Binaries are built on demand, not committed to the repository — `bin/` is regenerable output
(`.gitignore`d), not a source artifact. See "Build the platform binaries" below to build for your
platform (locally, or cross-built onto a remote host over SSH), then install the result:

```bash
sudo install -m 0755 bin/macos-arm64/zfs-tools  /usr/local/bin/zfs-tools   # macOS Apple Silicon
sudo install -m 0755 bin/linux-x86_64/zfs-tools /usr/local/bin/zfs-tools   # Linux x86_64
```

### Build from source

Requires [Swift 6.0+](https://www.swift.org/install/).

```bash
git clone https://github.com/jaredmbourgeois/swift-zfs-tools.git
cd swift-zfs-tools
swift build -c release
# binary at .build/release/ZFSTools
```

Compile-time defaults (retention schedule, date format, shell) live in `sources/model/Defaults.swift`.

### Build the platform binaries

`zfs-tools-build` builds `bin/<platform>/zfs-tools`, deriving the platform from `uname` at the build site (override with `--platform`). It builds locally when `--remote` is omitted, otherwise rsyncs the source to the host, builds there, and copies the artifact back (override the output with `--destination`).

Release artifacts default to `--static-swift-stdlib` so Linux binaries can run on hosts without a Swift toolchain; pass `--no-static-swift-stdlib` only when you intentionally want a dynamic Swift-runtime build. This is not a fully static binary: Linux artifacts still depend on the platform C runtime/dynamic loader, and macOS builds still link Apple's system Swift dylibs because modern Swift no longer supports static Swift stdlib linkage on macOS.

```bash
swift run ZFSToolsBuilder                          # rebuild this host's binary in place
swift run ZFSToolsBuilder --remote user@buildhost  # build on a remote host over SSH, copy back
```

`--remote` takes any SSH destination or `~/.ssh/config` alias. Add `--swift /path/to/swift` if Swift isn't on the remote's `PATH`. `--temp-dir` is interpreted relative to the remote login directory unless it is absolute. It must name a real build directory: root, empty, parent-directory paths, `~/...`, and broad absolute paths are rejected before cleanup can run. Absolute temp-dir basenames must contain `zfs-tools-build`.

## Quick start

```bash
# 1. Snapshot — dry-run first (prints commands, runs nothing)
zfs-tools snapshot --dataset-grep tank/data --recursive true

# Skip received/forwarded subtrees during broad snapshot runs
zfs-tools snapshot --dataset-grep tank/data --excluded-dataset-greps tank/data/received

# 2. Run it for real
zfs-tools snapshot --dataset-grep tank/data --recursive true --execute true

# 3. Prune to the GFS schedule
zfs-tools consolidate --dataset-grep tank/data --execute true

# 4. Replicate to a backup host
zfs-tools sync --dataset-grep tank/data \
  --ssh-user backup --ssh-ip backup.server.com \
  --ssh-port 22 --ssh-key-path ~/.ssh/backup_key \
  --send-rate-limit 20M \
  --execute true
```

Every command discovers datasets with `zfs list -o name -H | grep <pattern>`, then builds shell-safe ZFS commands. The commands it runs, single-quoted against spaces and metacharacters:

```bash
zfs snapshot -r 'tank/data@20250607-120000'
zfs destroy 'tank/data@20250101-000000'
set -o pipefail; zfs send -v -i 'tank/data@<prev>' 'tank/data@<latest>' \
  | pv -q -L '20M' \
  | ssh -p '22' -i '~/.ssh/backup_key' 'backup'@'backup.server.com' zfs recv -F 'tank/data@<latest>'
```

## Safety notes

- Dry-run is the default. Start every new config without `--execute true`, inspect the logged commands, then run it for real.
- `sync` defaults to pruning destination snapshots whose ZFS `guid` is absent locally. This preserves historical behavior, but it is destructive; set `--prune-remote-snapshots false` for append-only/offsite receivers.
- Test new schedules and path remapping against a non-critical dataset before pointing them at production pools.
- Run the tool as a user with the minimum ZFS permissions needed for the operation. For push replication over SSH, use `receive-guard` as a forced command on the receiver key.

## Dry-run by default

`--execute` defaults to `false`. In dry-run, nothing touches ZFS — each command is printed instead of run, so you can inspect exactly what a cron job will do before trusting it. Add `--execute true` to apply. Every run logs each command, result, stdout, and stderr with explicit `zfs-tools command:`, `zfs-tools result:`, `zfs-tools stdout:`, and `zfs-tools stderr:` prefixes, so real runs are auditable too.

## Commands

Each operation has three variants:

| Variant | Use |
|---------|-----|
| `<command>` | Run directly with inline flags |
| `<command>-configure` | Save those flags to a reusable JSON config (`--output-path`) |
| `<command>-configured` | Run from a saved JSON config (`--config-path`) |

### snapshot

Creates timestamped snapshots: `zfs snapshot [-r] 'dataset@yyyyMMdd-HHmmss'`. When `--recursive true` is used without exclusions, zfs-tools snapshots only the top-most listed datasets with `-r` so children are not snapshotted twice. When exclusions are present, it snapshots the filtered datasets non-recursively so an excluded descendant is not crossed by a parent `-r`.

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern (all if omitted) |
| `--recursive` | Snapshot child datasets too (`-r`) |
| `--excluded-dataset-greps` | Dataset substring to skip after listing; repeat to avoid snapshotting received/forwarded trees |
| `--max-pool-utilization` | Skip if pool capacity exceeds this percent (0–100) |
| `--min-free-bytes` | Skip if pool free space is below this many bytes |

### consolidate

Applies a [GFS](https://en.wikipedia.org/wiki/Backup_rotation_scheme#Grandfather-father-son) retention schedule, destroying snapshots outside the windows while keeping the best-distributed snapshot within each. See [Retention](#retention).

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern |
| `--consolidation-period-path` | Custom schedule JSON (overrides the default) |
| `--consolidation-period-upper-bound` | Schedule reference time (default: now), parsed with `--date-format` |
| `--do-not-delete-snapshots-path` | JSON array of snapshot names to always keep |
| `--max-pool-utilization` | After consolidation, aggressively prune if capacity still exceeds this percent |
| `--min-free-bytes` | After consolidation, aggressively prune if free space is still below this |

### sync

Replicates snapshots to a remote host via `zfs send | ssh zfs recv` — incremental when a common snapshot exists, full otherwise. By default, remote snapshots whose ZFS `guid` is absent locally are destroyed. Sends run sequentially, since [ZFS receive locks the dataset](https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html). See [Remote sync](#remote-sync).

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern |
| `--ssh-user` / `--ssh-ip` / `--ssh-port` / `--ssh-key-path` | Remote connection |
| `--remote-path-strip` | Strip this prefix from each dataset path before sending |
| `--remote-path-root` | Prepend this root to the (stripped) path on the remote |
| `--send-rate-limit` | Optional local `pv -q -L` throughput limit for each `zfs send` pipeline |
| `--prune-remote-snapshots` | Destroy remote snapshots absent locally; defaults to `true` for compatibility, set `false` for append-only/offsite receivers |
| `--sent-bookmark-name` | Optional local bookmark component, e.g. `sent-backup`; after each successful send, `dataset#<name>` is advanced and can be used as an incremental base after source snapshots are pruned |

### execute-actions

Chains snapshot / consolidate / sync from one JSON file — each entry points at a saved config. Ideal for cron.

```bash
zfs-tools execute-actions --actions-path ~/zfs/backup.json --execute true
zfs-tools execute-actions-configure --output-path ~/zfs/backup.json   # writes a template
```

```cron
0 1 * * * /usr/local/bin/zfs-tools execute-actions --actions-path ~/zfs/backup.json --execute true
```

## Retention

The default schedule (`Defaults.swift`):

| Period | Keep |
|--------|------|
| Daily | 1 / day for 7 days |
| Weekly | 1 / week for 3 weeks |
| Monthly | 1 / month for 11 months |
| Yearly | 1 / year, forever |

Within each period the consolidator keeps the snapshot closest to each ideal evenly-spaced date and destroys the rest. Snapshots newer than the schedule's upper bound, any named in `--do-not-delete-snapshots-path`, and snapshots whose suffix cannot be parsed with the configured date format are preserved.

This is the point of consolidation: **3 years of daily snapshots is ~1000 snapshots; under this schedule it collapses to ~24** (7 daily + 3 weekly + 11 monthly + ~3 yearly) while keeping fine-grained recent history and coarse-grained old history.

Define a custom schedule as JSON and load it with `--consolidation-period-path`. Each period sets how many `snapshots` to keep `every` `everyMultiple` × `everyPeriod` (`days`/`weeks`/`months`/`years`/`hours`), `repetitions` times (omit `repetitions` for "forever"):

```json
{
  "periods": [
    { "everyMultiple": 1, "everyPeriod": "days",   "repetitions": 7,  "snapshots": 1 },
    { "everyMultiple": 1, "everyPeriod": "weeks",  "repetitions": 3,  "snapshots": 1 },
    { "everyMultiple": 1, "everyPeriod": "months", "repetitions": 11, "snapshots": 1 },
    { "everyMultiple": 1, "everyPeriod": "years",                     "snapshots": 1 }
  ],
  "upperBound": null
}
```

## Pool-utilization guards

`snapshot` and `consolidate` can read pool capacity (`zpool list`) and free space (`zfs list`) and act on a threshold — either `--max-pool-utilization` (percent) or `--min-free-bytes`:

```bash
# Don't add snapshots once the pool passes 80% full
zfs-tools snapshot --dataset-grep tank/data --max-pool-utilization 80 --execute true

# Consolidate, then keep pruning oldest snapshots until ≥ 5 GiB is free
zfs-tools consolidate --dataset-grep tank/data --min-free-bytes 5368709120 --execute true
```

- **snapshot** skips creation and warns:
  `zfs-tools snapshot: WARNING — pool tank utilization exceeds threshold (capacity: 86.0%, available: … bytes). Skipping snapshot creation.`
- **consolidate** runs the normal schedule first, then — if still over the line — aggressively prunes the oldest snapshots one at a time (always keeping the most recent per dataset, plus anything protected) until utilization drops back under the threshold.

Pool reads are fail-loud: if a real run gets unparseable output from ZFS, it errors rather than reading 0% and letting a full pool slip past the guard. (In dry-run the guard is inert.)

## Remote sync

Sync orders snapshots by ZFS `createtxg` and matches common bases by snapshot `guid`, not by parsing the snapshot name. Snapshot names may be descriptive, manually created, or from another host/timezone; the authoritative ZFS metadata determines incremental order. If no common guid exists, sync falls back to a full send.

Remote-path remapping redirects where snapshots land on the destination. `--remote-path-strip` removes a full path-component prefix from each local path; `--remote-path-root` prepends a new one:

```bash
# local  tank/data/photos
# strip  tank   →  data/photos
# root   backups/prod  →  backups/prod/data/photos
zfs-tools sync --dataset-grep tank/data \
  --remote-path-strip tank --remote-path-root backups/prod \
  --ssh-user backup --ssh-ip backup.server.com --ssh-port 22 --ssh-key-path ~/.ssh/backup_key \
  --execute true
```

With neither flag set, the receive path matches the send path. Both are optional. Remote snapshot records are listed over SSH and then filtered with the remapped pattern on the sender side, so incremental-base detection works against the destination's real names while `receive-guard` can still exact-match the bare `zfs list` command. A strip value of `tank` matches `tank/data`, not `tankish/data`.

Add `--send-rate-limit <rate>` to throttle each local `zfs send` stream through `pv -q -L`. The value must be a positive byte count with an optional `K`/`M`/`G`/`T`/`P`/`E`/`Z`/`Y` suffix, such as `20M`; omit the option for no limit. Real runs require `pv` on the sending host when this option is set. Send pipelines start with `set -o pipefail`, so a failure in `zfs send`, `pv`, or `ssh zfs recv` fails the whole command instead of reporting success from the last pipeline stage only.

By default, sync preserves the historical pruning behavior: destination snapshots whose ZFS `guid` is absent locally are destroyed. This is intentionally based on `guid`, not names, so a remapped or differently named destination snapshot with the same identity is preserved. Set `--prune-remote-snapshots false` for append-only or intermittently available offsite receivers where destination history may intentionally outlive source retention.

For offsites that may be unavailable longer than the source retention window, set `--sent-bookmark-name <stable-destination-name>`. The value is a bookmark component, not a full `dataset#bookmark` path; it must be non-empty and contain only letters, digits, `.`, `_`, `-`, or `:`. After each successful send, zfs-tools advances a local `dataset#<stable-destination-name>` bookmark, creating a temporary replacement before destroying the previous stable bookmark. On later runs, if the last sent source snapshot has been pruned but the destination still has the same guid, zfs-tools uses the bookmark as the `zfs send -i` base instead of falling back to a full send.

### receive-guard

`zfs-tools receive-guard --pool <pool>` is intended for SSH forced commands on push-replication receiver keys. It accepts only the command shapes emitted by `sync`: `zfs recv -F <target>`, the snapshot-record `zfs list`, and `zfs destroy <snapshot>`. Receive and destroy targets must stay inside `--pool`, destroy targets must be snapshots, and the accepted list command is executed as a scoped `zfs list ... -r <pool>` so the key cannot enumerate unrelated snapshots. The pool name must be a single pool component: no empty value, surrounding whitespace, `/`, `@`, or `#`.

Example `authorized_keys` entry on the receiver:

```text
command="/usr/local/bin/zfs-tools receive-guard --pool backup",restrict ssh-ed25519 AAAA... zfs-backup-push
```

The sender still connects normally with `zfs-tools sync`; OpenSSH supplies the original remote command to the guard through `SSH_ORIGINAL_COMMAND`.

## Configuration reference

`<command>-configure` writes one of these; `<command>-configured` reads it. JSON is the schema — field names match the `Config` types in `ZFSToolsModel`. `stringEncodingRawValue: 4` is UTF-8. Live examples: [`tests/resource/`](tests/resource/). New optional fields decode with conservative defaults when absent, so older configs continue to work.

```jsonc
// snapshot
{ "datasetGrep": "tank/data", "recursive": true, "execute": false,
  "excludedDatasetGreps": [],
  "dateSeparator": "@", "lineSeparator": "\n", "stringEncodingRawValue": 4 }
```

```jsonc
// sync — remotePathStrip / remotePathRoot / sendRateLimit / sentBookmarkName are optional
{ "datasetGrep": "tank/data", "execute": false,
  "sshUser": "backup", "sshIP": "backup.server.com", "sshPort": "22", "sshKeyPath": "~/.ssh/backup_key",
  "sendRateLimit": "20M", "pruneRemoteSnapshots": true, "sentBookmarkName": "sent-backup",
  "dateSeparator": "@", "lineSeparator": "\n", "stringEncodingRawValue": 4 }
```

```jsonc
// actions — chain saved configs in order
[
  { "snapshot":    { "configPath": "/zfs/tank-data-snapshot.json" } },
  { "consolidate": { "configPath": "/zfs/tank-data-consolidate.json" } },
  { "sync":        { "configPath": "/zfs/tank-data-sync.json" } }
]
```

A consolidate config wraps the [schedule](#retention) shown above plus `datasetGrep`, `snapshotsNotConsolidated`, and the common fields — see [`tests/resource/ConsolidatorConfig.json`](tests/resource/ConsolidatorConfig.json).

## Common options

| Option | Default | Description |
|--------|---------|-------------|
| `--execute` | `false` | Run commands (dry-run when false) |
| `--date-format` | `yyyyMMdd-HHmmss` | Snapshot timestamp format |
| `--date-separator` | `@` | Separator between dataset name and timestamp |
| `--shell-path` | `/bin/bash` | Shell used to run commands |

## Under the hood

- Read-only listings (datasets, snapshot records, pool stats) and per-dataset `zfs snapshot` run **in parallel**; `destroy` and `send`/`recv` run **sequentially** (ZFS receive locks the dataset).
- Sync lists snapshot records as `guid,createtxg,name` and chooses the most recent common guid as the incremental base; snapshot names are display labels, not ordering metadata. Remote pruning is guid-based, so a differently named destination snapshot with the same guid is preserved.
- Every interpolated value is **single-quoted** for the shell (embedded quotes escaped `'\''`), so dataset names with spaces and grep patterns can't word-split or inject.
- Optional send throttling uses the sender's `pv -q -L` in the local pipeline; `set -o pipefail` makes any send/throttle/receive stage fail the command.
- Saved configs are written **atomically** (temp file + rename) — an interrupted write can't corrupt a config.
- Built for **complete Swift 6 strict concurrency**; shell execution and file I/O are injected as `@Sendable` witnesses, which is what makes the core unit-testable without a live pool.

## References

- [OpenZFS docs](https://openzfs.github.io/openzfs-docs/) · [zfs(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs.8.html) · [zfs-send(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-send.8.html) / [zfs-recv(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-receive.8.html)

## License

Apache License v2.0 with Runtime Library Exception.

Donations are welcome — BTC `3ACMiYCiknTp4VoSE9Zxc2JnaxmDAMGBqH` · ETH `0xD97F48B5Ab68285c58BD1D11dE87a166A7C4D0b0` · SOL `LW3j5Zv54a8qD7dzZ5KdpfE6UssFAGj48uM1DhJCeSN`
