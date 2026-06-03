[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SiteDBConnection,

    [Parameter(Mandatory = $false)]
    [string]$LoggingDBConnection,

    [Parameter(Mandatory = $false)]
    [string]$MonitoringDBConnection,

    [Parameter(Mandatory = $false)]
    [string]$BackupPath = "C:\temp\CurrentCitrixDBConnections.txt",

    [Parameter(Mandatory = $false)]
    [switch]$SplitDatabase,

    [Parameter(Mandatory = $false)]
    [switch]$SingleDatabase
)

if ($SplitDatabase -and $SingleDatabase) {
    throw "Use either -SplitDatabase or -SingleDatabase, not both."
}

# Load Citrix modules
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

# Standard list of Citrix FMA Services
$services = @(
    "Log", "Monitor", "Sf", "EnvTest", "Broker", 
    "Prov", "Hyp", "Acct", "Admin", "Config"
)

$tempDir = Split-Path -Path $BackupPath -Parent
$outputFile = $BackupPath
$splitDBs = $false

# -------------------------------------------------------------------------
# PHASE 1: Capture current connection info
# -------------------------------------------------------------------------
Write-Host "=== PHASE 1: Capturing Current Connection Strings ===" -ForegroundColor Cyan

# Ensure backup directory exists
if (![string]::IsNullOrWhiteSpace($tempDir) -and !(Test-Path -Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null 
}

# Clear previous file if it exists
Clear-Content $outputFile -ErrorAction SilentlyContinue

Write-Host "Querying services and saving to $outputFile..."

# Gather connections to check for split DBs
try {
    $brokerConn  = Get-BrokerDBConnection -ErrorAction SilentlyContinue
    $logConn     = Get-LogDBConnection -ErrorAction SilentlyContinue
    $monitorConn = Get-MonitorDBConnection -ErrorAction SilentlyContinue

    # Compare connections (PowerShell string comparison is case-insensitive by default).
    if ($SplitDatabase) {
        $splitDBs = $true
        Write-Host "`n[!] Split database mode selected by parameter." -ForegroundColor Magenta
    } elseif ($SingleDatabase) {
        $splitDBs = $false
        Write-Host "`n[i] Single database mode selected by parameter." -ForegroundColor Magenta
    } elseif (($brokerConn -ne $logConn) -or ($brokerConn -ne $monitorConn)) {
        $splitDBs = $true
        Write-Host "`n[!] Split database configuration detected." -ForegroundColor Magenta
    } else {
        Write-Host "`n[i] Single database configuration detected." -ForegroundColor Magenta
    }
} catch {
    Write-Host "`n[!] Could not verify if databases are split. Defaulting to Single DB mode." -ForegroundColor Yellow
}

Write-Host ""

foreach ($service in $services) {
    try {
        $cmd = Get-Command "Get-${service}DBConnection" -ErrorAction Stop
        $connection = & $cmd
        
        $line = "$($service.PadRight(15)) : $connection"
        Write-Host $line
        Add-Content -Path $outputFile -Value $line
    } catch {
        $line = "$($service.PadRight(15)) : [Error getting connection or service not installed]"
        Write-Host $line -ForegroundColor Yellow
        Add-Content -Path $outputFile -Value $line
    }
}

Write-Host "`nPhase 1 Complete. Backup saved to $outputFile.`n" -ForegroundColor Green


# -------------------------------------------------------------------------
# PHASE 2: Collect new connection strings
# -------------------------------------------------------------------------
Write-Host "`n=== PHASE 2: Collecting New Connection Strings ===" -ForegroundColor Cyan
Write-Host "Format Example: Server=NEW-SQL-SERVER;Initial Catalog=CitrixSiteDB;Integrated Security=True`n"

if ($splitDBs) {
    if ([string]::IsNullOrWhiteSpace($SiteDBConnection)) {
        $SiteDBConnection = Read-Host "Enter the NEW Site database connection string (for most services)"
    }

    if ([string]::IsNullOrWhiteSpace($LoggingDBConnection)) {
        $LoggingDBConnection = Read-Host "Enter the NEW Logging database connection string"
    }

    if ([string]::IsNullOrWhiteSpace($MonitoringDBConnection)) {
        $MonitoringDBConnection = Read-Host "Enter the NEW Monitoring database connection string"
    }

    if ([string]::IsNullOrWhiteSpace($SiteDBConnection) -or [string]::IsNullOrWhiteSpace($LoggingDBConnection) -or [string]::IsNullOrWhiteSpace($MonitoringDBConnection)) {
        Write-Host "One or more connection strings were left blank. Exiting before changing existing connections." -ForegroundColor Red
        exit 1
    }
} else {
    if ([string]::IsNullOrWhiteSpace($SiteDBConnection)) {
        $SiteDBConnection = Read-Host "Enter the NEW database connection string"
    }

    if ([string]::IsNullOrWhiteSpace($SiteDBConnection)) {
        Write-Host "No connection string provided. Exiting before changing existing connections." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nNew connection strings have been collected. Review the backup at $outputFile before continuing." -ForegroundColor Yellow
Pause


# -------------------------------------------------------------------------
# PHASE 3: Nullify connection strings
# -------------------------------------------------------------------------
Write-Host "`n=== PHASE 3: Nullifying Connection Strings ===" -ForegroundColor Cyan
Write-Host "WARNING: This will sever the Delivery Controller's connection to the database(s)." -ForegroundColor Red
Write-Host "Press CTRL+C to abort if you are not ready." -ForegroundColor Red
Pause

foreach ($service in $services) {
    try {
        $cmd = Get-Command "Set-${service}DBConnection" -ErrorAction Stop
        & $cmd -DBConnection $null -Force
        Write-Host "Successfully nullified: $service"
    } catch {
        Write-Host "Failed to nullify $service : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "`nPhase 3 Complete. Services are now disconnected.`n" -ForegroundColor Green


# -------------------------------------------------------------------------
# PHASE 4: Set new connection strings
# -------------------------------------------------------------------------
Write-Host "`n=== PHASE 4: Setting New Connection Strings ===" -ForegroundColor Cyan

if ($splitDBs) {
    foreach ($service in $services) {
        try {
            $cmd = Get-Command "Set-${service}DBConnection" -ErrorAction Stop
            
            # Apply the specific string based on the service name
            if ($service -eq "Log") {
                & $cmd -DBConnection $LoggingDBConnection -Force
            } elseif ($service -eq "Monitor") {
                & $cmd -DBConnection $MonitoringDBConnection -Force
            } else {
                & $cmd -DBConnection $SiteDBConnection -Force
            }
            Write-Host "Successfully updated: $service"
        } catch {
            Write-Host "Failed to update $service : $($_.Exception.Message)" -ForegroundColor Red
        }
    }

} else {
    foreach ($service in $services) {
        try {
            $cmd = Get-Command "Set-${service}DBConnection" -ErrorAction Stop
            & $cmd -DBConnection $SiteDBConnection -Force
            Write-Host "Successfully updated: $service"
        } catch {
            Write-Host "Failed to update $service : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nPhase 4 Complete. Verifying new connections:`n" -ForegroundColor Green

# Final Verification
foreach ($service in $services) {
    try {
        $cmd = Get-Command "Get-${service}DBConnection" -ErrorAction SilentlyContinue
        $connection = & $cmd
        Write-Host "$($service.PadRight(15)) : $connection" -ForegroundColor Cyan
    } catch {}
}

Write-Host "`nScript execution finished. Please restart Citrix services or reboot the controller." -ForegroundColor Green


