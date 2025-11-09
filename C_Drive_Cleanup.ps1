# VM Disk Space Scanner and Cleaner
# Scans VMs for low disk space and cleans temporary files

# Configuration
$diskThreshold = 11  # Percentage free space threshold
$outputDir = "C:\ZZ"
$logFile = Join-Path $outputDir "VM_Cleanup_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Create output directory if it doesn't exist
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Paths to clean (supports wildcards)
$pathsToClean = @(
    "C:\Program Files\Adobe\ARM\*",
    "C:\Windows\appcompat\backupTest\Upload0.txt",
    "C:\Windows\ccmcache\*",
    "C:\ProgramData\VMware\VDM\Dumps\*",
    "C:\`$Recycle.Bin\*",
    "C:\Users\*\AppData\LocalLow\Adobe\Acrobat DC\ConnectorIcons",
    "C:\Users\*\AppData\Local\Temp\*",
    "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Service Worker\CacheStorage\*",
    "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data\*"
)

# Function to get VM list (modify based on your environment)
function Get-LowDiskVMs {
    $lowDiskVMs = @()
    
    # Example using Get-VM (VMware)
    # Uncomment and modify based on your virtualization platform
    # $vms = Get-VM | Where-Object {$_.PowerState -eq "PoweredOn"}
    
    # Example using Get-ADComputer (if VMs are domain-joined)
    # $vms = Get-ADComputer -Filter * -SearchBase "OU=VirtualMachines,DC=domain,DC=com"
    
    # For testing: Get computers from a list or use localhost
    $vms = @($env:COMPUTERNAME)  # Replace with your VM collection method
    
    foreach ($vm in $vms) {
        try {
            $disk = Get-WmiObject Win32_LogicalDisk -ComputerName $vm -Filter "DeviceID='C:'" -ErrorAction Stop
            $percentFree = ($disk.FreeSpace / $disk.Size) * 100
            
            if ($percentFree -lt $diskThreshold) {
                $lowDiskVMs += [PSCustomObject]@{
                    VMName = $vm
                    PercentFree = [math]::Round($percentFree, 2)
                    FreeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                    TotalSizeGB = [math]::Round($disk.Size / 1GB, 2)
                }
            }
        }
        catch {
            Write-Warning "Unable to check disk space on $vm : $_"
        }
    }
    
    return $lowDiskVMs
}

# Function to clean files on remote VM
function Clear-VMFiles {
    param(
        [string]$ComputerName,
        [array]$Paths
    )
    
    $totalFreed = 0
    $results = @()
    
    foreach ($path in $Paths) {
        try {
            # Convert local path to UNC path
            $uncPath = "\\$ComputerName\" + $path.Replace(":", "$")
            
            # Get size before deletion
            $itemsBefore = Get-ChildItem -Path $uncPath -Recurse -Force -ErrorAction SilentlyContinue
            $sizeBefore = ($itemsBefore | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            
            if ($sizeBefore -gt 0) {
                # Remove items
                Remove-Item -Path $uncPath -Recurse -Force -ErrorAction SilentlyContinue
                $sizeFreedMB = [math]::Round($sizeBefore / 1MB, 2)
                $totalFreed += $sizeFreedMB
                
                $results += "  ✓ Cleaned: $path ($sizeFreedMB MB)"
            }
        }
        catch {
            $results += "  ✗ Failed: $path - $($_.Exception.Message)"
        }
    }
    
    return [PSCustomObject]@{
        Results = $results
        TotalFreedMB = $totalFreed
    }
}

# Main Script
Write-Host "`n=== VM Disk Space Scanner and Cleaner ===" -ForegroundColor Cyan
Write-Host "Started: $(Get-Date)" -ForegroundColor Gray
Write-Host "Threshold: Less than $diskThreshold% free space`n" -ForegroundColor Gray

# Start logging
"VM Disk Space Scanner and Cleaner - $(Get-Date)" | Out-File $logFile
"Threshold: Less than $diskThreshold% free space`n" | Out-File $logFile -Append

# Step 1: Scan for VMs with low disk space
Write-Host "Scanning VMs for low disk space..." -ForegroundColor Yellow
$lowDiskVMs = Get-LowDiskVMs

if ($lowDiskVMs.Count -eq 0) {
    Write-Host "No VMs found with less than $diskThreshold% free space." -ForegroundColor Green
    "No VMs found with less than $diskThreshold% free space." | Out-File $logFile -Append
    exit
}

Write-Host "Found $($lowDiskVMs.Count) VM(s) with low disk space:`n" -ForegroundColor Red
$lowDiskVMs | Format-Table -AutoSize | Out-String | Write-Host

# Save flagged VMs to file
$flaggedVMsFile = Join-Path $outputDir "Flagged_VMs_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$lowDiskVMs | Export-Csv -Path $flaggedVMsFile -NoTypeInformation
Write-Host "Flagged VMs saved to: $flaggedVMsFile`n" -ForegroundColor Gray

# Step 2: Clean files on each VM
Write-Host "Beginning cleanup process...`n" -ForegroundColor Yellow

foreach ($vm in $lowDiskVMs) {
    Write-Host "Processing: $($vm.VMName)" -ForegroundColor Cyan
    Write-Host "  Current Free Space: $($vm.PercentFree)% ($($vm.FreeSpaceGB) GB)" -ForegroundColor Gray
    
    "`nProcessing: $($vm.VMName)" | Out-File $logFile -Append
    "  Current Free Space: $($vm.PercentFree)% ($($vm.FreeSpaceGB) GB)" | Out-File $logFile -Append
    
    $cleanupResult = Clear-VMFiles -ComputerName $vm.VMName -Paths $pathsToClean
    
    $cleanupResult.Results | ForEach-Object { 
        Write-Host $_
        $_ | Out-File $logFile -Append
    }
    
    Write-Host "  Total Space Freed: $($cleanupResult.TotalFreedMB) MB`n" -ForegroundColor Green
    "  Total Space Freed: $($cleanupResult.TotalFreedMB) MB" | Out-File $logFile -Append
    
    # Check disk space again
    try {
        $diskAfter = Get-WmiObject Win32_LogicalDisk -ComputerName $vm.VMName -Filter "DeviceID='C:'"
        $percentFreeAfter = [math]::Round(($diskAfter.FreeSpace / $diskAfter.Size) * 100, 2)
        $freeSpaceGBAfter = [math]::Round($diskAfter.FreeSpace / 1GB, 2)
        
        Write-Host "  New Free Space: $percentFreeAfter% ($freeSpaceGBAfter GB)" -ForegroundColor Green
        "  New Free Space: $percentFreeAfter% ($freeSpaceGBAfter GB)" | Out-File $logFile -Append
    }
    catch {
        Write-Warning "  Unable to verify final disk space"
    }
    
    Write-Host ""
}

Write-Host "=== Cleanup Complete ===" -ForegroundColor Cyan
Write-Host "Log file: $logFile" -ForegroundColor Gray
Write-Host "Completed: $(Get-Date)`n" -ForegroundColor Gray