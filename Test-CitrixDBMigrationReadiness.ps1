<#
.SYNOPSIS
    Pre-flight validation script for Citrix Delivery Controller database migration permissions.

.DESCRIPTION
    This script validates whether the current user/session appears to have the required access
    to migrate a Citrix Delivery Controller to a new SQL database server.

    It does NOT change any Citrix database connection strings.

    It checks:
      - PowerShell elevation
      - Citrix PowerShell snap-in/module availability
      - Availability of Get/Set/Test DB connection commands
      - Ability to read current Citrix DB connections
      - Citrix delegated administrator visibility/effective rights
      - Whether the new DB connection strings are usable via Test-*DBConnection, where available
      - Optional direct SQL connectivity as the current Windows user

.NOTES
    Run from an elevated PowerShell session on a Citrix Delivery Controller.

    This script is intended to be run BEFORE a script that calls Set-*DBConnection.

.PARAMETER SiteDBConnection
    New Site database connection string.

.PARAMETER LoggingDBConnection
    New Logging database connection string. Optional unless using split databases.

.PARAMETER MonitoringDBConnection
    New Monitoring database connection string. Optional unless using split databases.

.PARAMETER SkipSqlClientTest
    Skips the optional direct SQL connectivity test using .NET SqlClient.

.EXAMPLE
    .\Test-CitrixDBMigrationReadiness.ps1 `
        -SiteDBConnection "Server=NEW-SQL;Initial Catalog=CitrixSiteDB;Integrated Security=True"

.EXAMPLE
    .\Test-CitrixDBMigrationReadiness.ps1 `
        -SiteDBConnection "Server=NEW-SQL;Initial Catalog=CitrixSiteDB;Integrated Security=True" `
        -LoggingDBConnection "Server=NEW-SQL;Initial Catalog=CitrixLoggingDB;Integrated Security=True" `
        -MonitoringDBConnection "Server=NEW-SQL;Initial Catalog=CitrixMonitoringDB;Integrated Security=True"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SiteDBConnection,

    [Parameter(Mandatory = $false)]
    [string]$LoggingDBConnection,

    [Parameter(Mandatory = $false)]
    [string]$MonitoringDBConnection,

    [Parameter(Mandatory = $false)]
    [switch]$SkipSqlClientTest,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\temp\CitrixDBMigrationReadiness.csv"
)

# -------------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------------

$Services = @(
    "Log",
    "Monitor",
    "Sf",
    "EnvTest",
    "Broker",
    "Prov",
    "Hyp",
    "Acct",
    "Admin",
    "Config"
)

$Results = New-Object System.Collections.Generic.List[object]

# -------------------------------------------------------------------------
# Helper Functions
# -------------------------------------------------------------------------

function Add-Result {
    param(
        [string]$Category,
        [string]$Check,
        [string]$Status,
        [string]$Details
    )

    $Results.Add([pscustomobject]@{
        Timestamp = Get-Date
        Category  = $Category
        Check     = $Check
        Status    = $Status
        Details   = $Details
    })

    $color = switch ($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }

    Write-Host "[$Status] $Category - $Check : $Details" -ForegroundColor $color
}

function Test-IsElevated {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SqlConnectionAsCurrentUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectionString,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $ConnectionString
        $connection.Open()

        $command = $connection.CreateCommand()
        $command.CommandText = @"
SELECT
    SYSTEM_USER AS SystemUser,
    ORIGINAL_LOGIN() AS OriginalLogin,
    DB_NAME() AS DatabaseName,
    HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'CONNECT') AS HasConnect,
    IS_MEMBER('db_owner') AS IsDbOwner
"@

        $reader = $command.ExecuteReader()

        if ($reader.Read()) {
            $systemUser    = $reader["SystemUser"]
            $originalLogin = $reader["OriginalLogin"]
            $databaseName  = $reader["DatabaseName"]
            $hasConnect    = $reader["HasConnect"]
            $isDbOwner     = $reader["IsDbOwner"]

            Add-Result `
                -Category "SQL" `
                -Check "$Name direct SQL connectivity as current user" `
                -Status "PASS" `
                -Details "Connected to DB '$databaseName' as '$systemUser' / original login '$originalLogin'. CONNECT=$hasConnect, db_owner=$isDbOwner."
        }

        $reader.Close()
        $connection.Close()
    }
    catch {
        Add-Result `
            -Category "SQL" `
            -Check "$Name direct SQL connectivity as current user" `
            -Status "FAIL" `
            -Details $_.Exception.Message
    }
}

function Get-ConnectionStringForService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Service
    )

    switch ($Service) {
        "Log" {
            if (![string]::IsNullOrWhiteSpace($LoggingDBConnection)) {
                return $LoggingDBConnection
            }
            return $SiteDBConnection
        }

        "Monitor" {
            if (![string]::IsNullOrWhiteSpace($MonitoringDBConnection)) {
                return $MonitoringDBConnection
            }
            return $SiteDBConnection
        }

        default {
            return $SiteDBConnection
        }
    }
}

# -------------------------------------------------------------------------
# Start
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Citrix Delivery Controller DB Migration Readiness Check ===" -ForegroundColor Cyan
Write-Host ""

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
Add-Result -Category "Session" -Check "Current Windows identity" -Status "PASS" -Details $currentIdentity

# -------------------------------------------------------------------------
# Check elevation
# -------------------------------------------------------------------------

if (Test-IsElevated) {
    Add-Result -Category "Session" -Check "PowerShell elevation" -Status "PASS" -Details "PowerShell is running elevated."
}
else {
    Add-Result -Category "Session" -Check "PowerShell elevation" -Status "FAIL" -Details "PowerShell is not running elevated. Re-run as Administrator."
}

# -------------------------------------------------------------------------
# Ensure output directory exists
# -------------------------------------------------------------------------

try {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if (!(Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    Add-Result -Category "Output" -Check "Output path" -Status "PASS" -Details $OutputPath
}
catch {
    Add-Result -Category "Output" -Check "Output path" -Status "FAIL" -Details $_.Exception.Message
}

# -------------------------------------------------------------------------
# Load Citrix snap-ins
# -------------------------------------------------------------------------

try {
    Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

    $citrixSnapins = Get-PSSnapin | Where-Object { $_.Name -like "Citrix.*" }

    if ($citrixSnapins) {
        Add-Result `
            -Category "Citrix PowerShell" `
            -Check "Citrix snap-ins loaded" `
            -Status "PASS" `
            -Details (($citrixSnapins.Name | Sort-Object) -join ", ")
    }
    else {
        Add-Result `
            -Category "Citrix PowerShell" `
            -Check "Citrix snap-ins loaded" `
            -Status "FAIL" `
            -Details "No Citrix snap-ins are loaded. Run this on a Delivery Controller or install the Citrix PowerShell SDK."
    }
}
catch {
    Add-Result `
        -Category "Citrix PowerShell" `
        -Check "Citrix snap-ins loaded" `
        -Status "FAIL" `
        -Details $_.Exception.Message
}

# -------------------------------------------------------------------------
# Validate Citrix delegated admin visibility and effective rights
# -------------------------------------------------------------------------

try {
    $effectiveRightsCmd = Get-Command "Get-AdminEffectiveRight" -ErrorAction Stop
    $effectiveRights = & $effectiveRightsCmd -ErrorAction Stop

    if ($effectiveRights) {
        Add-Result `
            -Category "Citrix Delegated Admin" `
            -Check "Effective rights" `
            -Status "PASS" `
            -Details "Current user has $($effectiveRights.Count) effective Citrix delegated admin right object(s)."
    }
    else {
        Add-Result `
            -Category "Citrix Delegated Admin" `
            -Check "Effective rights" `
            -Status "WARN" `
            -Details "Command succeeded, but no effective rights were returned."
    }
}
catch {
    Add-Result `
        -Category "Citrix Delegated Admin" `
        -Check "Effective rights" `
        -Status "FAIL" `
        -Details $_.Exception.Message
}

try {
    $adminCmd = Get-Command "Get-AdminAdministrator" -ErrorAction Stop

    # This may not always return the user directly if access is inherited through AD groups,
    # so failure here should not be treated as absolute failure if Get-AdminEffectiveRight passed.
    $adminRecord = & $adminCmd -Name $currentIdentity -ErrorAction SilentlyContinue

    if ($adminRecord) {
        Add-Result `
            -Category "Citrix Delegated Admin" `
            -Check "Administrator record" `
            -Status "PASS" `
            -Details "Found direct Citrix administrator record for $currentIdentity."
    }
    else {
        Add-Result `
            -Category "Citrix Delegated Admin" `
            -Check "Administrator record" `
            -Status "WARN" `
            -Details "No direct administrator record found for $currentIdentity. This may be normal if rights are inherited through an AD group."
    }
}
catch {
    Add-Result `
        -Category "Citrix Delegated Admin" `
        -Check "Administrator record" `
        -Status "WARN" `
        -Details $_.Exception.Message
}

# -------------------------------------------------------------------------
# Check command availability and ability to read existing DB connections
# -------------------------------------------------------------------------

foreach ($service in $Services) {
    $getCommandName  = "Get-$($service)DBConnection"
    $setCommandName  = "Set-$($service)DBConnection"
    $testCommandName = "Test-$($service)DBConnection"

    try {
        Get-Command $getCommandName -ErrorAction Stop | Out-Null
        Add-Result -Category "Citrix Commands" -Check "$getCommandName available" -Status "PASS" -Details "Command found."
    }
    catch {
        Add-Result -Category "Citrix Commands" -Check "$getCommandName available" -Status "FAIL" -Details "Command not found."
    }

    try {
        Get-Command $setCommandName -ErrorAction Stop | Out-Null
        Add-Result -Category "Citrix Commands" -Check "$setCommandName available" -Status "PASS" -Details "Command found."
    }
    catch {
        Add-Result -Category "Citrix Commands" -Check "$setCommandName available" -Status "FAIL" -Details "Command not found."
    }

    try {
        Get-Command $testCommandName -ErrorAction Stop | Out-Null
        Add-Result -Category "Citrix Commands" -Check "$testCommandName available" -Status "PASS" -Details "Command found."
    }
    catch {
        Add-Result -Category "Citrix Commands" -Check "$testCommandName available" -Status "WARN" -Details "Command not found. This service may not expose a Test-*DBConnection cmdlet in this SDK/version."
    }

    try {
        $getCmd = Get-Command $getCommandName -ErrorAction Stop
        $currentConnection = & $getCmd -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($currentConnection)) {
            Add-Result `
                -Category "Current Citrix DB Connection" `
                -Check "$service current DB connection" `
                -Status "WARN" `
                -Details "Command succeeded, but returned a blank/null connection string."
        }
        else {
            Add-Result `
                -Category "Current Citrix DB Connection" `
                -Check "$service current DB connection" `
                -Status "PASS" `
                -Details "Successfully read current DB connection."
        }
    }
    catch {
        Add-Result `
            -Category "Current Citrix DB Connection" `
            -Check "$service current DB connection" `
            -Status "FAIL" `
            -Details $_.Exception.Message
    }
}

# -------------------------------------------------------------------------
# Test proposed new DB connection strings using Citrix Test-*DBConnection
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Testing proposed Citrix DB connection strings ===" -ForegroundColor Cyan
Write-Host ""

foreach ($service in $Services) {
    $testCommandName = "Test-$($service)DBConnection"
    $targetConnectionString = Get-ConnectionStringForService -Service $service

    if ([string]::IsNullOrWhiteSpace($targetConnectionString)) {
        Add-Result `
            -Category "Citrix DB Preflight" `
            -Check "$service proposed DB connection" `
            -Status "FAIL" `
            -Details "No connection string was provided for this service."
        continue
    }

    try {
        $testCmd = Get-Command $testCommandName -ErrorAction Stop

        $testResult = & $testCmd -DBConnection $targetConnectionString -ErrorAction Stop

        if ($null -eq $testResult) {
            Add-Result `
                -Category "Citrix DB Preflight" `
                -Check "$service proposed DB connection" `
                -Status "PASS" `
                -Details "$testCommandName completed successfully. No result object was returned."
        }
        else {
            Add-Result `
                -Category "Citrix DB Preflight" `
                -Check "$service proposed DB connection" `
                -Status "PASS" `
                -Details "$testCommandName completed. Result: $($testResult | Out-String)"
        }
    }
    catch {
        Add-Result `
            -Category "Citrix DB Preflight" `
            -Check "$service proposed DB connection" `
            -Status "FAIL" `
            -Details $_.Exception.Message
    }
}

# -------------------------------------------------------------------------
# Optional direct SQL tests as current Windows user
# -------------------------------------------------------------------------

if ($SkipSqlClientTest) {
    Add-Result `
        -Category "SQL" `
        -Check "Direct SQL connectivity tests" `
        -Status "WARN" `
        -Details "Skipped by request."
}
else {
    Write-Host ""
    Write-Host "=== Optional direct SQL connectivity tests as current user ===" -ForegroundColor Cyan
    Write-Host ""

    Test-SqlConnectionAsCurrentUser -ConnectionString $SiteDBConnection -Name "Site DB"

    if (![string]::IsNullOrWhiteSpace($LoggingDBConnection)) {
        Test-SqlConnectionAsCurrentUser -ConnectionString $LoggingDBConnection -Name "Logging DB"
    }

    if (![string]::IsNullOrWhiteSpace($MonitoringDBConnection)) {
        Test-SqlConnectionAsCurrentUser -ConnectionString $MonitoringDBConnection -Name "Monitoring DB"
    }
}

# -------------------------------------------------------------------------
# Export results
# -------------------------------------------------------------------------

try {
    $Results | Export-Csv -Path $OutputPath -NoTypeInformation -Force

    Add-Result `
        -Category "Output" `
        -Check "CSV report" `
        -Status "PASS" `
        -Details "Report written to $OutputPath"
}
catch {
    Add-Result `
        -Category "Output" `
        -Check "CSV report" `
        -Status "FAIL" `
        -Details $_.Exception.Message
}

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan

$failCount = ($Results | Where-Object { $_.Status -eq "FAIL" }).Count
$warnCount = ($Results | Where-Object { $_.Status -eq "WARN" }).Count
$passCount = ($Results | Where-Object { $_.Status -eq "PASS" }).Count

Write-Host "PASS: $passCount" -ForegroundColor Green
Write-Host "WARN: $warnCount" -ForegroundColor Yellow
Write-Host "FAIL: $failCount" -ForegroundColor Red
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "Readiness result: NOT READY" -ForegroundColor Red
    Write-Host "Review failed checks before running the migration script." -ForegroundColor Red
    exit 1
}
elseif ($warnCount -gt 0) {
    Write-Host "Readiness result: READY WITH WARNINGS" -ForegroundColor Yellow
    Write-Host "Review warnings before running the migration script." -ForegroundColor Yellow
    exit 2
}
else {
    Write-Host "Readiness result: READY" -ForegroundColor Green
    exit 0
}
