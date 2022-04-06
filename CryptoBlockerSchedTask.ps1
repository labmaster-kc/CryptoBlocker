<#----------------------------------------------------------
	Script:		CryptoBlockerSchedTask.ps1
	Version: 	v20220405
	Comments:	Creates scheduled task that runs Crypto Blocker script daily for pattern updates.
	Author:		labmaster-kc

    Additional Config files - none
----------------------------------------------------------#>
<#VARIABLE DECLARATION#>
##	General settings for the scheduled task
    $TaskName = "Update CryptoBlocker"
    $TaskDesc = "2022.04.05 labmaster - Script to install FSRM and build CryptoBlocker policies based on internet pattern list.  Re-run the script to update pattern list." 
    $Trigger= New-ScheduledTaskTrigger -Daily -At 8pm
    $User= "NT AUTHORITY\SYSTEM"
##	------------------------------------------------------------------------------------------------
<#END VARIABLE DECLARATION#>


##-------------------------------------------
##	Function:	Main Code Block
##	Purpose:	Configures Scheduled Task according to variables
##				
##-------------------------------------------

##-------------------------------------------
## Build a scheduled task

$Action= New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "C:\Scripts\FSRMCryptoBlocker\DeployCryptoBlocker.ps1"

Register-ScheduledTask -TaskPath "\CompanyFolder\" -TaskName $TaskName -Trigger $Trigger -User $User -Action $Action -Description $TaskDesc

                            
