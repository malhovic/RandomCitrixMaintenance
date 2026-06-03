<#
.SYNOPSIS
    Reports Citrix VDA registration health.

.DESCRIPTION
    Exports registered and unregistered VDA state with catalog, delivery group,
    power state, maintenance mode, session count, agent version, and last
    connection details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$CatalogName,

    [Parameter(Mandatory = $false)]
    [string]$DesktopGroupName,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\temp\CitrixVDARegistrationHealth.csv"
)

function Invoke-CitrixCommand {
    param([string]$CommandName, [hashtable]$Parameters = @{})

    $command = Get-Command $CommandName -ErrorAction Stop
    if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
        $Parameters["AdminAddress"] = $AdminAddress
    }

    return & $command @Parameters -ErrorAction Stop
}

Write-Host "=== Citrix VDA Registration Health ===" -ForegroundColor Cyan
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

$parameters = @{ MaxRecordCount = 100000 }
if (![string]::IsNullOrWhiteSpace($CatalogName)) {
    $parameters["CatalogName"] = $CatalogName
}
if (![string]::IsNullOrWhiteSpace($DesktopGroupName)) {
    $parameters["DesktopGroupName"] = $DesktopGroupName
}

$machines = @(Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters $parameters)

$report = $machines | Select-Object `
    MachineName,
    DNSName,
    CatalogName,
    DesktopGroupName,
    RegistrationState,
    PowerState,
    InMaintenanceMode,
    SessionCount,
    AgentVersion,
    OSType,
    LastConnectionTime,
    LastDeregistrationReason,
    LastDeregistrationTime

$outputDir = Split-Path -Path $OutputPath -Parent
if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | Export-Csv -Path $OutputPath -NoTypeInformation -Force

$registeredCount = @($machines | Where-Object { $_.RegistrationState -eq "Registered" }).Count
$unregisteredCount = $machines.Count - $registeredCount

Write-Host "Registered VDAs: $registeredCount" -ForegroundColor Green
Write-Host "Not registered VDAs: $unregisteredCount" -ForegroundColor Yellow
Write-Host "VDA registration report written to $OutputPath" -ForegroundColor Cyan

if ($unregisteredCount -gt 0) {
    exit 2
}

exit 0
