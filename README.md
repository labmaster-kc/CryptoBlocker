CryptoBlocker
==============

This is a solution to block users infected with different ransomware variants.

The script will install File Server Resource Manager (FSRM), and set up the relevant configuration.

<i><b>UPDATED VERSION:</b> This fork uses most of the original logic, but re-writes significant portions of the original script using native Powershell commands.  Native Powershell cmdlets are used to parse JSON.  Commands that use filescrn.exe (depricated) are replaced with native FSRM Powershell commands.</i>

<b>Script Deployment Steps</b>

<i><b>NOTE:</b> Before running, please add any known good file extensions used in your environment to SkipList.txt, one per line.  This will ensure that if a filescreen is added to the list in the future that blocks that specific file extension, your environment won't be affected as they will be automatically removed.  If SkipList.txt does not exist, it will be created automatically.</i>

1. Checks for FSRM, installs if needed
    a. Global configuration of FSRM email and notification settings
2. Checks for network shares
6. Creates a File Group in FSRM containing malicious extensions and filenames (pulled from https://fsrm.experiant.ca/api/v1/get)
7. Creates a File Screen Template in FSRM utilising this File Group, with email and event notification
8. Creates File Screens utilising this template for each drive containing network shares

<b> How it Works</b>

If the user attempts to write a malicious file (as described in the filescreen) to a protected network share, FSRM will prevent the file from being written and send an email to the configured administrators notifying them of the user and file location where the attempted file write occured.

<b>NOTE: This will NOT stop variants which use randomised file extensions, don't drop README files, etc</b>

<b>Usage</b>

Configure the variables at the beginning of the script, and run the script.  You can easily use this script to deploy the required FSRM install, configuration and needed blocking scripts across many file servers.

An event will be logged by FSRM to the Event Viewer (Source = SRMSVC, Event ID = 8215), showing who tried to write a malicious file and where they tried to write it. Use your monitoring system of choice to raise alarms, tickets, etc for this event and respond accordingly.

<i><b>NOTE:</b> An additional script is provided to create a Scheduled Task, which runs the Crypto Blocker Deployment script daily for pattern udpates.  It runs the whole script (including checking for FSRM), but the script is fairly fast.</i>

<i><b>NOTE:</b> The original script is checked for override files (SkipList.txt, ProtectList.txt, IncludeList.txt) in multiple locations.  This script only recognizes override files in the same folder as the main script.</i>

<b>SkipList.txt</b>

By default, this script will protect against all patterns from the internet pattern list. If you would like to override this, you can create a <tt>SkipList.txt</tt> file in the script's running directory. The contents of this file should be the patterns you would like to exclude, one per line.

<b>ProtectList.txt</b>

By default, this script will enumarate all the shares running on the server and add protections for them. If you would like to override this, you can create a <tt>ProtectList.txt</tt> file in the script's running directory. The contents of this file should be the folders you would like to protect, one per line. If this file exists, only the folders listed in it will be protected. If the file is empty or only has invalid entries, there will be no protected folders.

<b>IncludeList.txt</b>

Sometimes you have file screens that you want to add that are not included in the download from Experiant. In this case, you can simply create a file named <tt>IncludeList.txt</tt> and put the screens you would like to add, one per line. If this file does not exist, only the screens from Experiant are included.

<b>Disclaimer</b>

This script is provided as is.  I can not be held liable if this does not thwart a ransomware infection, causes your server to spontaneously combust, results in job loss, etc.
