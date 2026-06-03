# Citrix Management Scripts

A collection of PowerShell scripts for managing, maintaining, troubleshooting, and automating Citrix environments.

This repository is intended to hold practical administrative scripts for Citrix Virtual Apps and Desktops / Citrix DaaS environments, including Delivery Controller maintenance, database connection management, service validation, environment reporting, and operational support tasks.

> **Important:** These scripts are intended for Citrix administrators. Review and test all scripts in a lab or non-production environment before running them in production.

---

## Repository Purpose

This repository is designed to serve as a centralized location for Citrix management scripts that can help with:

* Delivery Controller maintenance
* Citrix database connection management
* Environment validation
* Pre-flight checks before major changes
* Operational troubleshooting
* Repeatable administrative tasks
* Citrix FMA service reporting

Scripts in this repository may make changes to Citrix infrastructure. Always review each script before use.

---

## Recommended Workflow

For Citrix Delivery Controller database migrations, use the scripts in this order:

1. Run `Test-CitrixDBMigrationReadiness.ps1`
2. Review the console output and CSV report
3. Resolve any failures or unacceptable warnings
4. Run `Update-CitrixDBConnections.ps1` during a maintenance window
5. Restart Citrix services or reboot the Delivery Controller
6. Validate Studio, Director, VDAs, Machine Catalogs, Delivery Groups, and application/desktop launches

---

## Scripts

| Script                                | Purpose                                                                                   | Impact                   | Recommended Order |
| ------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------ | ----------------- |
| `Test-CitrixDBMigrationReadiness.ps1` | Validates whether the current session/user appears ready to perform a Citrix DB migration | Read-only / non-changing | 1                 |
| `Update-CitrixDBConnections.ps1`      | Migrates a Delivery Controller to new Citrix database connection strings                  | Makes changes            | 2                 |

---

# `Test-CitrixDBMigrationReadiness.ps1`

Performs a pre-flight readiness check before migrating a Citrix Delivery Controller to a new SQL database server.

This script should be run before `Update-CitrixDBConnections.ps1`.

Unlike the migration script, this script does **not** nullify, update, or replace any Citrix database connection strings. It is designed to validate whether the current PowerShell session and user appear to have the required access to safely perform the migration.

---

## What This Script Checks

The readiness script validates:

* Whether PowerShell is running elevated
* Whether Citrix PowerShell snap-ins can be loaded
* Whether the current Windows identity can be detected
* Whether Citrix `Get-*DBConnection` commands are available
* Whether Citrix `Set-*DBConnection` commands are available
* Whether Citrix `Test-*DBConnection` commands are available, where supported
* Whether the current user can read the existing Citrix DB connection strings
* Whether Citrix delegated administrator rights can be queried
* Whether the proposed new database connection string or strings pass Citrix DB connection tests
* Optional direct SQL connectivity as the current Windows user
* CSV report generation

---

## Why This Script Exists

Migrating a Citrix Delivery Controller to a new SQL Server can fail for several reasons, including:

* Missing Citrix PowerShell SDK components
* Running PowerShell without elevation
* Insufficient Citrix delegated administrator rights
* Missing SQL permissions
* Invalid SQL connection strings
* SQL Server connectivity problems
* Split database configurations not being accounted for
* Service-specific Citrix DB test commands not being available in the installed SDK version

The readiness script helps identify these problems before running the actual migration script.

---

## Read-Only / Non-Changing Behavior

This script is intended to be safe for pre-flight validation.

It does **not** run commands like:

```powershell
Set-BrokerDBConnection
Set-LogDBConnection
Set-MonitorDBConnection
```

Instead, it checks whether those commands exist and whether the proposed new connection strings can be tested.

The goal is to confirm readiness without changing the current Delivery Controller configuration.

---

## Usage

### Single Database Configuration

```powershell
.\Test-CitrixDBMigrationReadiness.ps1 `
    -SiteDBConnection "Server=NEW-SQL-SERVER;Initial Catalog=CitrixSiteDB;Integrated Security=True"
```

### Split Database Configuration

```powershell
.\Test-CitrixDBMigrationReadiness.ps1 `
    -SiteDBConnection "Server=NEW-SQL-SERVER;Initial Catalog=CitrixSiteDB;Integrated Security=True" `
    -LoggingDBConnection "Server=NEW-SQL-SERVER;Initial Catalog=CitrixLoggingDB;Integrated Security=True" `
    -MonitoringDBConnection "Server=NEW-SQL-SERVER;Initial Catalog=CitrixMonitoringDB;Integrated Security=True"
```

### Skip Direct SQL Client Test

```powershell
.\Test-CitrixDBMigrationReadiness.ps1 `
    -SiteDBConnection "Server=NEW-SQL-SERVER;Initial Catalog=CitrixSiteDB;Integrated Security=True" `
    -SkipSqlClientTest
```

---

## Output

By default, the script writes a CSV readiness report to:

```powershell
C:\temp\CitrixDBMigrationReadiness.csv
```

The report includes:

* Timestamp
* Category
* Check name
* Status
* Details

Statuses include:

| Status | Meaning                                                    |
| ------ | ---------------------------------------------------------- |
| `PASS` | The check completed successfully                           |
| `WARN` | The check completed, but something should be reviewed      |
| `FAIL` | The check failed and should be remediated before migration |

---

## Exit Codes

The script exits with different codes depending on the result.

| Exit Code | Meaning                                  |
| --------- | ---------------------------------------- |
| `0`       | Ready                                    |
| `1`       | Not ready; one or more failures detected |
| `2`       | Ready with warnings                      |

This allows the script to be used in automation or larger operational workflows.

---

## Readiness Result Guidance

If the readiness result is:

```text
READY
```

the environment appears ready for the migration script.

If the readiness result is:

```text
READY WITH WARNINGS
```

review each warning before proceeding. Some warnings may be acceptable depending on the environment, such as a service-specific `Test-*DBConnection` cmdlet not being available in the installed SDK version.

If the readiness result is:

```text
NOT READY
```

do not run the migration script until the failed checks are remediated.

---

# `Update-CitrixDBConnections.ps1`

Updates Citrix Delivery Controller database connection strings across standard Citrix FMA services.

This script is useful when migrating Citrix databases to a new SQL Server, restoring databases, changing SQL aliases, or repointing a Delivery Controller to updated database connection strings.

> **Run `Test-CitrixDBMigrationReadiness.ps1` before running this script.**

---

## What This Script Does

The script performs the database connection update in three major phases.

---

## Phase 1: Capture Current Connection Strings

The script loads the Citrix PowerShell snap-ins and queries the current database connection strings for the standard Citrix FMA services.

It saves the current connection strings to:

```powershell
C:\temp\CurrentCitrixDBConnections.txt
```

This provides a quick backup/reference before any changes are made.

The script checks whether the environment appears to be using:

* A **single database configuration**
* A **split database configuration** with separate Site, Logging, and Monitoring databases

It does this by comparing the Broker, Logging, and Monitoring database connection strings.

---

## Phase 2: Nullify Existing Connection Strings

The script loops through the standard Citrix FMA services and sets each database connection to `$null`.

This temporarily severs the Delivery Controller’s connection to the Citrix database or databases.

The script pauses before this phase and displays a warning so the administrator has a chance to abort before making changes.

---

## Phase 3: Apply New Connection Strings

After the existing connection strings are nullified, the script prompts the administrator for the new database connection string or strings.

For a **single database configuration**, the script prompts for one connection string and applies it to all supported services.

For a **split database configuration**, the script prompts for:

* Site database connection string
* Logging database connection string
* Monitoring database connection string

It then applies the appropriate connection string to each Citrix FMA service.

After updating the services, the script verifies the new connection strings by querying each service again.

---

## Citrix Services Included

The script attempts to manage the following Citrix FMA services:

```powershell
Log
Monitor
Sf
EnvTest
Broker
Prov
Hyp
Acct
Admin
Config
```

For each service, the script dynamically attempts to run the matching Citrix PowerShell commands, such as:

```powershell
Get-BrokerDBConnection
Set-BrokerDBConnection
Get-MonitorDBConnection
Set-MonitorDBConnection
```

If a service is not installed or the command is unavailable, the script records an error and continues.

---

## Requirements

* PowerShell
* Citrix Delivery Controller PowerShell snap-ins
* Local administrator rights on the Delivery Controller
* Citrix administrator permissions
* Access to the SQL Server hosting the Citrix databases
* Valid database connection string or strings
* Maintenance window recommended

The script begins by loading Citrix snap-ins:

```powershell
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue
```

---

## Example Connection String

```text
Server=NEW-SQL-SERVER;Initial Catalog=CitrixSiteDB;Integrated Security=True
```

For split database deployments, provide the correct database name for each database:

```text
Server=NEW-SQL-SERVER;Initial Catalog=CitrixSiteDB;Integrated Security=True
Server=NEW-SQL-SERVER;Initial Catalog=CitrixLoggingDB;Integrated Security=True
Server=NEW-SQL-SERVER;Initial Catalog=CitrixMonitoringDB;Integrated Security=True
```

---

## Usage

Run the script from an elevated PowerShell session on a Citrix Delivery Controller.

```powershell
.\Update-CitrixDBConnections.ps1
```

Follow the prompts carefully.

The script will:

1. Capture the current DB connection strings.
2. Save them to `C:\temp\CurrentCitrixDBConnections.txt`.
3. Detect whether the environment uses single or split databases.
4. Pause before nullifying the current database connections.
5. Prompt for the new connection string or strings.
6. Apply the new connection strings.
7. Display the resulting configuration for verification.

---

## Operational Notes

After the script completes, restart the Citrix services or reboot the Delivery Controller.

The script displays the following reminder at completion:

```text
Please restart Citrix services or reboot the controller.
```

This is recommended to ensure all Citrix services fully recognize the updated database connections.

---

# Safety Considerations

These scripts are intended for Citrix administrators and should be used carefully.

Before running the migration script in production:

* Confirm you have current backups of all Citrix databases.
* Confirm SQL permissions are correct.
* Confirm the new SQL Server or SQL alias is reachable.
* Confirm the target databases are online.
* Confirm whether the environment uses single or split databases.
* Run the readiness script first.
* Review the readiness CSV report.
* Run during a maintenance window.
* Have console or out-of-band access to the Delivery Controller.
* Validate the generated backup file before proceeding past Phase 1 of the migration script.

---

# Important Behavior Notes

## `Test-CitrixDBMigrationReadiness.ps1`

This script is designed to be **non-changing**.

It validates the session, Citrix command availability, current connection visibility, proposed DB connection usability, and optional SQL connectivity before migration.

## `Update-CitrixDBConnections.ps1`

This script **does make changes**.

It nullifies existing Citrix DB connection strings before applying new ones. This will temporarily disconnect the Delivery Controller from the Citrix databases.

---

# Disclaimer

These scripts are provided as-is with no warranty or guarantee.

Use at your own risk.

Always validate scripts in a test environment before using them in production.
