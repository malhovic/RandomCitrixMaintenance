<#
.SYNOPSIS
    Validates a Citrix Delivery Controller after database connection migration.

.DESCRIPTION
    Confirms expected database connection strings, checks basic site queries,
    verifies controller and VDA visibility, and writes a CSV validation report.
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
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\temp\CitrixPostMigrationValidation.csv"
)

$Results = New-Object System.Collections.Generic.List[object]
$Services = "Log", "Monitor", "Sf", "EnvTest", "Broker", "Prov", "Hyp", "Acct", "Admin", "Config"

function Add-ValidationResult {
    param([string]$Category, [string]$Check, [string]$Status, [string]$Details)

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

function Get-ExpectedConnection {
    param([string]$Service)

    switch ($Service) {
        "Log" {
            if (![string]::IsNullOrWhiteSpace($LoggingDBConnection)) { return $LoggingDBConnection }
            return $SiteDBConnection
        }
        "Monitor" {
            if (![string]::IsNullOrWhiteSpace($MonitoringDBConnection)) { return $MonitoringDBConnection }
            return $SiteDBConnection
        }
        default { return $SiteDBConnection }
    }
}

function Invoke-CitrixCommand {
    param([string]$CommandName, [hashtable]$Parameters = @{})

    $command = Get-Command $CommandName -ErrorAction Stop
    if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
        $Parameters["AdminAddress"] = $AdminAddress
    }

    return & $command @Parameters -ErrorAction Stop
}

Write-Host "=== Citrix Post-Migration Validation ===" -ForegroundColor Cyan
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

foreach ($service in $Services) {
    $commandName = "Get-$($service)DBConnection"
    $expected = Get-ExpectedConnection -Service $service

    try {
        $actual = Invoke-CitrixCommand -CommandName $commandName

        if ($actual -eq $expected) {
            Add-ValidationResult -Category "Database" -Check "$service DB connection" -Status "PASS" -Details "Connection matches expected value."
        }
        else {
            Add-ValidationResult -Category "Database" -Check "$service DB connection" -Status "FAIL" -Details "Connection does not match expected value."
        }
    }
    catch {
        Add-ValidationResult -Category "Database" -Check "$service DB connection" -Status "FAIL" -Details $_.Exception.Message
    }
}

$siteQueries = @(
    @{ CommandName = "Get-ConfigSite"; Parameters = @{} },
    @{ CommandName = "Get-BrokerController"; Parameters = @{ MaxRecordCount = 1 } },
    @{ CommandName = "Get-BrokerCatalog"; Parameters = @{ MaxRecordCount = 1 } },
    @{ CommandName = "Get-BrokerDesktopGroup"; Parameters = @{ MaxRecordCount = 1 } },
    @{ CommandName = "Get-BrokerApplication"; Parameters = @{ MaxRecordCount = 1 } }
)
foreach ($siteQuery in $siteQueries) {
    try {
        Invoke-CitrixCommand -CommandName $siteQuery.CommandName -Parameters $siteQuery.Parameters | Out-Null
        Add-ValidationResult -Category "Site Queries" -Check $siteQuery.CommandName -Status "PASS" -Details "Command completed."
    }
    catch {
        Add-ValidationResult -Category "Site Queries" -Check $siteQuery.CommandName -Status "FAIL" -Details $_.Exception.Message
    }
}

try {
    $controllers = @(Invoke-CitrixCommand -CommandName "Get-BrokerController" -Parameters @{ MaxRecordCount = 100000 })
    Add-ValidationResult -Category "Controllers" -Check "Controller inventory" -Status "PASS" -Details "$($controllers.Count) controller(s) returned."
}
catch {
    Add-ValidationResult -Category "Controllers" -Check "Controller inventory" -Status "FAIL" -Details $_.Exception.Message
}

try {
    $registered = @(Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters @{ MaxRecordCount = 100000; Filter = "RegistrationState -eq 'Registered'" })
    $unregistered = @(Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters @{ MaxRecordCount = 100000; Filter = "RegistrationState -ne 'Registered'" })
    Add-ValidationResult -Category "VDAs" -Check "Registration summary" -Status "PASS" -Details "Registered=$($registered.Count); NotRegistered=$($unregistered.Count)."
}
catch {
    Add-ValidationResult -Category "VDAs" -Check "Registration summary" -Status "WARN" -Details $_.Exception.Message
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$Results | Export-Csv -Path $OutputPath -NoTypeInformation -Force
Write-Host "Post-migration validation report written to $OutputPath" -ForegroundColor Cyan

if (($Results | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0) {
    exit 1
}
elseif (($Results | Where-Object { $_.Status -eq "WARN" }).Count -gt 0) {
    exit 2
}

exit 0
