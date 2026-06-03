<#
.SYNOPSIS
    Performs broad readiness checks before a Citrix Virtual Apps and Desktops upgrade.

.DESCRIPTION
    Checks operating system, pending reboot indicators, free disk space, Citrix
    PowerShell availability, controller inventory, database connection visibility,
    VDA registration health, and common site query access.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AdminAddress,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\temp\CitrixUpgradeReadiness.csv",

    [Parameter(Mandatory = $false)]
    [int]$MinimumFreeGB = 10
)

$Results = New-Object System.Collections.Generic.List[object]

function Add-ReadinessResult {
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

function Invoke-CvadCommand {
    param([string]$CommandName, [hashtable]$Parameters = @{})

    $command = Get-Command $CommandName -ErrorAction Stop
    if (![string]::IsNullOrWhiteSpace($AdminAddress)) {
        $Parameters["AdminAddress"] = $AdminAddress
    }

    return & $command @Parameters -ErrorAction Stop
}

function Test-PendingReboot {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )

    foreach ($path in $paths) {
        if ($path -like "*Session Manager") {
            $value = Get-ItemProperty -Path $path -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
            if ($value) {
                return $true
            }
        }
        elseif (Test-Path $path) {
            return $true
        }
    }

    return $false
}

Write-Host "=== Citrix Upgrade Readiness Check ===" -ForegroundColor Cyan

try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Add-ReadinessResult -Category "Operating System" -Check "Version" -Status "PASS" -Details "$($os.Caption) $($os.Version)"
}
catch {
    Add-ReadinessResult -Category "Operating System" -Check "Version" -Status "WARN" -Details $_.Exception.Message
}

try {
    $systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    $freeGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    $status = if ($freeGB -ge $MinimumFreeGB) { "PASS" } else { "WARN" }
    Add-ReadinessResult -Category "Operating System" -Check "System drive free space" -Status $status -Details "$freeGB GB free; threshold is $MinimumFreeGB GB."
}
catch {
    Add-ReadinessResult -Category "Operating System" -Check "System drive free space" -Status "WARN" -Details $_.Exception.Message
}

if (Test-PendingReboot) {
    Add-ReadinessResult -Category "Operating System" -Check "Pending reboot" -Status "WARN" -Details "Pending reboot indicators were found."
}
else {
    Add-ReadinessResult -Category "Operating System" -Check "Pending reboot" -Status "PASS" -Details "No common pending reboot indicators found."
}

try {
    Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue
    $snapins = Get-PSSnapin | Where-Object { $_.Name -like "Citrix.*" }
    if ($snapins) {
        Add-ReadinessResult -Category "Citrix PowerShell" -Check "Snap-ins" -Status "PASS" -Details (($snapins.Name | Sort-Object) -join ", ")
    }
    else {
        Add-ReadinessResult -Category "Citrix PowerShell" -Check "Snap-ins" -Status "FAIL" -Details "No Citrix snap-ins loaded."
    }
}
catch {
    Add-ReadinessResult -Category "Citrix PowerShell" -Check "Snap-ins" -Status "FAIL" -Details $_.Exception.Message
}

try {
    $controllers = @(Invoke-CvadCommand -CommandName "Get-BrokerController" -Parameters @{ MaxRecordCount = 100000 })
    if ($controllers.Count -gt 0) {
        Add-ReadinessResult -Category "Site" -Check "Controllers" -Status "PASS" -Details "$($controllers.Count) controller(s) found: $(($controllers | Select-Object -ExpandProperty DNSName -ErrorAction SilentlyContinue) -join ', ')"
    }
    else {
        Add-ReadinessResult -Category "Site" -Check "Controllers" -Status "FAIL" -Details "No controllers returned."
    }
}
catch {
    Add-ReadinessResult -Category "Site" -Check "Controllers" -Status "FAIL" -Details $_.Exception.Message
}

$siteChecks = @(
    @{ CommandName = "Get-ConfigSite"; Parameters = @{} },
    @{ CommandName = "Get-BrokerCatalog"; Parameters = @{ MaxRecordCount = 1 } },
    @{ CommandName = "Get-BrokerDesktopGroup"; Parameters = @{ MaxRecordCount = 1 } }
)
foreach ($siteCheck in $siteChecks) {
    try {
        Invoke-CvadCommand -CommandName $siteCheck.CommandName -Parameters $siteCheck.Parameters | Out-Null
        Add-ReadinessResult -Category "Site" -Check $siteCheck.CommandName -Status "PASS" -Details "Command completed."
    }
    catch {
        Add-ReadinessResult -Category "Site" -Check $siteCheck.CommandName -Status "FAIL" -Details $_.Exception.Message
    }
}

foreach ($dbCommand in "Get-BrokerDBConnection", "Get-LogDBConnection", "Get-MonitorDBConnection", "Get-AdminDBConnection", "Get-ConfigDBConnection") {
    try {
        $connection = Invoke-CvadCommand -CommandName $dbCommand
        $status = if ([string]::IsNullOrWhiteSpace($connection)) { "WARN" } else { "PASS" }
        $details = if ([string]::IsNullOrWhiteSpace($connection)) { "Blank connection string." } else { "Connection string readable." }
        Add-ReadinessResult -Category "Database" -Check $dbCommand -Status $status -Details $details
    }
    catch {
        Add-ReadinessResult -Category "Database" -Check $dbCommand -Status "FAIL" -Details $_.Exception.Message
    }
}

try {
    $unregistered = @(Invoke-CvadCommand -CommandName "Get-BrokerMachine" -Parameters @{ MaxRecordCount = 100000; Filter = "RegistrationState -ne 'Registered'" })
    if ($unregistered.Count -gt 0) {
        Add-ReadinessResult -Category "VDAs" -Check "Unregistered machines" -Status "WARN" -Details "$($unregistered.Count) machine(s) are not registered."
    }
    else {
        Add-ReadinessResult -Category "VDAs" -Check "Unregistered machines" -Status "PASS" -Details "No unregistered machines returned by Broker."
    }
}
catch {
    Add-ReadinessResult -Category "VDAs" -Check "Unregistered machines" -Status "WARN" -Details $_.Exception.Message
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (![string]::IsNullOrWhiteSpace($outputDir) -and !(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$Results | Export-Csv -Path $OutputPath -NoTypeInformation -Force
Write-Host "Upgrade readiness report written to $OutputPath" -ForegroundColor Cyan

if (($Results | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0) {
    exit 1
}
elseif (($Results | Where-Object { $_.Status -eq "WARN" }).Count -gt 0) {
    exit 2
}

exit 0
