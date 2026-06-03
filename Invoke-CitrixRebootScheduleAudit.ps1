<#
.SYNOPSIS
    Audits Citrix reboot schedules and machines that may need restart attention.

.DESCRIPTION
    Exports reboot schedules and a machine reboot-state summary. The script is
    read-only and intended for image-update, upgrade, and recurring maintenance
    review.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "C:\temp\CitrixRebootScheduleAudit"
)

function Ensure-Folder {
    param([string]$Path)

    if (!(Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
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

Write-Host "=== Citrix Reboot Schedule Audit ===" -ForegroundColor Cyan
Ensure-Folder -Path $OutputFolder
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

$schedulePath = Join-Path $OutputFolder "RebootSchedules.csv"
$machinePath = Join-Path $OutputFolder "MachineRebootState.csv"
$summaryPath = Join-Path $OutputFolder "Summary.csv"

try {
    $schedules = @(Invoke-CitrixCommand -CommandName "Get-BrokerRebootScheduleV2" -Parameters @{ MaxRecordCount = 100000 })
}
catch {
    Write-Warning "Get-BrokerRebootScheduleV2 failed or is unavailable: $($_.Exception.Message)"
    $schedules = @()
}

$schedules | Select-Object * | Export-Csv -Path $schedulePath -NoTypeInformation -Force

try {
    $machines = @(Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters @{ MaxRecordCount = 100000 })
}
catch {
    Write-Warning "Get-BrokerMachine failed: $($_.Exception.Message)"
    $machines = @()
}

$machineReport = $machines | Select-Object `
    MachineName,
    DNSName,
    CatalogName,
    DesktopGroupName,
    PowerState,
    RegistrationState,
    InMaintenanceMode,
    SessionCount,
    LastConnectionTime,
    LastHostingUpdateTime

$machineReport | Export-Csv -Path $machinePath -NoTypeInformation -Force

$summary = @(
    [pscustomobject]@{ Metric = "RebootSchedules"; Value = $schedules.Count }
    [pscustomobject]@{ Metric = "Machines"; Value = $machines.Count }
    [pscustomobject]@{ Metric = "RegisteredMachines"; Value = @($machines | Where-Object { $_.RegistrationState -eq "Registered" }).Count }
    [pscustomobject]@{ Metric = "MaintenanceModeMachines"; Value = @($machines | Where-Object { $_.InMaintenanceMode }).Count }
    [pscustomobject]@{ Metric = "MachinesWithSessions"; Value = @($machines | Where-Object { $_.SessionCount -gt 0 }).Count }
)

$summary | Export-Csv -Path $summaryPath -NoTypeInformation -Force

Write-Host "Reboot schedules exported to $schedulePath" -ForegroundColor Green
Write-Host "Machine reboot state exported to $machinePath" -ForegroundColor Green
Write-Host "Summary exported to $summaryPath" -ForegroundColor Green
