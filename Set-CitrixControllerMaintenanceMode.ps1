<#
.SYNOPSIS
    Enables or disables maintenance mode for machines associated with a controller workflow.

.DESCRIPTION
    Finds broker machines by name, catalog, delivery group, or all machines and
    sets InMaintenanceMode. Supports -WhatIf and -Confirm.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$MachineName,

    [Parameter(Mandatory = $false)]
    [string]$CatalogName,

    [Parameter(Mandatory = $false)]
    [string]$DesktopGroupName,

    [Parameter(Mandatory = $false)]
    [switch]$AllMachines,

    [Parameter(Mandatory = $false)]
    [switch]$Disable,

    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\temp\CitrixMaintenanceModeChanges.csv"
)

function Invoke-CitrixCommand {
    param([string]$CommandName, [hashtable]$Parameters = @{})

    $command = Get-Command $CommandName -ErrorAction Stop
    if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
        $Parameters["AdminAddress"] = $AdminAddress
    }

    return & $command @Parameters -ErrorAction Stop
}

function Get-TargetMachines {
    if ($AllMachines) {
        return Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters @{ MaxRecordCount = 100000 }
    }

    if ($MachineName) {
        foreach ($name in $MachineName) {
            Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters @{ MachineName = $name }
        }
        return
    }

    if (![string]::IsNullOrWhiteSpace($CatalogName)) {
        return Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters @{ CatalogName = $CatalogName; MaxRecordCount = 100000 }
    }

    if (![string]::IsNullOrWhiteSpace($DesktopGroupName)) {
        return Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters @{ DesktopGroupName = $DesktopGroupName; MaxRecordCount = 100000 }
    }

    throw "Specify -MachineName, -CatalogName, -DesktopGroupName, or -AllMachines."
}

Write-Host "=== Citrix Maintenance Mode Update ===" -ForegroundColor Cyan
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

$targetState = -not $Disable
$changes = New-Object System.Collections.Generic.List[object]
$machines = @(Get-TargetMachines)

foreach ($machine in $machines) {
    $name = if ($machine.MachineName) { $machine.MachineName } else { $machine.DNSName }
    $action = if ($targetState) { "Enable maintenance mode" } else { "Disable maintenance mode" }

    if ($PSCmdlet.ShouldProcess($name, $action)) {
        try {
            Invoke-CitrixCommand -CommandName "Set-BrokerMachineMaintenanceMode" -Parameters @{
                InputObject       = $machine
                MaintenanceMode   = $targetState
            } | Out-Null

            $status = "Updated"
            $details = "Maintenance mode set to $targetState."
            Write-Host "$name : $details" -ForegroundColor Green
        }
        catch {
            $status = "Error"
            $details = $_.Exception.Message
            Write-Warning "$name : $details"
        }

        $changes.Add([pscustomobject]@{
            Timestamp       = Get-Date
            MachineName     = $name
            CatalogName     = $machine.CatalogName
            DesktopGroup    = $machine.DesktopGroupName
            PreviousState   = $machine.InMaintenanceMode
            RequestedState  = $targetState
            Status          = $status
            Details         = $details
        })
    }
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$changes | Export-Csv -Path $OutputPath -NoTypeInformation -Force
Write-Host "Maintenance mode change report written to $OutputPath" -ForegroundColor Cyan
