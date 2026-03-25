# swift-zfs-tools

CLI for ZFS snapshot lifecycle management: create, consolidate, sync, automate.

Built with Swift 6.0 using [swift-argument-parser](https://github.com/apple/swift-argument-parser) and [swift-shell](https://github.com/jaredmbourgeois/swift-shell). All operations are dry-run by default — pass `--execute true` to run commands against ZFS.

## Installation

### Pre-compiled Binaries

```
bin/macos-arm64/zfs-tools     # macOS Apple Silicon
bin/linux-x86_64/zfs-tools    # Linux x86_64
```

Copy to your `$PATH`:
```bash
cp bin/macos-arm64/zfs-tools /usr/local/bin/zfs-tools
```

### Build from Source

Requires [Swift 6.0+](https://www.swift.org/install/).

```bash
git clone https://github.com/jaredmbourgeois/swift-zfs-tools.git
cd swift-zfs-tools
swift build -c release
# Binary at .build/release/ZFSTools
```

Compile-time defaults (retention schedule, date format, etc.) can be customized in `sources/model/Defaults.swift` before building.

## Quick Start

```bash
# Snapshot matching datasets (dry-run — shows commands without executing)
zfs-tools snapshot --dataset-grep tank/data --recursive true

# Execute for real
zfs-tools snapshot --dataset-grep tank/data --recursive true --execute true

# Apply retention policy
zfs-tools consolidate --dataset-grep tank/data --execute true

# Replicate to remote
zfs-tools sync \
  --dataset-grep tank/data \
  --ssh-user admin --ssh-ip backup.server.com \
  --ssh-port 22 --ssh-key-path ~/.ssh/backup_key \
  --execute true
```

## Commands

Each operation supports three variants:

| Pattern | Description |
|---------|-------------|
| `<command>` | Run directly with inline arguments |
| `<command>-configure` | Save arguments as a reusable JSON config |
| `<command>-configured` | Run from a saved JSON config |

### snapshot / snapshot-configure / snapshot-configured

Creates timestamped ZFS snapshots (`zfs snapshot [-r] dataset@yyyyMMdd-HHmmss`).

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern (all if omitted) |
| `--recursive` | Recursively snapshot child datasets (`-r`) |
| `--max-pool-utilization` | Skip if pool capacity exceeds this percentage (0-100) |
| `--min-free-bytes` | Skip if pool free space is below this threshold |

### consolidate / consolidate-configure / consolidate-configured

Applies a [GFS](https://en.wikipedia.org/wiki/Backup_rotation_scheme#Grandfather-father-son) retention schedule, destroying snapshots outside the retention windows while keeping the best-distributed snapshots within each period.

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern |
| `--consolidation-period-path` | Path to custom schedule JSON (overrides default) |
| `--consolidation-period-upper-bound` | Override the schedule's reference time |
| `--do-not-delete-snapshots-path` | Path to JSON array of protected snapshot names |
| `--max-pool-utilization` | Aggressive prune after consolidation if exceeded |
| `--min-free-bytes` | Aggressive prune after consolidation if below threshold |

### sync / sync-configure / sync-configured

Replicates snapshots to a remote system via `zfs send | ssh zfs recv`. Uses incremental sends when a common snapshot exists. Deletes remote snapshots that no longer exist locally. Sends/receives sequentially since [ZFS receive locks the dataset](https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html).

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern |
| `--ssh-user` | SSH user for remote |
| `--ssh-ip` | SSH host for remote |
| `--ssh-port` | SSH port for remote |
| `--ssh-key-path` | SSH key path for remote |

### execute-actions / execute-actions-configure

Chains multiple operations from a JSON actions file:

```json
[
  {"snapshot": {"configPath": "/path/to/snapshot.json"}},
  {"consolidate": {"configPath": "/path/to/consolidate.json"}},
  {"sync": {"configPath": "/path/to/sync.json"}}
]
```

```bash
zfs-tools execute-actions --actions-path ~/zfs/backup.json --execute true
```

Automate with cron:
```
0 1 * * * /usr/local/bin/zfs-tools execute-actions --actions-path ~/zfs/backup.json --execute true
```

## Retention Policy

The default consolidation schedule (defined in `Defaults.swift`):

| Period | Retention |
|--------|-----------|
| Daily | 1 snapshot/day for 7 days |
| Weekly | 1 snapshot/week for 3 weeks |
| Monthly | 1 snapshot/month for 11 months |
| Yearly | 1 snapshot/year indefinitely |

Within each period, the consolidator keeps snapshots closest to the ideal evenly-distributed dates, destroying the rest. Snapshots newer than the schedule's upper bound are always preserved.

Custom schedules can be defined as JSON (see `tests/resource/ConsolidatorConfig.json`) and loaded via `--consolidation-period-path`.

## Disk Usage Monitoring

Snapshot and consolidate commands support pool utilization thresholds to prevent filling the pool:

```bash
# Skip snapshots if pool is over 80% full
zfs-tools snapshot --dataset-grep tank/data --max-pool-utilization 80 --execute true

# Aggressive prune if less than 5GB free after consolidation
zfs-tools consolidate --dataset-grep tank/data --min-free-bytes 5368709120 --execute true
```

When a threshold is exceeded:
- **Snapshot**: skips creation and prints a warning
- **Consolidate**: runs normal retention first, then aggressively prunes oldest snapshots (preserving the most recent per dataset) until utilization drops below the threshold

These options are available in CLI flags, JSON configs, and `Defaults.swift`.

## Common Options

| Option | Default | Description |
|--------|---------|-------------|
| `--execute` | `false` | Execute commands (dry-run if false) |
| `--date-format` | `yyyyMMdd-HHmmss` | Snapshot timestamp format |
| `--date-separator` | `@` | Separator between dataset name and timestamp |
| `--shell-path` | `/bin/bash` | Shell used for command execution |

## References

- [OpenZFS documentation](https://openzfs.github.io/openzfs-docs/)
- [zfs(8) man page](https://openzfs.github.io/openzfs-docs/man/master/8/zfs.8.html)
- [zfs-send(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-send.8.html) / [zfs-recv(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-receive.8.html)

## License

Licensed under Apache License v2.0 with Runtime Library Exception

I hope you enjoy using zfs-tools! If you would like to show your support, coffee donations are always appreciated!

BTC: `3ACMiYCiknTp4VoSE9Zxc2JnaxmDAMGBqH`
ETH: `0xD97F48B5Ab68285c58BD1D11dE87a166A7C4D0b0`
SOL: `LW3j5Zv54a8qD7dzZ5KdpfE6UssFAGj48uM1DhJCeSN`
