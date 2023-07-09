// Command.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

@main
struct Command: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zfs-tools",
        abstract: """
        ZFS snapshot management for the command line.
        
        This toolkit helps you create, manage, and replicate ZFS snapshots with simple
        commands that can be run directly or through configuration files. Perfect for
        automating backups and ensuring your data is protected with minimal effort.
        
        Core features:
          • Create timestamped snapshots with recursive dataset support
          • Smart retention policies that keep the right snapshots and clean up the rest
          • Secure snapshot replication to remote systems
          • Chain commands together for complete backup workflows
        
        I hope you enjoy using zfs-tools! If you find it helpful and would like to show your support, coffee donations are greatly appreciated!
        BTC: 3ACMiYCiknTp4VoSE9Zxc2JnaxmDAMGBqH
        ETH: 0xD97F48B5Ab68285c58BD1D11dE87a166A7C4D0b0
        SOL: LW3j5Zv54a8qD7dzZ5KdpfE6UssFAGj48uM1DhJCeSN
        """,
        usage: """
        
        # Snapshot of a dataset
        zfs-tools snapshot --dataset-grep tank/data
        
        # Create and run a retention policy (daily for a week, weekly for a month, etc.)
        zfs-tools consolidate --dataset-grep tank/data
        
        # Send snapshots to a remote system
        zfs-tools sync --dataset-grep tank/data --ssh-user admin --ssh-ip backup.server.com --ssh-port 22 --ssh-key-path ~/.ssh/id_rsa
        
        # Save a command as a reusable config file
        zfs-tools snapshot-configure --dataset-grep tank/data --recursive --output-path ~/zfs/snapshot.json
        
        # Run a saved config
        zfs-tools snapshot-configured --config-path ~/zfs/snapshot.json
        
        # Chain multiple operations together
        zfs-tools execute-actions --actions-path ~/zfs/daily-backup.json
        """,
        discussion: """
        
        WORKFLOW PATTERNS
          Each command follows a consistent pattern that supports three ways of working:
          • Direct execution with inline arguments
          • Create a reusable JSON config with the *-configure variant
          • Run operations from a config file with the *-configured variant
        
        COMMON OPTIONS \(Arguments.Common.optionGroupTitle)
          --date-format       \(Arguments.Common.dateFormatHelp) [default: yyyyMMdd-HHmmss]
          --date-separator    \(Arguments.Common.dateSeparatorHelp) [default: @]
          --execute           \(Arguments.Common.executeHelp) [default: false (dry-run)]
          --shell-path        \(Arguments.Common.shellPathHelp) [default: /bin/bash]
        
        SNAPSHOT RETENTION POLICIES
          The consolidate command uses a multi-tiered retention strategy. By default:
          • The last 7 daily snapshots are kept
          • One weekly snapshot for the last 3 weeks
          • One monthly snapshot for the last 11 months
          • One yearly snapshot indefinitely
          
          This gives you granular recovery points for recent changes while saving
          space with fewer snapshots as time passes. You can customize these periods
          in JSON config files.
        
        TYPICAL WORKFLOWS
          Simple backup routine:
          1. snapshot - Create point-in-time backups of important datasets
          2. consolidate - Intelligently manage retention to save space
          3. sync - Copy snapshots to a second system for redundancy
          
          For automation, create config files and add execute-actions to cron:
          
          # Sample actions file (~/zfs/backup.json)
          [
            {"snapshot": {"configPath": "~/zfs/snapshot.json"}},
            {"consolidate": {"configPath": "~/zfs/consolidate.json"}},
            {"sync": {"configPath": "~/zfs/sync.json"}}
          ]
          
          # Add to crontab for nightly backups
          0 1 * * * /usr/local/bin/zfs-tools execute-actions --actions-path ~/zfs/backup.json
        
        EXAMPLES
          # Start with a test run (dry-run is default)
          zfs-tools snapshot --dataset-grep tank/home --recursive
          
          # When ready, add --execute to actually perform operations
          zfs-tools snapshot --dataset-grep tank/home --recursive --execute
          
          # Create separate configs for different dataset groups
          zfs-tools snapshot-configure --dataset-grep tank/home --recursive --output-path ~/zfs/home.json
          zfs-tools snapshot-configure --dataset-grep tank/vms --recursive --output-path ~/zfs/vms.json
          
          # For incremental backups to a remote system
          zfs-tools sync --dataset-grep tank/critical --ssh-user backup --ssh-ip 192.168.1.100 --ssh-port 22 --ssh-key-path ~/.ssh/backup_key --execute
        """,
        version: "1.1.4",
        shouldDisplay: true,
        subcommands: [
            ExecuteActions.self,
            ExecuteActionsConfigure.self,
            Snapshot.self,
            SnapshotConfigure.self,
            SnapshotConfigured.self,
            Consolidate.self,
            ConsolidateConfigure.self,
            ConsolidateConfigured.self,
            Sync.self,
            SyncConfigure.self,
            SyncConfigured.self
        ],
        groupedSubcommands: [],
        defaultSubcommand: ExecuteActionsConfigure.self,
        helpNames: nil,
        aliases: []
    )
}
