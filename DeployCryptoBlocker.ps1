<#----------------------------------------------------------
	Script:		DeployCryptoBlocker.ps1
	Version: 	v20220408
	Comments:	Sets up FSRM for Crypto Blocker using pattern list from the internet.
	Author:		labmaster-kc

    Exception Handling - we have 3 ways to handle exceptions (false positives)
    1. (SkipList) Remove the pattern from the main File Group.
        a. That pattern will not be blocked
        b. 5000 other patterns will still be blocked
    2. (ExcludeList) Create an exception for the subfolder (must be a subfolder), and allow all patterns in that exception folder (and tree)
        a. Works really well when an application creates files with random extensions, but always puts them in the same (specific) folder.
        b. Doesn't work well in common folders like C:\Windows\Temp where you don't want to allow all patterns to be written.
    3. (ExceptionList) Create an exception for a specific subfolder and allow specific patterns to be written to that folder.
        a. Very specific
        b. Somewhat complex.  Path, patterns, and JSON need to be correct.

    Additional Config files
    ProtectList.txt:   List of paths that must be protected
    ExcludeList.txt:   Override list of paths that should not be monitored, one entry per line
    SkipList.txt:      List of patterns that should not be monitored, one entry per line
    IncludeList.txt:   Override list of patterns that should be monitored, one entry per line
    ExceptionList.txt: Override list of paths that should not be monitored and specific patterns that are allowed in that path, JSON file
----------------------------------------------------------#>
<#VARIABLE DECLARATION#>
##	Email notification - Used to send email notification to defined administrator
	$computer = $env:computername
	$senderEmail = $computer + ".CryptoBlocker@email.com"									##	From email address
	$senderPassword = ""								##	Password for 'From' email address
	$adminEmail = "email@email.com"					##	Email of administrator to notify
	$smtpServer = "mail.email.com"						##	SMTP server to use when sending email
	$smtpSendPort = ""									##	port used to send SMTP email (587)
	$emailNotificationLimit = 1							##  minimum number of minutes between notifications
	$eventNotificationLimit = 1							##  minimum number of minutes between writing events to the event log
##	------------------------------------------------------------------------------------------------
##	Log file - used to log events detected by $watcher
	$logFile = ""										##	Full path to location where log file will be stored

##	------------------------------------------------------------------------------------------------
# Names to use in FSRM
$fileGroupName = "CryptoBlockerGroup"
$fileTemplateName = "CryptoBlockerTemplate"
$fileTemplateDescription = "Crypto Blocker Template"
# set screening type to
# Active screening: Do not allow users to save unathorized files
$fileScreeningActive = $false
# Passive screening: Allow users to save unathorized files (use for monitoring)
#$fileTemplateType = "Passiv"

# Email config - The message applies to Events too.

$notificationTo = "[Admin Email]"
$notificationSubject = "[Server] CryptoBlocker - [Source File Path] blocked"
$notificationMessage = @'
Server - [Server]
Offending File Path - [Source File Path]
User - [Source Io Owner]
File Screen Path - [File Screen Path]
Process that attempted the write - [Source Process Image]
Process ID - [Source Process Id]
File Group matched - [Violated File Group]
'@

#$notificationMessage = "script - User [Source Io Owner] attempted to save [Source File Path] to [File Screen Path] on the [Server] server. This file is in the [Violated File Group] file group."


<#END VARIABLE DECLARATION#>


##-------------------------------------------
##	Function:	Main Code Block
##	Purpose:	Configures FSRM according to variables
##				
##-------------------------------------------

##-------------------------------------------
# Identify Windows Server version, PowerShell version and install FSRM role
$majorVer = [System.Environment]::OSVersion.Version.Major
$minorVer = [System.Environment]::OSVersion.Version.Minor
$powershellVer = $PSVersionTable.PSVersion.Major

if ($powershellVer -le 2)
{
    Write-Host "`n####"
    Write-Host "ERROR: PowerShell v3 or higher required."
    exit
}

Write-Host "`n####"
Write-Host "Checking File Server Resource Manager.."

Import-Module ServerManager

if ($majorVer -ge 6)
{
    $checkFSRM = Get-WindowsFeature -Name FS-Resource-Manager

    if ($checkFSRM.Installed -eq $True)
    {    Write-Host -BackgroundColor Green -ForegroundColor Black "FSRM is already installed"
    }
    else
    {
        if (($minorVer -ge 2 -or $majorVer -eq 10) -and $checkFSRM.Installed -ne "True")
        {
            # Server 2012 / 2016
            Write-Host "`n####"
            Write-Host "FSRM not found.. Installing (2012 / 2016).."

            $install = Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
	        if ($? -ne $True)
	        {
		        Write-Host "Install of FSRM failed."
		        exit
	        }
        }
        elseif ($minorVer -ge 1 -and $checkFSRM.Installed -ne "True")
        {
            # Server 2008 R2
            Write-Host "`n####"
		    Write-Host "FSRM not found.. Installing (2008 R2).."
            $install = Add-WindowsFeature FS-FileServer, FS-Resource-Manager
	    if ($? -ne $True)
	    {
		    Write-Host "Install of FSRM failed."
		    exit
	    }
	
        }
        elseif ($checkFSRM.Installed -ne "True")
        {
            # Server 2008
            Write-Host "`n####"
		    Write-Host "FSRM not found.. Installing (2008).."
            $install = &servermanagercmd -Install FS-FileServer FS-Resource-Manager
	    if ($? -ne $True)
	    {
		    Write-Host "Install of FSRM failed."
		    exit
	    }
        }

        ##-------------------------------------------
        ## configure global email settings for FSRM
        Write-Host "`n####"
        Write-Host "Processing global email settings.."
        Set-FsrmSetting -FromEmailAddress $senderEmail
        Set-FsrmSetting -AdminEmailAddress $adminEmail
        Set-FsrmSetting -SmtpServer $smtpServer

        Set-FsrmSetting -EmailNotificationLimit $emailNotificationLimit
        Set-FsrmSetting -EventNotificationLimit $eventNotificationLimit
    }
}
else
{
    # Assume Server 2003
    Write-Host "`n####"
	Write-Host "Unsupported version of Windows detected! Quitting.."
    return
}



##-------------------------------------------
## Enumerate shares
## ProtectList.txt overrides share enumeration, has to be in same folder as deploy script
Write-Host "`n####"
Write-Host "Processing ProtectList.."

if (Test-Path $PSScriptRoot\ProtectList.txt)
{
    $drivesContainingShares = Get-Content $PSScriptRoot\ProtectList.txt | ForEach-Object { $_.Trim() }
}
Else {
    $drivesContainingShares =   @(Get-WmiObject Win32_Share | 
                    Select Name,Path,Type | 
                    Where-Object { $_.Type -match '0|2147483648' } | 
                    Select -ExpandProperty Path | 
                    Select -Unique)
}


if ($drivesContainingShares.Count -eq 0)
{
    Write-Host "`n####"
    Write-Host "No drives containing shares were found. Exiting.."
    exit
}

Write-Host "`n####"
Write-Host "The following shares needing to be protected: $($drivesContainingShares -Join ",")"


##-------------------------------------------
## Download list of CryptoLocker file extensions - data held in variable, not written to disk
Write-Host "`n####"
Write-Host "Dowloading CryptoLocker file extensions list from fsrm.experiant.ca api.."

# download the latest extension list - skip the extra code to convert JSON
$monitoredExtensions = (Invoke-WebRequest -Uri "https://fsrm.experiant.ca/api/v1/combined" -UseBasicParsing).content | convertfrom-json | % {$_.filters}



##-------------------------------------------
## Process SkipList.txt - SkipList.txt has to be in same folder as deploy script
Write-Host "`n####"
Write-Host "Processing SkipList.."

If (Test-Path $PSScriptRoot\SkipList.txt)
{
    $Exclusions = Get-Content $PSScriptRoot\SkipList.txt | ForEach-Object { $_.Trim() }
    $monitoredExtensions = $monitoredExtensions | Where-Object { $Exclusions -notcontains $_ }

}
Else 
{
    Write-Host "`n####"
    Write-Host "No SkipList.txt found..."
}


##-------------------------------------------
## Check to see if we have any local patterns to include - IncludeList.txt has to be in same folder as deploy script
Write-Host "`n####"
Write-Host "Processing IncludeList.."

If (Test-Path $PSScriptRoot\IncludeList.txt)
{
    $includeExt = Get-Content $PSScriptRoot\IncludeList.txt | ForEach-Object { $_.Trim() }
    $monitoredExtensions = $monitoredExtensions + $includeExt
}


##-------------------------------------------
## Create the File Group in FSRM based on downloaded list and incude/exclude overrides.
## Delete the File Group if it exists, then add back as a new list
## Original code split the list into 4K chunks (filescrn limitation), and used filescrn.exe (depricated)
# -Confirm:$False
Write-Host "`n####"
Write-Host "Removing and Creating File Group... " $monitoredExtensions.count
$monitoredExtensions = $monitoredExtensions | Sort-Object -Unique
Remove-FsrmFileGroup -Name $fileGroupName -Confirm:$false -ErrorAction SilentlyContinue
New-FsrmFileGroup -Name $fileGroupName -IncludePattern $monitoredExtensions



##-------------------------------------------
## Create Notifications
## TRied using New-FsrmFmjNotificationAction but it doesn't work (invalid object in New-FsrmFileScreenTemplate)
$emailAction = New-FsrmAction -Type Email -MailTo $notificationTo -Subject $notificationSubject -Body $notificationMessage
$eventAction = New-FsrmAction -Type Event -EventType Error -Body $notificationMessage
# create an array of notifications
$fileTemplateNotifications = @()
$fileTemplateNotifications += $emailAction
$fileTemplateNotifications += $eventAction


##-------------------------------------------
## Create File Screen Template with Notification
## Delete the File Screen Template if it exists, then add back as a new template
Write-Host "`n####"
Write-Host "Adding/replacing File Screen Template [$fileTemplateName] with eMail Notification [$EmailNotification] and Event Notification [$EventNotification].."
Remove-FsrmFileScreenTemplate -Name $fileTemplateName -Confirm:$false -ErrorAction SilentlyContinue

New-FsrmFileScreenTemplate -Name $fileTemplateName -Description $fileTemplateDescription -IncludeGroup $fileGroupName -Notification $fileTemplateNotifications


##-------------------------------------------
## Create File Screens from Templates for every share
## Delete the File Screen if it exists, then add back as a new screen
Write-Host "`n####"
Write-Host "Adding/replacing File Screens.."
$drivesContainingShares | ForEach-Object {
    Write-Host "File Screen for [$_] with Source Template [$fileTemplateName].."
    Remove-FsrmFileScreen -Path $_ -Confirm:$false -ErrorAction SilentlyContinue
    New-FsrmFileScreen -Path $_ -Description "Crypto Blocker Screening" -Template $fileTemplateName -Active:$fileScreeningActive
}


##-------------------------------------------
## File Screen Exceptions - ExcludeList.txt
## File Screen Exceptions must apply to subfolders of existing File Screens
## ** For now, allow all patterns in these exception folders
## Delete the File Screen Exception if it exists, then add back as a new screen exception
## Check to see if we have any Folder Exceptions to exclude - ExcludeList.txt has to be in same folder as deploy script
Write-Host "`n####"
Write-Host "Processing ExcludeList.."
If (Test-Path $PSScriptRoot\ExcludeList.txt) {
    Get-Content $PSScriptRoot\ExcludeList.txt | ForEach-Object {
        Write-Host -ForegroundColor Cyan $_
        If (Test-Path $_) {
            Remove-FsrmFileScreenException -Path $_ -Confirm:$false -ErrorAction SilentlyContinue
            New-FsrmFileScreenException -Path $_ -Description "Crypto Blocker Screening Exception" -IncludeGroup $fileGroupName
            #New-FsrmFileScreenException -Path $_ -Description "Crypto Blocker Screening Exception"
        }
    }
}

##-------------------------------------------
## File Screen Exceptions - ExceptionList.txt
## File Screen Exceptions must apply to subfolders of existing File Screens
## ** This is more precise with FileGroups that match exceptions and only "allow" certain files in these exception folders
## Delete the File Screen Exception if it exists, then add back as a new screen exception
## Check to see if we have any Folder Exceptions to exclude - ExceptionList.txt has to be in same folder as deploy script
Write-Host "`n####"
Write-Host "Processing ExceptionList.."
If (Test-Path $PSScriptRoot\ExceptionList.txt) {
    $exceptionList = Get-Content $PSScriptRoot\ExceptionList.txt | ConvertFrom-Json
    foreach ($exception in $exceptionList.exceptions)
    {
        Write-Host -ForegroundColor Yellow $exception.name
        If (Test-Path $exception.path) {
            # Remove and re-create File Groups with patterns specific to this exception path
            Remove-FsrmFileGroup -Name $exception.name -Confirm:$false -ErrorAction SilentlyContinue

            # Get the pattern list, and create a new File Group
            $exceptionPatterns = % {$exception.patterns}
            New-FsrmFileGroup -Name $exception.name -IncludePattern $exceptionPatterns
            
            # Remove and re-create File Scnreen Exception with specific File Group patterns
            Remove-FsrmFileScreenException -Path $exception.path -Confirm:$false -ErrorAction SilentlyContinue
            New-FsrmFileScreenException -Path $exception.path -Description "Crypto Blocker Screening Exception" -IncludeGroup $exception.name
            #New-FsrmFileScreenException -Path $_ -Description "Crypto Blocker Screening Exception"
        }
    }
}




################################ Functions ################################



