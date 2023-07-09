# swift-zfs-tools

A toolkit for managing ZFS snapshots.

## Overview

- Create snapshots
- Consolidate snapshots with configurable retention schedules
- Syncing snapshots to remote systems
- Automating workflows by chaining multiple actions

## Requirements

- ZFS installed on your system
- SSH access (for remote sync operations)
- Swift 6.0+ (if compiling from source)

## Installation

### Option 1: Use Pre-compiled Binary (Recommended)

Pre-compiled binaries are available in `swift-zfs-tools/bin`:

### Option 2: Compile from Source

If you prefer to compile the tool yourself:

1. **Install Swift 6.0+**
   - macOS: Install [Xcode](https://developer.apple.com/xcode/)
   - Ubuntu: Follow the [Swift installation guide](https://www.swift.org/install/linux/)

2. **Clone the repository**
   ```bash
   git clone https://github.com/jaredmbourgeois/swift-zfs-tools.git
   cd swift-zfs-tools
   ```

3. **Optional: Customize defaults**
   - Edit `sources/model/Defaults.swift` to change default settings

4. **Build the project**
   ```bash
   swift build \
     -c release \
     --build-path /desired/build/location
   ```

5. **Install the executable**
   ```bash
   # The binary will be at /desired/build/location/PLATFORM/release/ZFSTools
   cp /desired/build/location/PLATFORM/release/ZFSTools /usr/local/bin/zfs-tools
   ```

## Usage

### Create snapshots
```bash
# Test run (dry-run by default)
zfs-tools snapshot \
  --dataset-grep tank/data \
  --recursive

# Execute the command
zfs-tools snapshot \
  --dataset-grep tank/data \
  --recursive \
  --execute
```

### Consolidate snapshots with retention policy
```bash
# Apply retention policy (dry run)
zfs-tools consolidate \
  --dataset-grep tank/data

# Execute the consolidation
zfs-tools consolidate \
  --dataset-grep tank/data \
  --execute
```

### Sync snapshots to remote system
```bash
zfs-tools sync \
  --dataset-grep tank/data \
  --ssh-user admin \
  --ssh-ip backup.server.com \
  --ssh-port 22 \
  --ssh-key-path ~/.ssh/backup_key \
  --execute
```

## Configuration Files

Create reusable configurations:

```bash
# Create configuration files
zfs-tools snapshot-configure \
  --dataset-grep tank/data \
  --recursive \
  --output-path ~/zfs/snapshot.json

zfs-tools consolidate-configure \
  --dataset-grep tank/data \
  --output-path ~/zfs/consolidate.json

zfs-tools sync-configure \
  --dataset-grep tank/data \
  --ssh-user admin \
  --ssh-ip backup.server.com \
  --ssh-port 22 \
  --ssh-key-path ~/.ssh/backup_key \
  --output-path ~/zfs/sync.json

# Run from configuration files
zfs-tools snapshot-configured \
  --config-path ~/zfs/snapshot.json \
  --execute

zfs-tools consolidate-configured \
  --config-path ~/zfs/consolidate.json \
  --execute

zfs-tools sync-configured \
  --config-path ~/zfs/sync.json \
  --execute
```

## Automating Workflows

Chain operations with `execute-actions`:

1. Create an actions file (e.g., `~/zfs/backup.json`):
   ```json
   [
     {"snapshot": {"configPath": "/path/to/snapshot.json"}},
     {"consolidate": {"configPath": "/path/to/consolidate.json"}},
     {"sync": {"configPath": "/path/to/sync.json"}}
   ]
   ```

2. Run the workflow:
   ```bash
   zfs-tools execute-actions \
     --actions-path ~/zfs/backup.json \
     --execute
   ```

3. Add to crontab for scheduled backups:
   ```
   0 1 * * * /usr/local/bin/zfs-tools execute-actions --actions-path ~/zfs/backup.json --execute
   ```

## Default Retention Policy

The default consolidation policy keeps:
- Daily snapshots for 7 days
- Weekly snapshots for 3 weeks
- Monthly snapshots for 11 months
- Yearly snapshots indefinitely

Customize by editing `Defaults.swift` before building or by creating a custom configuration.

## Common Options

| Option | Description | Default |
|--------|-------------|---------|
| `--date-format` | Format for snapshot timestamps | `yyyyMMdd-HHmmss` |
| `--date-separator` | Separator between dataset name and timestamp | `@` |
| `--execute` | Actually execute the commands (otherwise dry-run) | `false` |
| `--line-separator` | Line separator for output | `\n` |
| `--shell-path` | Path to the shell | `/bin/bash` |

## Example Configurations

Check the `tests/resource` directory for example configuration files.

## License

Licensed under Apache License v2.0 with Runtime Library Exception

```
I hope you enjoy using zfs-tools! If you would like to show your support, coffee donations are always appreciated!
BTC: 3ACMiYCiknTp4VoSE9Zxc2JnaxmDAMGBqH
ETH: 0xD97F48B5Ab68285c58BD1D11dE87a166A7C4D0b0
SOL: LW3j5Zv54a8qD7dzZ5KdpfE6UssFAGj48uM1DhJCeSN
```
