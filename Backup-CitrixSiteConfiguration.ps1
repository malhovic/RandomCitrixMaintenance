<#
.SYNOPSIS
    Creates an admin-readable backup snapshot of common Citrix site configuration.

.DESCRIPTION
    This is not a SQL database backup. It exports current Citrix configuration
    objects to CSV and CLIXML so administrators have a reference point before
    upgrades, database migrations, and maintenance activity.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "C:\temp\CitrixSiteConfigBackup"
)

function Ensure-Folder {
    param([string]$Path)

    if (!(Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-CitrixData {
    param(
        [string]$CommandName,
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

function Save-DataSet {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    $csvPath = Join-Path $OutputFolder "$Name.csv"
    $xmlPath = Join-Path $OutputFolder "$Name.clixml"

    try {
        $data = @(& $ScriptBlock)
        $data | Export-Csv -Path $csvPath -NoTypeInformation -Force
        $data | Export-Clixml -Path $xmlPath -Force
        Write-Host "Saved $Name" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed saving ${Name}: $($_.Exception.Message)"
    }
}

Write-Host "=== Citrix Site Configuration Backup ===" -ForegroundColor Cyan
Ensure-Folder -Path $OutputFolder
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

Save-DataSet -Name "Catalogs" -ScriptBlock { Get-CitrixData -CommandName "Get-BrokerCatalog" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "DeliveryGroups" -ScriptBlock { Get-CitrixData -CommandName "Get-BrokerDesktopGroup" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "Applications" -ScriptBlock { Get-CitrixData -CommandName "Get-BrokerApplication" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "ApplicationGroups" -ScriptBlock { Get-CitrixData -CommandName "Get-BrokerApplicationGroup" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "Machines" -ScriptBlock { Get-CitrixData -CommandName "Get-BrokerMachine" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "Tags" -ScriptBlock { Get-CitrixData -CommandName "Get-BrokerTag" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "Administrators" -ScriptBlock { Get-CitrixData -CommandName "Get-AdminAdministrator" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "AdminRoles" -ScriptBlock { Get-CitrixData -CommandName "Get-AdminRole" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "AdminScopes" -ScriptBlock { Get-CitrixData -CommandName "Get-AdminScope" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "HostingConnections" -ScriptBlock { Get-CitrixData -CommandName "Get-BrokerHypervisorConnection" -Parameters @{ MaxRecordCount = 100000 } }
Save-DataSet -Name "RebootSchedules" -ScriptBlock { Get-CitrixData -CommandName "Get-BrokerRebootScheduleV2" -Parameters @{ MaxRecordCount = 100000 } }

Save-DataSet -Name "DBConnections" -ScriptBlock {
    $services = "Log", "Monitor", "Sf", "EnvTest", "Broker", "Prov", "Hyp", "Acct", "Admin", "Config"

    foreach ($service in $services) {
        $commandName = "Get-$($service)DBConnection"
        try {
            $parameters = @{}
            if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
                $parameters["AdminAddress"] = $AdminAddress
            }

            [pscustomobject]@{
                Service      = $service
                DBConnection = & (Get-Command $commandName -ErrorAction Stop) @parameters -ErrorAction Stop
                Status       = "OK"
                Error        = $null
            }
        }
        catch {
            [pscustomobject]@{
                Service      = $service
                DBConnection = $null
                Status       = "Error"
                Error        = $_.Exception.Message
            }
        }
    }
}

Write-Host "Configuration backup complete: $OutputFolder" -ForegroundColor Cyan
