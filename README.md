# swift-zfs-tools
## A collection of ZFS tools written in Swift.

Currently supports taking ZFS snapshots, consolidating ZFS snapshots based on time period, and syncing local snapshots to a remote.

Run with `swift-zfs-tools /path/to/config.json`.

---

**Config**

Configure actions (snapshot, consolidate, sync) to perform in a `.json` file. Pass the path as the first command argument. All actions have a `dryRun: Bool` field that will `echo` commands.

Example `config.json` that will take a snapshot, consolidate locally, and sync to remote:

```
{
  "actions": [
    {
      "snapshot": {
        "_0": {
          "path": "snapshotConfig.json"
        }
      }
    },
    {
      "consolidate": {
        "_0": {
          "path": "consolidateConfig.json"
        }
      }
    },
    {
      "sync": {
        "_0": {
          "path": "syncConfig.json"
        }
      }
    }
  ],
  "dateFormat": "yyyyMMdd-HHmmss"
}
```

---

**Snapshot** 

Example `snapshotConfig.json`:

```
{
   "dryRun":false,
   "dateSeparator":"@",
   "dataset":"nas_12tb\\/nas",
   "recursive":true
}
```

---

**Consolidate** 

Example `consolidateConfig.json`:

```
{
  "snapshotsNotConsolidated": [],
  "consolidatePeriod": {
    "upperBound": "20220802-000000",
    "snapshotPeriodBias": {
      "upperBound": {}
    },
    "snapshotPeriods": [
      {
        "snapshots": 7,
        "frequency": [
          {
            "day": {
              "_0": 1
            }
          }
        ]
      },
      {
        "snapshots": 3,
        "frequency": [
          {
            "weekOfYear": {
              "_0": 1
            }
          }
        ]
      },
      {
        "snapshots": 11,
        "frequency": [
          {
            "month": {
              "_0": 1
            }
          }
        ]
      },
      {
        "snapshots": 16,
        "frequency": [
          {
            "month": {
              "_0": 3
            }
          }
        ]
      },
      {
        "snapshots": 10,
        "frequency": [
          {
            "month": {
              "_0": 6
            }
          }
        ]
      }
    ]
  },
  "snapshotDateSeparator": "@",
  "datasetMatch": "path\\/to\\/dataset",
  "dryRun": false
}

```

---

**Syncer** 

Example `syncerConfig.json`:

```
{
  "dryRun": false,
  "snapshotDateSeparator": "@",
  "datasetMatch": "path\\/to\\/dataset",
  "sshKeyPath": "sshKeyPath",
  "sshIP": "sshIP"
}
```

---
