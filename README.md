# swift-zfs-tools

ZFS snapshot management for the command line — create, consolidate, replicate, and automate snapshots. Dry-run by default: the commands it would run are printed until you pass `--execute true`. macOS 14+ and Linux.

Built on [swift-argument-parser](https://github.com/apple/swift-argument-parser) and [swift-shell](https://github.com/jaredmbourgeois/swift-shell). The core logic ships as an importable library, `ZFSToolsModel`.

## Install

### Pre-compiled binaries

```bash
cp bin/macos-arm64/zfs-tools  /usr/local/bin/zfs-tools   # macOS Apple Silicon
cp bin/linux-x86_64/zfs-tools /usr/local/bin/zfs-tools   # Linux x86_64
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

### Regenerate the prebuilt binaries

`zfs-tools-build` rebuilds `bin/<platform>/zfs-tools`, deriving the platform from `uname` at the build site (override with `--platform`). It builds locally when `--remote` is omitted, otherwise rsyncs the source to the host, builds there, and copies the artifact back (override the output with `--destination`).

```bash
swift run ZFSToolsBuilder                          # rebuild this host's binary in place
swift run ZFSToolsBuilder --remote user@buildhost  # build on a remote host over SSH, copy back
```

`--remote` takes any SSH destination or `~/.ssh/config` alias. Add `--swift /path/to/swift` if Swift isn't on the remote's `PATH`.

## Quick start

```bash
# 1. Snapshot — dry-run first (prints commands, runs nothing)
zfs-tools snapshot --dataset-grep tank/data --recursive true

# 2. Run it for real
zfs-tools snapshot --dataset-grep tank/data --recursive true --execute true

# 3. Prune to the GFS schedule
zfs-tools consolidate --dataset-grep tank/data --execute true

# 4. Replicate to a backup host
zfs-tools sync --dataset-grep tank/data \
  --ssh-user backup --ssh-ip backup.server.com \
  --ssh-port 22 --ssh-key-path ~/.ssh/backup_key \
  --execute true
```

Every command discovers datasets with `zfs list -o name -H | grep <pattern>`, then builds shell-safe ZFS commands. The commands it runs, single-quoted against spaces and metacharacters:

```bash
zfs snapshot -r 'tank/data@20250607-120000'
zfs destroy 'tank/data@20250101-000000'
zfs send -v -i 'tank/data@<prev>' 'tank/data@<latest>' \
  | ssh -p '22' -i '~/.ssh/backup_key' 'backup'@'backup.server.com' zfs recv -F 'tank/data@<latest>'
```

## Dry-run by default

`--execute` defaults to `false`. In dry-run, nothing touches ZFS — each command is printed instead of run, so you can inspect exactly what a cron job will do before trusting it. Add `--execute true` to apply. Every run logs each command with its exit status and any stdout/stderr (prefixed `zfs-tools command:`), so real runs are auditable too.

## Commands

Each operation has three variants:

| Variant | Use |
|---------|-----|
| `<command>` | Run directly with inline flags |
| `<command>-configure` | Save those flags to a reusable JSON config (`--output-path`) |
| `<command>-configured` | Run from a saved JSON config (`--config-path`) |

### snapshot

Creates timestamped snapshots: `zfs snapshot [-r] 'dataset@yyyyMMdd-HHmmss'`.

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern (all if omitted) |
| `--recursive` | Snapshot child datasets too (`-r`) |
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

Replicates snapshots to a remote host via `zfs send | ssh zfs recv` — incremental when a common snapshot exists, full otherwise. Remote snapshots that no longer exist locally are destroyed. Sends run sequentially, since [ZFS receive locks the dataset](https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html). See [Remote sync](#remote-sync).

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern |
| `--ssh-user` / `--ssh-ip` / `--ssh-port` / `--ssh-key-path` | Remote connection |
| `--remote-path-strip` | Strip this prefix from each dataset path before sending |
| `--remote-path-root` | Prepend this root to the (stripped) path on the remote |

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

Within each period the consolidator keeps the snapshot closest to each ideal evenly-spaced date and destroys the rest. Snapshots newer than the schedule's upper bound, and any named in `--do-not-delete-snapshots-path`, are always preserved.

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

Remote-path remapping redirects where snapshots land on the destination. `--remote-path-strip` removes a prefix from each local path; `--remote-path-root` prepends a new one:

```bash
# local  tank/data/photos
# strip  tank   →  data/photos
# root   backups/prod  →  backups/prod/data/photos
zfs-tools sync --dataset-grep tank/data \
  --remote-path-strip tank --remote-path-root backups/prod \
  --ssh-user backup --ssh-ip backup.server.com --ssh-port 22 --ssh-key-path ~/.ssh/backup_key \
  --execute true
```

With neither flag set, the receive path matches the send path. Both are optional; the remote dataset listing is filtered with the remapped pattern so incremental-base detection works against the destination's real names.

## Configuration reference

`<command>-configure` writes one of these; `<command>-configured` reads it. JSON is the schema — field names match the `Config` types in `ZFSToolsModel`. `stringEncodingRawValue: 4` is UTF-8. Live examples: [`tests/resource/`](tests/resource/).

```json
// snapshot
{ "datasetGrep": "tank/data", "recursive": true, "execute": false,
  "dateSeparator": "@", "lineSeparator": "\n", "stringEncodingRawValue": 4 }
```

```json
// sync — remotePathStrip / remotePathRoot are optional
{ "datasetGrep": "tank/data", "execute": false,
  "sshUser": "backup", "sshIP": "backup.server.com", "sshPort": "22", "sshKeyPath": "~/.ssh/backup_key",
  "dateSeparator": "@", "lineSeparator": "\n", "stringEncodingRawValue": 4 }
```

```json
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

- Read-only listings (datasets, snapshots, pool stats) and per-dataset `zfs snapshot` run **in parallel**; `destroy` and `send`/`recv` run **sequentially** (ZFS receive locks the dataset).
- Every interpolated value is **single-quoted** for the shell (embedded quotes escaped `'\''`), so dataset names with spaces and grep patterns can't word-split or inject.
- Saved configs are written **atomically** (temp file + rename) — an interrupted write can't corrupt a config.
- Built for **complete Swift 6 strict concurrency**; shell execution and file I/O are injected as `@Sendable` witnesses, which is what makes the core unit-testable without a live pool.

## References

- [OpenZFS docs](https://openzfs.github.io/openzfs-docs/) · [zfs(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs.8.html) · [zfs-send(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-send.8.html) / [zfs-recv(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-receive.8.html)

## License

Apache License v2.0 with Runtime Library Exception.

Donations are welcome — BTC `3ACMiYCiknTp4VoSE9Zxc2JnaxmDAMGBqH` · ETH `0xD97F48B5Ab68285c58BD1D11dE87a166A7C4D0b0` · SOL `LW3j5Zv54a8qD7dzZ5KdpfE6UssFAGj48uM1DhJCeSN`
