<#
.SYNOPSIS
    Exports a broad inventory snapshot of a Citrix Virtual Apps and Desktops site.

.DESCRIPTION
    Collects common site objects that are useful before upgrades, database migrations,
    and maintenance windows. The script is read-only and writes CSV files to an
    output folder.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "C:\temp\CitrixSiteInventory"
)

$ErrorActionPreference = "Continue"

function Initialize-OutputFolder {
    param([string]$Path)

    if (!(Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Invoke-CitrixCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )

    try {
        $command = Get-Command $CommandName -ErrorAction Stop

        if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
            $Parameters["AdminAddress"] = $AdminAddress
        }

        return & $command @Parameters -ErrorAction Stop
    }
    catch {
        Write-Warning "$CommandName failed or is unavailable: $($_.Exception.Message)"
        return @()
    }
}

function Export-Inventory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    $path = Join-Path $OutputFolder "$Name.csv"

    try {
        $data = & $ScriptBlock
        @($data) | Export-Csv -Path $path -NoTypeInformation -Force
        Write-Host "Exported $Name to $path" -ForegroundColor Green
    }
    catch {
        [pscustomobject]@{
            Error = $_.Exception.Message
        } | Export-Csv -Path $path -NoTypeInformation -Force
        Write-Warning "Failed exporting ${Name}: $($_.Exception.Message)"
    }
}

Write-Host "=== Citrix Site Inventory Export ===" -ForegroundColor Cyan
Initialize-OutputFolder -Path $OutputFolder
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

Export-Inventory -Name "Controllers" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-BrokerController" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "Zones" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-ConfigZone" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "MachineCatalogs" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-BrokerCatalog" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "DeliveryGroups" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-BrokerDesktopGroup" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "Machines" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-BrokerMachine" -Parameters @{ MaxRecordCount = 100000 } |
        Select-Object MachineName, DNSName, CatalogName, DesktopGroupName, RegistrationState, PowerState, InMaintenanceMode, SessionCount, AgentVersion, OSType, LastConnectionTime
}

Export-Inventory -Name "Applications" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-BrokerApplication" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "Administrators" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-AdminAdministrator" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "Scopes" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-AdminScope" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "HostingConnections" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-BrokerHypervisorConnection" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "RebootSchedules" -ScriptBlock {
    Invoke-CitrixCommand -CommandName "Get-BrokerRebootScheduleV2" -Parameters @{ MaxRecordCount = 100000 }
}

Export-Inventory -Name "DBConnections" -ScriptBlock {
    $services = "Log", "Monitor", "Sf", "EnvTest", "Broker", "Prov", "Hyp", "Acct", "Admin", "Config"

    foreach ($service in $services) {
        $commandName = "Get-$($service)DBConnection"
        try {
            $parameters = @{}
            if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
                $parameters["AdminAddress"] = $AdminAddress
            }

            $connection = & (Get-Command $commandName -ErrorAction Stop) @parameters -ErrorAction Stop
            [pscustomobject]@{
                Service      = $service
                Command      = $commandName
                DBConnection = $connection
                Status       = "OK"
                Error        = $null
            }
        }
        catch {
            [pscustomobject]@{
                Service      = $service
                Command      = $commandName
                DBConnection = $null
                Status       = "Error"
                Error        = $_.Exception.Message
            }
        }
    }
}

Write-Host "Inventory export complete: $OutputFolder" -ForegroundColor Cyan
