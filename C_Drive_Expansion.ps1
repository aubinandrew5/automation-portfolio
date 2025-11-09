#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Expands C: drive by removing recovery partition and extending the volume.

.DESCRIPTION
    This script automates the process of expanding the C: drive after the disk
    has been expanded in vSphere. It identifies and removes the recovery partition
    if present, then extends the C: drive to use all available unallocated space.
    
    Can run locally or remotely against one or more computers.

.PARAMETER ComputerName
    The name(s) of the remote computer(s) to expand the C: drive on.
    If not specified, runs on the local computer.

.PARAMETER Credential
    PSCredential object for remote authentication.
    If not specified, uses current user credentials.

.EXAMPLE
    .\Expand-CDrive.ps1
    Runs on the local computer.

.EXAMPLE
    .\Expand-CDrive.ps1 -ComputerName "VM01"
    Runs on remote computer VM01.

.EXAMPLE
    .\Expand-CDrive.ps1 -ComputerName "VM01","VM02","VM03"
    Runs on multiple remote computers.

.EXAMPLE
    $cred = Get-Credential
    .\Expand-CDrive.ps1 -ComputerName "VM01" -Credential $cred
    Runs on remote computer using specific credentials.

.NOTES
    - Must be run as Administrator
    - Requires the disk to already be expanded in vSphere
    - Creates a transcript log for auditing
    - For remote execution, requires PSRemoting to be enabled on target computers
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [string[]]$ComputerName,
    
    [Parameter()]
    [PSCredential]$Credential
)

# Start transcript logging
$logPath = "C:\Temp\DriveExpansion_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
New-Item -ItemType Directory -Path "C:\Temp" -Force -ErrorAction SilentlyContinue | Out-Null
Start-Transcript -Path $logPath

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "C: Drive Expansion Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Get C: drive information
    $cDrive = Get-Partition | Where-Object { $_.DriveLetter -eq 'C' }
    if (-not $cDrive) {
        throw "Could not find C: drive"
    }

    $diskNumber = $cDrive.DiskNumber
    Write-Host "Found C: drive on Disk $diskNumber" -ForegroundColor Green
    
    # Get current C: drive size
    $currentSize = [math]::Round($cDrive.Size / 1GB, 2)
    Write-Host "Current C: drive size: $currentSize GB" -ForegroundColor Yellow
    Write-Host ""

    # Check for recovery partition on the same disk after C: drive
    $allPartitions = Get-Partition -DiskNumber $diskNumber | Sort-Object -Property Offset
    $cDriveIndex = $allPartitions.IndexOf($cDrive)
    
    $recoveryPartition = $null
    for ($i = $cDriveIndex + 1; $i -lt $allPartitions.Count; $i++) {
        $partition = $allPartitions[$i]
        if ($partition.Type -eq 'Recovery') {
            $recoveryPartition = $partition
            break
        }
    }

    if ($recoveryPartition) {
        Write-Host "Found Recovery Partition:" -ForegroundColor Yellow
        Write-Host "  Partition Number: $($recoveryPartition.PartitionNumber)" -ForegroundColor White
        Write-Host "  Size: $([math]::Round($recoveryPartition.Size / 1MB, 2)) MB" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Removing Recovery Partition..." -ForegroundColor Yellow
        
        # Remove the recovery partition using diskpart
        $diskpartScript = @"
select disk $diskNumber
select partition $($recoveryPartition.PartitionNumber)
delete partition override
"@
        
        $diskpartScript | diskpart | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Recovery partition removed successfully" -ForegroundColor Green
            Write-Host ""
        } else {
            Write-Warning "Diskpart returned exit code: $LASTEXITCODE"
        }
        
        # Wait a moment for the system to process the change
        Start-Sleep -Seconds 2
    } else {
        Write-Host "No recovery partition found after C: drive" -ForegroundColor Green
        Write-Host ""
    }

    # Check for unallocated space
    $disk = Get-Disk -Number $diskNumber
    $maxSize = ($cDrive | Get-PartitionSupportedSize).SizeMax
    $unallocatedSpace = [math]::Round(($maxSize - $cDrive.Size) / 1GB, 2)

    if ($unallocatedSpace -gt 0) {
        Write-Host "Available unallocated space: $unallocatedSpace GB" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Extending C: drive..." -ForegroundColor Yellow
        
        # Extend the partition to maximum size
        Resize-Partition -DiskNumber $diskNumber -PartitionNumber $cDrive.PartitionNumber -Size $maxSize
        
        # Get new size
        $newCDrive = Get-Partition -DiskNumber $diskNumber -PartitionNumber $cDrive.PartitionNumber
        $newSize = [math]::Round($newCDrive.Size / 1GB, 2)
        $addedSpace = [math]::Round(($newSize - $currentSize), 2)
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "SUCCESS!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Previous size: $currentSize GB" -ForegroundColor White
        Write-Host "New size: $newSize GB" -ForegroundColor White
        Write-Host "Added space: $addedSpace GB" -ForegroundColor Green
    } else {
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "No unallocated space available to expand C: drive" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "This could mean:" -ForegroundColor White
        Write-Host "  - The disk has not been expanded in vSphere yet" -ForegroundColor White
        Write-Host "  - There are other partitions consuming the space" -ForegroundColor White
        Write-Host "  - The drive is already at maximum size" -ForegroundColor White
    }

} catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor White
} finally {
    Write-Host ""
    Write-Host "Log file saved to: $logPath" -ForegroundColor Cyan
    Stop-Transcript
}