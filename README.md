# swift-zfs-tools

ZFS snapshot management for the command line — create, consolidate, replicate, and automate snapshots.

Dry-run by default: the commands it would run are printed until you pass `--execute true`. Supports macOS 14+ and Linux with Swift 6.0+.

Built on [swift-argument-parser](https://github.com/apple/swift-argument-parser) and [swift-shell](https://codeberg.org/BourgeoisConcernLLC/swift-shell). The core logic ships as an importable library, `ZFSToolsModel`.

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
git clone https://codeberg.org/BourgeoisConcernLLC/swift-zfs-tools.git
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

`--remote` takes any SSH destination or `~/.ssh/config` alias. Add `--swift /path/to/swift` if Swift isn't on the remote's `PATH`. `--temp-dir` is interpreted relative to the remote login directory unless it is absolute. It must name a real build directory: root, empty, parent-directory paths, `~/...`, and broad absolute paths are rejected before cleanup can run. The temp-dir basename, relative or absolute, must contain `zfs-tools-build`.

`--remote-command-prefix <words…>` runs the remote build's two `swift` commands (`swift build`, and the `--show-bin-path` query that locates the artifact) through a wrapper of your choosing — a resource-limiting launcher, say — inside the build directory:

```bash
swift run ZFSToolsBuilder --remote user@buildhost --swift /usr/bin/swift \
  --remote-command-prefix sudo -n my-build-wrapper
# on the remote: cd '<temp-dir>' && 'sudo' '-n' 'my-build-wrapper' '/usr/bin/swift' build -c 'release' --static-swift-stdlib
```

The prefix is every word after the option, dash-prefixed ones included, so it must be the **last** option on the command line. It needs `--remote` (a local build has no remote command; the combination is rejected), and the probe, the rsync, the copy back and the cleanup are not wrapped. Without the option nothing is prefixed.

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

# 4. Replicate to a backup host (add --prune-remote-snapshots true to also destroy
#    destination snapshots that are gone locally; nothing there is destroyed without it)
zfs-tools sync --dataset-grep tank/data \
  --ssh-user backup --ssh-ip backup.server.com \
  --ssh-port 22 --ssh-key-path ~/.ssh/backup_key \
  --send-rate-limit 20M \
  --execute true
```

Every command lists datasets with a bare `zfs list -o name -H`, filters the names itself (a fixed substring, not a regex), then issues each ZFS command as a program and its arguments. The lines it logs quote a token only when it needs quoting, so each pastes back into a shell as the same command:

```bash
zfs snapshot -r tank/data@20250607-120000
zfs destroy 'tank/my data@20250101-000000'
set -o pipefail; zfs send -v -i tank/data@20250606-120000 tank/data@20250607-120000 \
  | pv -q -L 20M \
  | ssh -p 22 -i /home/me/.ssh/backup_key backup@backup.server.com 'zfs recv -F tank/data@20250607-120000'
set -o pipefail; zfs send -v -I tank/data@20250601-120000 tank/data@20250607-120000 \
  | ssh -p 22 -i /home/me/.ssh/backup_key backup@backup.server.com 'zfs recv -F tank/data'
```

## Safety notes

- Dry-run is the default. Start every new config without `--execute true`, inspect the logged commands, then run it for real.
- `sync` destroys nothing on the destination unless told to: `--prune-remote-snapshots true` (or `"pruneRemoteSnapshots": true` in a saved config) makes it destroy destination snapshots whose ZFS `guid` is absent locally. Before 3.0.0 this was on by default — see [Upgrading from 2.x](#upgrading-from-2x).
- Test new schedules and path remapping against a non-critical dataset before pointing them at production pools.
- Run the tool as a user with the minimum ZFS permissions needed for the operation ([Permissions](#permissions)). For push replication over SSH, use `receive-guard` as a forced command on the receiver key.

## Dry-run by default

`--execute` defaults to `false`. In dry-run, nothing is changed on ZFS: the read-only commands (`zfs list`, `zpool list`, the remote listing over SSH) run for real, so the plan is computed against the pool as it is, and every mutating command (`zfs snapshot`, `zfs destroy`, `zfs bookmark`, the send pipeline) is printed instead of run — so you can inspect exactly what a cron job will do before trusting it. Add `--execute true` to apply. A dry run therefore needs `zfs` on the host (and the receiver reachable for `sync`); a listing that fails fails the run rather than reporting an empty plan. Every run logs each command, result, stdout, and stderr with explicit `zfs-tools command:`, `zfs-tools result:`, `zfs-tools stdout:`, and `zfs-tools stderr:` prefixes, so real runs are auditable too.

That command log is the tool's output and goes to **stdout**. Diagnostics — the pool-guard warnings, the aggressive-prune narration, a `receive-guard` rejection — go to **stderr**, so `zfs-tools … > plan.txt` captures the commands and nothing else.

Every command is issued as a program and its arguments, not as a shell line, so a dataset name with a space or a shell character reaches `zfs` as written; the one shell pipeline is the send stream (`zfs send … | ssh … 'zfs recv -F …'`). The logged command line quotes a token only when it needs quoting, and pastes back into a shell as the same command.

The `zfs`, `zpool` and `ssh` it runs are given exactly the environment and working directory `zfs-tools` itself was started with, and a bare `zfs` is looked up on that environment's `PATH`. Under cron or a service manager, set a `PATH` that holds `zfs` (on Debian and Ubuntu it lives in `/usr/sbin`): with no `PATH` at all nothing is found, and the run fails naming the program.

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

Replicates snapshots to a remote host via `zfs send | ssh zfs recv` — incremental when a common snapshot exists, full otherwise, and **at most two streams per dataset** however many snapshots it owes: one `-I` stream carries a whole run of snapshots (a bookmark base adds one `-i` first, since `-I` cannot start at a bookmark; no base adds a full send of the first). An owed list that is not provably one ascending run falls back to one `-i` per snapshot. Datasets run in name order, so a parent is received before its children. With `--prune-remote-snapshots true`, remote snapshots whose ZFS `guid` is absent locally are destroyed first; without it the destination only ever gains snapshots. Sends run sequentially, since [ZFS receive locks the dataset](https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html). See [Remote sync](#remote-sync).

| Option | Description |
|--------|-------------|
| `--dataset-grep` | Filter datasets by name pattern |
| `--ssh-user` / `--ssh-ip` / `--ssh-port` / `--ssh-key-path` | Remote connection |
| `--remote-path-strip` | Strip this prefix from each dataset path before sending |
| `--remote-path-root` | Prepend this root to the (stripped) path on the remote |
| `--send-rate-limit` | Optional local `pv -q -L` throughput limit for each `zfs send` pipeline |
| `--prune-remote-snapshots` | `true` destroys remote snapshots absent locally; defaults to `false`, which destroys nothing on the destination (append-only/offsite receivers) |
| `--sent-bookmark-name` | Optional local bookmark component, e.g. `sent-backup`; once a dataset's streams have all landed, `dataset#<name>` is advanced to its newest snapshot and can be used as an incremental base after source snapshots are pruned |

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

Pool reads are fail-loud: unparseable output from ZFS errors rather than reading 0% and letting a full pool slip past the guard. The guard reads the real pool on a dry run too and reports what it would do — `snapshot` prints the warning with "would skip", and `consolidate` prints the aggressive-prune candidates oldest-first (reading the pool once, since nothing is destroyed) instead of destroying them.

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

By default, sync destroys nothing on the destination: its history may outlive the source's retention, which is what an append-only or intermittently available offsite receiver wants. Set `--prune-remote-snapshots true` to have each sync first destroy the destination snapshots whose ZFS `guid` is absent locally, so the destination follows the source's retention. The match is intentionally by `guid`, not by name, so a remapped or differently named destination snapshot with the same identity is preserved.

For offsites that may be unavailable longer than the source retention window, set `--sent-bookmark-name <stable-destination-name>`. The value is a bookmark component, not a full `dataset#bookmark` path; it must be non-empty and contain only letters, digits, `.`, `_`, `-`, or `:`. Once a dataset's streams have all landed, zfs-tools advances a local `dataset#<stable-destination-name>` bookmark to its newest snapshot, creating a temporary replacement before destroying the previous stable bookmark. On later runs, if the last sent source snapshot has been pruned but the destination still has the same guid, zfs-tools uses the bookmark as the `zfs send -i` base instead of falling back to a full send.

### receive-guard

`zfs-tools receive-guard --pool <pool>` is intended for SSH forced commands on push-replication receiver keys. It accepts only the command shapes emitted by `sync`: `zfs recv -F <target>` (a snapshot name, or the dataset for a multi-snapshot `-I` stream), the snapshot-record `zfs list`, and `zfs destroy <snapshot>`. Receive and destroy targets must stay inside `--pool`, a destroy target must be one snapshot (never a `%` range or a `,` list), and the accepted list command is executed as a scoped `zfs list ... -r <pool>` so the key cannot enumerate unrelated snapshots. The pool name must be a single pool component: no empty value, surrounding whitespace, `/`, `@`, or `#`. An approved command is run directly, with no shell, as the `zfs` at the first of `/usr/sbin/zfs`, `/sbin/zfs`, `/usr/local/sbin/zfs` that is executable; the guard never searches `PATH`.

The sender hands `ssh` each remote command as one argument, quoting a token only when it needs quoting, and the guard reads a quoted token and a bare one as the same argument. So the lines a guard receives are bare words, with quotes only around a name that holds a space or a shell character. (Senders before 2.2.0 quoted every argument, but for their own local shell, which removed the quotes before `ssh` ran: the guard received bare words from them too, and a name with a space arrived split.) Every remote command a release's sender emits is recorded in [`tests/resource/remote_shapes/`](tests/resource/remote_shapes/), one file per version, and the test suite holds the current guard to all of them — see [Releasing](#releasing).

Example `authorized_keys` entry on the receiver:

```text
command="/usr/local/bin/zfs-tools receive-guard --pool backup",restrict ssh-ed25519 AAAA... zfs-backup-push
```

The sender still connects normally with `zfs-tools sync`; OpenSSH supplies the original remote command to the guard through `SSH_ORIGINAL_COMMAND`.

## Configuration reference

`<command>-configure` writes one of these; `<command>-configured` reads it. JSON is the schema — field names match the `Config` types in `ZFSToolsModel`. `stringEncodingRawValue: 4` is UTF-8. Live examples: [`tests/resource/`](tests/resource/). Optional fields decode with conservative defaults when absent, so older configs continue to load — and a sync config with no `pruneRemoteSnapshots` key does not prune (before 3.0.0 it did; see [Upgrading from 2.x](#upgrading-from-2x)).

```jsonc
// snapshot
{ "datasetGrep": "tank/data", "recursive": true, "execute": false,
  "excludedDatasetGreps": [],
  "dateSeparator": "@", "lineSeparator": "\n", "stringEncodingRawValue": 4 }
```

```jsonc
// sync — remotePathStrip / remotePathRoot / sendRateLimit / sentBookmarkName are optional;
//        pruneRemoteSnapshots is false when omitted
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
| `--shell-path` | `/bin/bash` | Shell used to run the send pipeline |

Snapshot timestamps are written and read in the time zone `zfs-tools` runs in.

## Permissions

Run each command as the least-privileged user that can do its job, with ZFS delegation (`zfs allow`) on the datasets it touches. The listings (`zfs list`, `zpool list`) need no delegation. What each verb issues, and the delegation that carries it:

| Verb | Mutating commands it runs | `zfs allow` permissions |
|------|---------------------------|-------------------------|
| `snapshot` | `zfs snapshot [-r]` | `snapshot` |
| `consolidate` | `zfs destroy <snapshot>` | `destroy` |
| `sync`, on the sender | `zfs send`, `zfs send -i`, `zfs send -I` | `send`, `hold` |
| `sync --sent-bookmark-name`, on the sender | `zfs bookmark`, `zfs destroy <bookmark>` | `bookmark`, `destroy` |
| `sync`, on the receiver (the user the push key logs in as) | `zfs recv -F`; with `--prune-remote-snapshots true` also `zfs destroy <snapshot>` | `create`, `mount`, `receive`, `rollback`, `destroy`, `hold`, `release` |

```bash
# sender: snapshot, consolidate and sync with a sent-bookmark, as one user
sudo zfs allow backup-sender snapshot,destroy,send,hold,bookmark tank/data
# receiver: the user behind the receive-guard key
sudo zfs allow backup-receiver create,mount,receive,rollback,destroy,hold,release backup
```

`hold` on the sender is easy to miss: a multi-snapshot `zfs send -I` stream — what `sync` sends whenever a dataset owes more than one snapshot — places temporary holds on the snapshots it reads, and without the permission the send dies with `cannot hold: permission denied`. The sender does not need `release`.

These are the sets the tool is run with on Linux (OpenZFS 2.x), where the sender's set works without `mount` although `zfs-allow(8)` names `mount` as a companion of `snapshot` and `destroy`. Delegation differs between platforms, so read `zfs-allow(8)` on yours, and prove a new delegation with a dry run followed by one real run against a scratch dataset.

## Upgrading from 2.x

3.0.0 changes three things an operator can observe. The commands it issues to ZFS are unchanged — the same lines, in the same order.

- **`sync` no longer prunes unless told to.** `--prune-remote-snapshots` now defaults to `false`, and a saved config without `"pruneRemoteSnapshots"` no longer prunes. If a destination relied on the old default to follow the source's retention, add `--prune-remote-snapshots true` (or `"pruneRemoteSnapshots": true`) before upgrading, or it will keep every snapshot it receives.
- **Warnings moved to stderr.** The pool-guard warnings and the aggressive-prune narration were printed to stdout among the command log; they now go to stderr. The command log itself is still stdout.
- **No `PATH`, no `zfs`.** A child process is given exactly the environment `zfs-tools` was started with. 2.x searched `/usr/bin:/bin` for a bare `zfs` when the environment had no `PATH`; 3.0.0 finds nothing and fails the run. An environment that sets `PATH` behaves as before.

For code that imports `ZFSToolsModel`: no parameter has a default any more (every `Config` initializer states each field), `Snapshotter`, `Consolidator`, `Syncer` and `ActionExecutor` take the shell that runs commands and the dry-run shell that reports them (`shell:`, `dryRunShell:`) plus a `diagnostics:` sink where they warn, `makeCalendar` and `makeDateFormatter` take the locale and time zone, and `ShellAtPath.loggingToStdout` is gone — build the shells with swift-shell 3.0.0's `ShellAtPath.live` and `ShellAtPath.dryRun` at your composition root, with `ShellLogFormatter.resultObserver(write:)` as their observer.

## Under the hood

- Read-only listings (datasets, snapshot records, pool stats) and per-dataset `zfs snapshot` run **in parallel**; `destroy` and `send`/`recv` run **sequentially** (ZFS receive locks the dataset).
- Sync lists snapshot records as `guid,createtxg,name` and chooses the most recent common guid as the incremental base; snapshot names are display labels, not ordering metadata. Remote pruning is guid-based, so a differently named destination snapshot with the same guid is preserved.
- Every ZFS command is spawned as a program with its arguments, so a dataset name with a space or a shell character can't word-split or inject; where a command must travel as text (the remote command handed to `ssh`, the stages of the send pipeline) each token is **single-quoted when it needs quoting** (embedded quotes escaped `'\''`).
- Optional send throttling uses the sender's `pv -q -L` in the local pipeline; `set -o pipefail` makes any send/throttle/receive stage fail the command.
- Saved configs are written **atomically** (temp file + rename) — an interrupted write can't corrupt a config.
- A dry run is a different shell, not a flag: every operation is handed one shell that runs commands and one that only reports them, and a single decision — where the operation builds its runner — sends each mutating command to one or the other. Read-only commands always go to the shell that runs.
- Built for **complete Swift 6 strict concurrency**. Nothing below a command's `run()` reads the environment, the clock, the file system, the locale or a standard stream for itself: each is read once at the composition root and handed down, as a value or a `@Sendable` closure, which is what makes the core unit-testable without a live pool. No parameter has a default value. A test that scans the package's own sources and tests (`tests/SourceRulesTest.swift`) holds both rules under `swift test`.

## Releasing

A release is an annotated tag `X.Y.Z` (no `v`) on a commit whose CI run is green. In order:

1. **swift-shell first, if the release needs a new one.** Tag swift-shell (its README's Releasing section), then set the exact pin in `Package.swift` (`Dependency.shell`'s `packageVersion`) to that tag. The pin is exact, so a build never picks up a swift-shell this repo's tests did not run against.
2. **The version.** Set `ToolVersion.current` (`sources/model/ToolVersion.swift`) — the one place the version lives; `zfs-tools --version` and `zfs-tools-build --version` both read it.
3. **The golden.** Add `tests/resource/remote_shapes/<version>.txt`: run `swift test`, and `RemoteShapesGoldenTest.testSenderEmitsThisVersionsGolden` fails printing the remote commands this version's sender emits — save them as the new file, one per line. Never edit a released version's file. If the new file differs from the previous version's, the wire changed: a guard that accepts both shapes has to be installed on every receiver before any sender emits the new one, so ship that guard as its own release first. Add to `rejections.txt` any command the change makes worth refusing by name.
4. **The permissions.** If the change runs a `zfs` subcommand or flag the previous release did not, update [Permissions](#permissions) — a sender that needs a new delegation fails on its first real run otherwise.
5. **Green, then tag.** `swift test` locally, push, and wait for CI (`.forgejo/workflows/ci.yml` runs `swift test`: the suite, the golden tests and the source-rules guard). Tag the commit CI ran on, and push the tag.

Versions follow semantic versioning from the operator's chair as well as the importer's: a changed default, a changed meaning of a flag or config key, or anything a consumer of `ZFSToolsModel` must edit to keep compiling is a major.

Before installing a release on hosts that replicate to each other, feed the new version's golden to the guard version still installed on the receivers (and the old golden to the new guard, which step 3's tests already do): the hosts upgrade one at a time, so for a while each version's sender talks to the other's guard.

## References

- [OpenZFS docs](https://openzfs.github.io/openzfs-docs/) · [zfs(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs.8.html) · [zfs-send(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-send.8.html) / [zfs-recv(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-receive.8.html)

## License

Copyright © 2025 Jared Bourgeois — Apache License v2.0 with Runtime Library Exception.

Donations are welcome — BTC `3ACMiYCiknTp4VoSE9Zxc2JnaxmDAMGBqH` · ETH `0xD97F48B5Ab68285c58BD1D11dE87a166A7C4D0b0` · SOL `LW3j5Zv54a8qD7dzZ5KdpfE6UssFAGj48uM1DhJCeSN`
