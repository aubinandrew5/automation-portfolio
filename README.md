**C_Drive_Cleanup.ps1**
Powershell script to scan all virtual desktops and clean up temp files.

Instructions:
1. Run C_Drive_Cleanup.ps1 as an administrator.
2. Output will be stored in C:\ZZ.

_Note:  Locations can be added/removed if necessary._


**C_Drive_Expansion.ps1**
PowerShell script to expand C: drive on desktops in a virtual environment.

Instructions:
1. Place C_Drive_Expansion.ps1 file to a local location on your desktop.  (Example:  create a folder in the root of C: and name it ZZ and place the file in there.)
2. Expand the drive(s) in virtual desktop manager.
3. Open PowerShell as an administrator.
4. Change the directory to the location of the script.  (Example:  cd C:\ZZ)
5. Run the following command:  .\C_Drive_Expansion.ps1 -ComputerName "Desktop_Name".  Replace "Desktop Name" with the name of the desktop.  You can list as many names as you want, separated by commas.  (Example:  "Desktop_Name1","Desktop_Name2","Desktop_Name3"
6. Type in your administrator username and password when prompted.
7. Once complete, run the following command to check the drive space on each desktop:  
Get-Volume C | Select-Object DriveLetter, FileSystemLabel, @{N="SizeGB";E={[math]::Round($_.Size/1GB,2)}}, @{N="FreeGB";E={[math]::Round($_.SizeRemaining/1GB,2)}}, @{N="UsedGB";E={[math]::Round(($_.Size-$_.SizeRemaining)/1GB,2)}}, @{N="PercentFree";E={[math]::Round(($_.SizeRemaining/$_.Size)*100,1)}}

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------

