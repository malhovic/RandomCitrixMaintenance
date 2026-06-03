# Load Citrix modules
Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue

# Standard list of Citrix FMA Services
$services = @(
    "Log", "Monitor", "Sf", "EnvTest", "Broker", 
    "Prov", "Hyp", "Acct", "Admin", "Config"
)

$tempDir = "C:\temp"
$outputFile = "$tempDir\CurrentCitrixDBConnections.txt"
$splitDBs = $false

# -------------------------------------------------------------------------
# PHASE 1: Capture current connection info
# -------------------------------------------------------------------------
Write-Host "=== PHASE 1: Capturing Current Connection Strings ===" -ForegroundColor Cyan

# Ensure temp directory exists
if (!(Test-Path -Path $tempDir)) { 
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

    # Compare connections (PowerShell string comparison is case-insensitive by default)
    if (($brokerConn -ne $logConn) -or ($brokerConn -ne $monitorConn)) {
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
Pause


# -------------------------------------------------------------------------
# PHASE 2: Nullify connection strings
# -------------------------------------------------------------------------
Write-Host "`n=== PHASE 2: Nullifying Connection Strings ===" -ForegroundColor Cyan
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

Write-Host "`nPhase 2 Complete. Services are now disconnected.`n" -ForegroundColor Green


# -------------------------------------------------------------------------
# PHASE 3: Set new connection strings
# -------------------------------------------------------------------------
Write-Host "`n=== PHASE 3: Setting New Connection Strings ===" -ForegroundColor Cyan
Write-Host "Format Example: Server=NEW-SQL-SERVER;Initial Catalog=CitrixSiteDB;Integrated Security=True`n"

if ($splitDBs) {
    $siteDBString    = Read-Host "Enter the NEW Site database connection string (for most services)"
    $logDBString     = Read-Host "Enter the NEW Logging database connection string"
    $monitorDBString = Read-Host "Enter the NEW Monitoring database connection string"

    if ([string]::IsNullOrWhiteSpace($siteDBString) -or [string]::IsNullOrWhiteSpace($logDBString) -or [string]::IsNullOrWhiteSpace($monitorDBString)) {
        Write-Host "One or more connection strings were left blank. Exiting script to prevent partial configuration." -ForegroundColor Red
        exit
    }

    foreach ($service in $services) {
        try {
            $cmd = Get-Command "Set-${service}DBConnection" -ErrorAction Stop
            
            # Apply the specific string based on the service name
            if ($service -eq "Log") {
                & $cmd -DBConnection $logDBString -Force
            } elseif ($service -eq "Monitor") {
                & $cmd -DBConnection $monitorDBString -Force
            } else {
                & $cmd -DBConnection $siteDBString -Force
            }
            Write-Host "Successfully updated: $service"
        } catch {
            Write-Host "Failed to update $service : $($_.Exception.Message)" -ForegroundColor Red
        }
    }

} else {
    $newDBString = Read-Host "Enter the NEW database connection string"

    if ([string]::IsNullOrWhiteSpace($newDBString)) {
        Write-Host "No connection string provided. Exiting script." -ForegroundColor Red
        exit
    }

    foreach ($service in $services) {
        try {
            $cmd = Get-Command "Set-${service}DBConnection" -ErrorAction Stop
            & $cmd -DBConnection $newDBString -Force
            Write-Host "Successfully updated: $service"
        } catch {
            Write-Host "Failed to update $service : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nPhase 3 Complete. Verifying new connections:`n" -ForegroundColor Green

# Final Verification
foreach ($service in $services) {
    try {
        $cmd = Get-Command "Get-${service}DBConnection" -ErrorAction SilentlyContinue
        $connection = & $cmd
        Write-Host "$($service.PadRight(15)) : $connection" -ForegroundColor Cyan
    } catch {}
}

Write-Host "`nScript execution finished. Please restart Citrix services or reboot the controller." -ForegroundColor Green


