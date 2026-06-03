<#
.SYNOPSIS
    Reports Citrix hosting and hypervisor connection health indicators.

.DESCRIPTION
    Exports broker hypervisor connections and provisioning schemes where
    available. This helps administrators spot hosting, storage, network, or MCS
    dependency issues before upgrades and image work.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "C:\temp\CitrixHostingConnectionHealth"
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

Write-Host "=== Citrix Hosting Connection Health ===" -ForegroundColor Cyan
Ensure-Folder -Path $OutputFolder
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

$results = New-Object System.Collections.Generic.List[object]

try {
    $connections = @(Invoke-CitrixCommand -CommandName "Get-BrokerHypervisorConnection" -Parameters @{ MaxRecordCount = 100000 })
    $connections | Export-Csv -Path (Join-Path $OutputFolder "BrokerHypervisorConnections.csv") -NoTypeInformation -Force

    foreach ($connection in $connections) {
        $results.Add([pscustomobject]@{
            Area    = "BrokerHypervisorConnection"
            Name    = $connection.Name
            Status  = "PASS"
            Details = "Connection object returned."
        })
    }
}
catch {
    $results.Add([pscustomobject]@{
        Area    = "BrokerHypervisorConnection"
        Name    = "Get-BrokerHypervisorConnection"
        Status  = "FAIL"
        Details = $_.Exception.Message
    })
}

try {
    $hypConnections = @(Invoke-CitrixCommand -CommandName "Get-HypHypervisorConnection" -Parameters @{ MaxRecordCount = 100000 })
    $hypConnections | Export-Csv -Path (Join-Path $OutputFolder "HypHypervisorConnections.csv") -NoTypeInformation -Force

    foreach ($connection in $hypConnections) {
        $results.Add([pscustomobject]@{
            Area    = "HypHypervisorConnection"
            Name    = $connection.Name
            Status  = "PASS"
            Details = "Hyp connection object returned."
        })
    }
}
catch {
    $results.Add([pscustomobject]@{
        Area    = "HypHypervisorConnection"
        Name    = "Get-HypHypervisorConnection"
        Status  = "WARN"
        Details = $_.Exception.Message
    })
}

try {
    $schemes = @(Invoke-CitrixCommand -CommandName "Get-ProvScheme" -Parameters @{ MaxRecordCount = 100000 })
    $schemes | Export-Csv -Path (Join-Path $OutputFolder "ProvisioningSchemes.csv") -NoTypeInformation -Force

    foreach ($scheme in $schemes) {
        $results.Add([pscustomobject]@{
            Area    = "ProvisioningScheme"
            Name    = $scheme.ProvisioningSchemeName
            Status  = "PASS"
            Details = "Provisioning scheme returned."
        })
    }
}
catch {
    $results.Add([pscustomobject]@{
        Area    = "ProvisioningScheme"
        Name    = "Get-ProvScheme"
        Status  = "WARN"
        Details = $_.Exception.Message
    })
}

$results | Export-Csv -Path (Join-Path $OutputFolder "HostingHealthSummary.csv") -NoTypeInformation -Force

foreach ($result in $results) {
    $color = switch ($result.Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }

    Write-Host "[$($result.Status)] $($result.Area) - $($result.Name): $($result.Details)" -ForegroundColor $color
}

if (($results | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0) {
    exit 1
}
elseif (($results | Where-Object { $_.Status -eq "WARN" }).Count -gt 0) {
    exit 2
}

exit 0
