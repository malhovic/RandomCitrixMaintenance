<#
.SYNOPSIS
    Performs common health checks on a Citrix Delivery Controller.

.DESCRIPTION
    Checks elevation, Citrix snap-ins, core Windows services, selected Citrix
    cmdlets, database connection visibility, controller objects, and recent
    Citrix event log errors.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\temp\CitrixControllerHealth.csv",

    [Parameter(Mandatory = $false)]
    [int]$EventLogHours = 24
)

$Results = New-Object System.Collections.Generic.List[object]

function Add-HealthResult {
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
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SdkCommand {
    param(
        [string]$CommandName,
        [hashtable]$Parameters = @{}
    )

    $command = Get-Command $CommandName -ErrorAction Stop
    if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
        $Parameters["AdminAddress"] = $AdminAddress
    }

    return & $command @Parameters -ErrorAction Stop
}

Write-Host "=== Citrix Delivery Controller Health Check ===" -ForegroundColor Cyan

if (Test-IsElevated) {
    Add-HealthResult -Category "Session" -Check "Elevation" -Status "PASS" -Details "PowerShell is elevated."
}
else {
    Add-HealthResult -Category "Session" -Check "Elevation" -Status "WARN" -Details "PowerShell is not elevated."
}

try {
    Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue
    $snapins = Get-PSSnapin | Where-Object { $_.Name -like "Citrix.*" }
    if ($snapins) {
        Add-HealthResult -Category "Citrix PowerShell" -Check "Snap-ins" -Status "PASS" -Details (($snapins.Name | Sort-Object) -join ", ")
    }
    else {
        Add-HealthResult -Category "Citrix PowerShell" -Check "Snap-ins" -Status "FAIL" -Details "No Citrix snap-ins loaded."
    }
}
catch {
    Add-HealthResult -Category "Citrix PowerShell" -Check "Snap-ins" -Status "FAIL" -Details $_.Exception.Message
}

$serviceNamePatterns = "Citrix*"
try {
    $services = Get-Service -Name $serviceNamePatterns -ErrorAction Stop
    foreach ($service in $services) {
        $status = if ($service.Status -eq "Running") { "PASS" } else { "WARN" }
        Add-HealthResult -Category "Windows Services" -Check $service.Name -Status $status -Details $service.Status
    }
}
catch {
    Add-HealthResult -Category "Windows Services" -Check "Citrix services" -Status "WARN" -Details $_.Exception.Message
}

$sdkChecks = @(
    @{ CommandName = "Get-BrokerController"; Parameters = @{ MaxRecordCount = 1 } },
    @{ CommandName = "Get-BrokerMachine"; Parameters = @{ MaxRecordCount = 1 } },
    @{ CommandName = "Get-BrokerDesktopGroup"; Parameters = @{ MaxRecordCount = 1 } },
    @{ CommandName = "Get-ConfigSite"; Parameters = @{} }
)
foreach ($sdkCheck in $sdkChecks) {
    try {
        Invoke-SdkCommand -CommandName $sdkCheck.CommandName -Parameters $sdkCheck.Parameters | Out-Null
        Add-HealthResult -Category "Citrix SDK" -Check $sdkCheck.CommandName -Status "PASS" -Details "Command completed."
    }
    catch {
        Add-HealthResult -Category "Citrix SDK" -Check $sdkCheck.CommandName -Status "FAIL" -Details $_.Exception.Message
    }
}

$dbServices = "Broker", "Log", "Monitor", "Admin", "Config"
foreach ($dbService in $dbServices) {
    $commandName = "Get-$($dbService)DBConnection"
    try {
        $connection = Invoke-SdkCommand -CommandName $commandName
        if ([string]::IsNullOrWhiteSpace($connection)) {
            Add-HealthResult -Category "Database" -Check $commandName -Status "WARN" -Details "Connection string is blank."
        }
        else {
            Add-HealthResult -Category "Database" -Check $commandName -Status "PASS" -Details "Connection string readable."
        }
    }
    catch {
        Add-HealthResult -Category "Database" -Check $commandName -Status "FAIL" -Details $_.Exception.Message
    }
}

try {
    $since = (Get-Date).AddHours(-1 * $EventLogHours)
    $events = Get-WinEvent -FilterHashtable @{ LogName = "Application"; StartTime = $since; Level = 2 } -ErrorAction Stop |
        Where-Object { $_.ProviderName -like "Citrix*" }

    if ($events) {
        Add-HealthResult -Category "Event Logs" -Check "Recent Citrix errors" -Status "WARN" -Details "$(@($events).Count) Citrix Application log error(s) in the last $EventLogHours hour(s)."
    }
    else {
        Add-HealthResult -Category "Event Logs" -Check "Recent Citrix errors" -Status "PASS" -Details "No Citrix Application log errors found in the last $EventLogHours hour(s)."
    }
}
catch {
    Add-HealthResult -Category "Event Logs" -Check "Recent Citrix errors" -Status "WARN" -Details $_.Exception.Message
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$Results | Export-Csv -Path $OutputPath -NoTypeInformation -Force
Write-Host "Health report written to $OutputPath" -ForegroundColor Cyan

if (($Results | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0) {
    exit 1
}
elseif (($Results | Where-Object { $_.Status -eq "WARN" }).Count -gt 0) {
    exit 2
}

exit 0
