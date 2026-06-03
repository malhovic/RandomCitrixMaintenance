# Citrix Management Scripts

A collection of PowerShell scripts for managing, maintaining, troubleshooting, and automating Citrix environments.

This repository is intended to hold practical administrative scripts for Citrix Virtual Apps and Desktops / Citrix DaaS environments, including Delivery Controller maintenance, database connection management, service validation, environment reporting, and operational support tasks.

> **Important:** These scripts are intended for Citrix administrators. Review and test all scripts in a lab or non-production environment before running them in production.

---

## Scripts

### `Update-CitrixDBConnections.ps1`

Updates Citrix Delivery Controller database connection strings across standard Citrix FMA services.

This script is useful when migrating Citrix databases to a new SQL Server, restoring databases, changing SQL aliases, or repointing a Delivery Controller to updated database connection strings.

---

## What This Script Does

The script performs the database connection update in three major phases:

### Phase 1: Capture Current Connection Strings

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

### Phase 2: Nullify Existing Connection Strings

The script loops through the standard Citrix FMA services and sets each database connection to `$null`.

This temporarily severs the Delivery Controller’s connection to the Citrix database or databases.

The script pauses before this phase and displays a warning so the administrator has a chance to abort before making changes.

---

### Phase 3: Apply New Connection Strings

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

## Safety Considerations

This script makes impactful changes to Delivery Controller database connectivity.

Before running it in production:

* Confirm you have a current backup of the Citrix databases.
* Confirm SQL permissions are correct.
* Confirm the new SQL Server or SQL alias is reachable.
* Confirm the target databases are online.
* Run during a maintenance window.
* Have console or out-of-band access to the Delivery Controller.
* Validate the generated backup file before proceeding past Phase 1.

The script includes pauses before destructive actions, but administrators should still review the script before execution.

---

## Output File

The script writes the original connection strings to:

```powershell
C:\temp\CurrentCitrixDBConnections.txt
```

This file can be used as a reference if the environment needs to be restored to the previous configuration.

---

## Disclaimer

These scripts are provided as-is with no warranty or guarantee. Use at your own risk.

Always validate scripts in a test environment before using them in production.
