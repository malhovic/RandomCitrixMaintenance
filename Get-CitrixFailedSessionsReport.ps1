<#
.SYNOPSIS
    Exports recent Citrix failed session and connection failure information.

.DESCRIPTION
    Queries broker failure records where available and exports a CSV report.
    Useful before and after upgrades to compare launch/session health.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [int]$Hours = 24,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\temp\CitrixFailedSessions.csv"
)

function Invoke-CitrixCommand {
    param([string]$CommandName, [hashtable]$Parameters = @{})

    $command = Get-Command $CommandName -ErrorAction Stop
    if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
        $Parameters["AdminAddress"] = $AdminAddress
    }

    return & $command @Parameters -ErrorAction Stop
}

Write-Host "=== Citrix Failed Sessions Report ===" -ForegroundColor Cyan
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

$since = (Get-Date).AddHours(-1 * $Hours)
$records = @()

try {
    $records = @(Invoke-CitrixCommand -CommandName "Get-BrokerConnectionLog" -Parameters @{
        MaxRecordCount = 100000
        Filter         = "BrokeringTime -ge '$($since.ToString("o"))' -and BrokeringDuration -eq 0"
    })
}
catch {
    Write-Warning "Get-BrokerConnectionLog filtered query failed: $($_.Exception.Message)"

    try {
        $records = @(Invoke-CitrixCommand -CommandName "Get-BrokerConnectionLog" -Parameters @{ MaxRecordCount = 100000 }) |
            Where-Object { $_.BrokeringTime -ge $since }
    }
    catch {
        Write-Warning "Get-BrokerConnectionLog is unavailable or failed: $($_.Exception.Message)"
        $records = @()
    }
}

$report = $records | Select-Object `
    BrokeringTime,
    UserName,
    MachineName,
    DesktopGroupName,
    CatalogName,
    ClientName,
    BrokeringDuration,
    EstablishmentDuration,
    FailureReason,
    ConnectionFailureReason,
    SessionKey

$outputDir = Split-Path -Path $OutputPath -Parent
if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | Export-Csv -Path $OutputPath -NoTypeInformation -Force

Write-Host "Records exported: $(@($report).Count)" -ForegroundColor Cyan
Write-Host "Failed sessions report written to $OutputPath" -ForegroundColor Cyan

if (@($report).Count -gt 0) {
    exit 2
}

exit 0
