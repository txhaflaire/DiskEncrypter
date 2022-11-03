#!/bin/bash

# Created by Thijs Xhaflaire, Jamf on 01/10/2022
# Modified on 28/10/2022

## Managed Preferences
## The function readSetting is reading the settingsPlist and the configured key, if there is no key value pair then we are using the $2 default value.
settingsPlist="/Library/Managed Preferences/com.custom.diskencrypter.plist"

readSetting() {
# $1: key
# $2: default (optional)
local key=$1
local defaultValue=$2

if ! value=$( /usr/libexec/PlistBuddy -c "Print :$key" "$settingsPlist" 2>/dev/null ); then
    value="$defaultValue"
fi
echo "$value"
}

readSettingsFile(){
## Read the rest of the settings and set defaults

## USER NOTIFICATION SETTINGS
## This script will use the 'swiftDialog' tool to display an information window to the end-user about the event.  A signed and notarised version of this application can be downloaded from https://github.com/bartreardon/swiftDialog/releases and should be present on the device in order for it to be used.
## Set whether which notifications you want to generate to the end user.
## "yes" = the user will be notified
## "no" = the user will not be notified and actions will be skipped
notifyUser=$( readSetting notifyUser "yes" )
notifyUserHint=$( readSetting notifyUserHint "yes" )

## Set to yes to configure a download and installtion of swiftDialog if the binary is not installed at the notificationApp location
downloadSwiftDialog=$( readSetting downloadSwiftDialog "yes" )

## General swiftDialog Settings
notificationApp=$( readSetting notificationApp "/usr/local/bin/dialog" )

## swiftDialog Customization ##
companyName=$( readSetting companyName "Jamf" )
iconPath=$( readSetting iconPath "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns" )

## General text section
title=$( readSetting title "Unencrypted Removable Media Device detected" )

subTitlePassword=$( readSetting subTitlePassword "Writing files to unencrypted removable media devices is not allowed, encrypt the disk in order to allow writing files. securely store the password and in case of loss the data will be unaccesible!" )
mainButtonLabelPassword=$( readSetting mainButtonLabelPassword "Continue" )

subTitleConversion=$( readSetting subTitleConversion "Writing files to unencrypted removable media devices is not allowed, encrypt the disk in order to allow writing files. we need to convert this volume to APFS before encryption. Securely store the password and in case of loss the data will be unaccesible!" )
mainButtonLabelConversion=$( readSetting mainButtonLabelConversion "Convert" )

subTitleEXFAT=$( readSetting subTitleEXFAT "Writing files to unencrypted removable media devices is not allowed, encrypt the disk in order to allow writing files. As this volume type does not support conversion or encryption we need to erase the volume. all existing content will be erased!!!. Securely store the password and in case of loss the data will be unaccesible!" )
mainButtonLabelEXFAT=$( readSetting mainButtonLabelEXFAT "Erase existing data and encrypt" )

exitButtonLabel=$( readSetting exitButtonLabel "Eject" )

## Password text and REGEX requirements
secondTitlePassword=$( readSetting secondTitlePassword "Enter the password you want to use to encrypt the removable media" )
placeholderPassword=$( readSetting placeholderPassword "Enter password here" )
secondaryButtonLabelPassword=$( readSetting secondaryButtonLabelPassword "Mount as read-only" )
passwordRegex=$( readSetting passwordRegex "^[^\s]{4,}$" )
passwordRegexErrorMessage=$( readSetting passwordRegexErrorMessage "The provided password does not meet the requirements, please use at leasts 4 characters" )

## Hint text and REGEX requirements
subTitleHint=$( readSetting subTitleHint "Optionally you can specify a hint, a password hint is a sort of reminder that helps the user remember their password." )
mainButtonLabelHint=$( readSetting mainButtonLabelHint "Encrypt" )
secondaryButtonLabelHint=$( readSetting secondaryButtonLabelHint "Encrypt w/o hint" )
secondTitleHint=$( readSetting secondTitleHint "Enter the hint you want to set" )
placeholderHint=$( readSetting placeholderHint "Enter hint here" )
hintRegex=$( readSetting hintRegex "^[^\s]{6,}$" )
hintRegexErrorMessage=$( readSetting hintRegexErrorMessage "The provided hint does not meet the requirements, please use a stronger hint that contains 6 characters" )

## Progress bar text
titleProgress=$( readSetting titleProgress "Disk Encryption Progress" )
subTitleProgress=$( readSetting subTitleProgress "Please wait while the external disk is being encrypted." )
mainButtonLabelProgress=$( readSetting mainButtonLabelProgress "Exit" )

}

###########################################
############ Do not edit below ############
###########################################

## Script variables
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
ExternalDisks=$(diskutil list external physical | grep "/dev/disk" | awk '{print $1}')

readSettingsFile 

	## Check if the mounted External Disk is external, physical and continue
	if [[ -z $ExternalDisks ]]; then
		echo "no external disks mounted"
		exit 0
	else
		## Echo external disk mounted
		echo "external disk mounted"

		## Loop through Storage Volume Types
		StorageType=$(diskutil list $ExternalDisks)

		if [[ $StorageType =~ "Apple_APFS" ]]; then
			echo "The external media volume type is APFS"
			StorageType='APFS'
			
			## Check the DiskID of the APFS container and report the encryption state
			DiskID=$(diskutil list $ExternalDisks | grep -o '\(Container disk[0-9s]*\)' | awk '{print $2}')
			echo "Disk ID is $DiskID"
			FileVaultStatus=$(diskutil apfs list $DiskID | grep "FileVault:" | awk '{print $2}')
			
			## If the APFS Container is not encrypted, run workflow
			if [ $StorageType == "APFS" ] && [ $FileVaultStatus == "Yes" ]; then
				echo "FileVault is enabled on $DiskID, exiting.."
				exit 0
			else
				echo "FileVault is disabled on $DiskID, running encryption workflow"
					
				# Mounting disk as read-only
				diskutil unmountDisk "$DiskID"s1
				diskutil mount readonly "$DiskID"s1

				# Downloading and installing swiftDialog if not existing
				if [[ "$downloadSwiftDialog" == "yes" ]] && [[ ! -f "$notificationApp" ]]; then
	
					echo "swiftDialog not installed, downloading and installing"
					
					LOCATION=$(/usr/bin/curl -s https://api.github.com/repos/bartreardon/swiftDialog/releases/latest | grep browser_download_url | grep .pkg | grep -v debug | awk '{ print $2 }' | sed 's/,$//' | sed 's/"//g')
					/usr/bin/curl -L $LOCATION -o /tmp/swiftDialog.pkg
					/usr/sbin/installer -pkg /tmp/swiftDialog.pkg -target /
					/bin/rm /tmp/swiftDialog.pkg
	
				fi
				
				## Generate notification and ask for password for encryption or mount volume as read-only
				if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]] && [[ "$FileVaultStatus" == "No" ]]; then
					dialog=$(/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$title" --message "$subTitlePassword" --button1text "$mainButtonLabelPassword" --button2text "$secondaryButtonLabelPassword" --infobuttontext "$exitButtonLabel" --quitoninfo --icon "$iconPath" --textfield "$secondTitlePassword",prompt="$placeholderPassword",regex="$passwordRegex",regexerror="$passwordRegexErrorMessage",secure=true,required=yes)
				fi
				
				case $? in
					0)
					Password=$(echo "$dialog" | grep "$secondTitlePassword" | awk -F " : " '{print $NF}' &)
					
					## Generate notification and ask if we want to specify a hint
					if [[ "$notifyUserHint" == "yes" ]] && [[ -f "$notificationApp" ]] && [[ "$FileVaultStatus" == "No" ]]; then				
						Passphrase=$(/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$title" --message "$subTitleHint" --button1text "$mainButtonLabelHint" --button2text "$secondaryButtonLabelHint" --icon "$iconPath" --textfield "$secondTitleHint",prompt="$placeholderHint",regex="$hintRegex",regexerror="$hintRegexErrorMessage" | grep "$secondTitleHint" | awk -F " : " '{print $NF}' &)
					fi
				
					## Start the encryption of the disk with the provided password, optionally we are configuring a hint as well.
					if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]] && [[ "$Password" != "" ]]; then
							
							/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$titleProgress" --message "$subTitleProgress" --icon "$iconPath"  --button1text "$mainButtonLabelProgress" --timer 12 &

							diskutil unmountDisk "$DiskID"s1
							diskutil mount "$DiskID"s1						
							diskutil apfs encryptVolume "$DiskID"s1 -user "disk" -passphrase "$Password"
							
                            ## If the optional hint has been configured we are going to configure it here after encrypting the disk
							if [ "$Passphrase" != "" ]; then
								sleep 5
								diskutil unmountDisk $DiskID
								diskutil apfs unlockVolume "$DiskID"s1 -passphrase "$Password"
								diskutil apfs setPassphraseHint "$DiskID"s1 -user "disk" -hint "$Passphrase"
							fi							
							exit 0	
					fi
					;;
					2)
					echo "$loggedInUser decided mounting $DiskID as read-only"
					diskutil unmountDisk "$DiskID"s1
					diskutil mount readonly "$DiskID"s1
					exit 2
					;;
					3)
					echo "$loggedInUser dediced to eject $DiskID"
					diskutil unmountDisk "$DiskID"s1
					exit 3
				esac
			 fi
		elif [[ $StorageType =~ "Apple_HFS" ]]; then
			echo "The external media type is $StorageType"
			StorageType="HFS"
			
			# Check Encryption State
            DiskID="$ExternalDisks"
			echo "Disk ID is $DiskID"
			FileVaultStatus=$(diskutil list $DiskID | grep "FileVault:" | awk '{print $2}')

            ## In case of HFS container, we need to convert it to APFS and have it encrypted
			if [ $StorageType == "HFS" ]; then

				# Mounting disk as read-only
				diskutil unmountDisk "$DiskID"
				diskutil mount readonly "$DiskID"s2

				# Downloading and installing swiftDialog if not existing
				if [[ "$downloadSwiftDialog" == "yes" ]] && [[ ! -f "$notificationApp" ]]; then
	
					echo "swiftDialog not installed, downloading and installing"
					
					LOCATION=$(/usr/bin/curl -s https://api.github.com/repos/bartreardon/swiftDialog/releases/latest | grep browser_download_url | grep .pkg | grep -v debug | awk '{ print $2 }' | sed 's/,$//' | sed 's/"//g')
					/usr/bin/curl -L $LOCATION -o /tmp/swiftDialog.pkg
					/usr/sbin/installer -pkg /tmp/swiftDialog.pkg -target /
					/bin/rm /tmp/swiftDialog.pkg
	
				fi

				## Generate notification and ask for password for encryption or mount volume as read-only
				if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]]; then
					dialog=$(/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$title" --message "$subTitleConversion" --button1text "$mainButtonLabelConversion" --button2text "$secondaryButtonLabelPassword" --infobuttontext "$exitButtonLabel" --quitoninfo --icon "$iconPath" --textfield "$secondTitlePassword",prompt="$placeholderPassword",regex="$passwordRegex",regexerror="$passwordRegexErrorMessage",secure=true,required=yes)
				fi

				case $? in
					0)
					Password=$(echo "$dialog" | grep "$secondTitlePassword" | awk -F " : " '{print $NF}' &)
					
					## Generate notification and ask if we want to specify a hint
					if [[ "$notifyUserHint" == "yes" ]] && [[ -f "$notificationApp" ]]; then				
						Passphrase=$(/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$title" --message "$subTitleHint" --button1text "$mainButtonLabelHint" --button2text "$secondaryButtonLabelHint" --icon "$iconPath" --textfield "$secondTitleHint",prompt="$placeholderHint",regex="$hintRegex",regexerror="$hintRegexErrorMessage" | grep "$secondTitleHint" | awk -F " : " '{print $NF}' &)
					fi
				
					## Start the encryption of the disk with the provided password, optionally we are configuring a hint as well.
					if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]] && [[ "$Password" != "" ]]; then
														
							/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$titleProgress" --message "$subTitleProgress" --icon "$iconPath"  --button1text $mainButtonLabelProgress --timer 12 &

							diskutil unmountDisk "$DiskID"s2
							diskutil mount "$DiskID"s2
							diskutil apfs convert "$DiskID"s2

							DiskID=$(diskutil list $ExternalDisks | grep -o '\(Container disk[0-9s]*\)' | awk '{print $2}')							
							diskutil apfs encryptVolume "$DiskID"s1 -user "disk" -passphrase "$Password"
								
							## If the optional hint has been configured we are going to configure it here after encrypting the disk
							if [ "$Passphrase" != "" ]; then
								sleep 5
								diskutil unmountDisk $DiskID
								diskutil apfs unlockVolume "$DiskID"s1 -passphrase "$Password"
								diskutil apfs setPassphraseHint "$DiskID"s1 -user "disk" -hint "$Passphrase"
							fi	
							exit 0
					fi
					;;
					2)
					echo "$loggedInUser decided mounting $DiskID as read-only"
					diskutil unmountDisk "$DiskID"
					diskutil mount readonly "$DiskID"s2
					exit 2
					;;
					3)
					echo "$loggedInUser dediced to eject $DiskID"
					diskutil unmountDisk "$DiskID"
					exit 3
				esac
            fi
		elif [[ $StorageType =~ "Microsoft Basic Data" ]]; then
			echo "The external media type is Microsoft Basic Data"
			StorageType="Microsoft Basic Data"
			
			# Check Encryption State
            DiskID="$ExternalDisks"
			echo "Disk ID is $DiskID"
			volumeName=$(diskutil info "$DiskID"s2 | grep "Volume Name" | awk '{print $3}')

            ## In case of EXFAT volume, we need to erase it, reformat to APFS and encrypt it
			if [[ $StorageType == "Microsoft Basic Data" ]]; then

				# Mounting disk as read-only
				diskutil unmountDisk "$DiskID"
				diskutil mount readonly "$DiskID"s2

				# Downloading and installing swiftDialog if not existing
				if [[ "$downloadSwiftDialog" == "yes" ]] && [[ ! -f "$notificationApp" ]]; then
	
					echo "swiftDialog not installed, downloading and installing"
					
					LOCATION=$(/usr/bin/curl -s https://api.github.com/repos/bartreardon/swiftDialog/releases/latest | grep browser_download_url | grep .pkg | grep -v debug | awk '{ print $2 }' | sed 's/,$//' | sed 's/"//g')
					/usr/bin/curl -L $LOCATION -o /tmp/swiftDialog.pkg
					/usr/sbin/installer -pkg /tmp/swiftDialog.pkg -target /
					/bin/rm /tmp/swiftDialog.pkg
	
				fi

				## Generate notification and ask for password for encryption or mount volume as read-only
				if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]]; then
					dialog=$(/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$title" --message "$subTitleEXFAT" --button1text "$mainButtonLabelEXFAT" --button2text "$secondaryButtonLabelPassword" --infobuttontext "$exitButtonLabel" --quitoninfo --icon "$iconPath" --textfield "$secondTitlePassword",prompt="$placeholderPassword",regex="$passwordRegex",regexerror="$passwordRegexErrorMessage",secure=true,required=yes)  #| grep "$secondTitlePassword" | awk -F " : " '{print $NF}' &)
				fi

				case $? in
					0)
					Password=$(echo "$dialog" | grep "$secondTitlePassword" | awk -F " : " '{print $NF}' &)
					
					## Generate notification and ask if we want to specify a hint
					if [[ "$notifyUserHint" == "yes" ]] && [[ -f "$notificationApp" ]]; then				
						Passphrase=$(/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$title" --message "$subTitleHint" --button1text "$mainButtonLabelHint" --button2text "$secondaryButtonLabelHint" --icon "$iconPath" --textfield "$secondTitleHint",prompt="$placeholderHint",regex="$hintRegex",regexerror="$hintRegexErrorMessage" | grep "$secondTitleHint" | awk -F " : " '{print $NF}' &)
					fi
            
					## Start the erase and encryption of the disk with the provided password, optionally we are configuring a hint as well.
					if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]] && [[ "$Password" != "" ]]; then
														
							/usr/bin/sudo -u "$loggedInUser" "$notificationApp" --title "$titleProgress" --message "$subTitleProgress" --icon "$iconPath"  --button1text $mainButtonLabelProgress --timer 12 &							
							diskutil eraseDisk APFS $volumeName "$DiskID" 

							DiskID=$(diskutil list $ExternalDisks | grep -o '\(Container disk[0-9s]*\)' | awk '{print $2}')							
							diskutil apfs encryptVolume "$DiskID"s1 -user "disk" -passphrase "$Password"
							
							## If the optional hint has been configured we are going to configure it here after encrypting the disk
							if [ "$Passphrase" != "" ]; then
								sleep 5
								diskutil unmountDisk $DiskID
								diskutil apfs unlockVolume "$DiskID"s1 -passphrase "$Password"
								diskutil apfs setPassphraseHint "$DiskID"s1 -user "disk" -hint "$Passphrase"
							fi
							exit 0
					fi
					;;
					2)
					echo "$loggedInUser decided mounting $DiskID as read-only"
					diskutil unmountDisk "$DiskID"
					diskutil mount readonly "$DiskID"s2
					exit 2
					;;
					3)
					echo "$loggedInUser dediced to eject $DiskID"
					diskutil unmountDisk "$DiskID"
					exit 3
				esac
            fi
		fi
	fi