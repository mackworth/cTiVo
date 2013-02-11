#!/usr/bin/osascript
--Applescript to link cTivo to ElGato Turbo sw and hw

--  Based on a script by  Yoav Yerushalmi on 11/20/08.
--  Modified by Hugh Mackworth on 1/31/13
--  Copyright 2013. All rights reserved.

--property logFile : "~/Library/Logs/cTivo.log"
property date_diff : 0
property formatType : ""
property turboAppName : ""

on wait_until_turbo264_idle()
	set startdate to (current date)
	set counter to 0
	tell application turboAppName
		using terms from application "Turbo.264 HD"
			repeat while isEncoding
				set date_diff to (current date) - startdate
				do shell script "echo " & date_diff & " " & counter & "%" & lastErrorCode
				delay 10
				set counter to counter + 1
				if counter > 100 then set counter to 0
			end repeat
		end using terms from
	end tell
	return
end wait_until_turbo264_idle

on run argv
	do shell script "echo start"
	try
		set formatType to first item of argv --Video options = Elgato format name
		if second item of argv = "-i" then
			set customFormat to ""
			set sourcefile to third item of argv --Format name
			set destfile to fourth item of argv
		else
			set customFormat to second item of argv --Other options = custom name
			if third item of argv = "-input" then
				set sourcefile to fourth item of argv --Format name
				set destfile to fifth item of argv
			else
				set sourcefile to third item of argv --Format name
				set destfile to fourth item of argv
			end if
		end if
	on error
		set formatType to "AppleTV"
		set sourcefile to "/Users/hugh/Desktop/COSTCO/tester/There's Something About Mary.mpg"
		set destfile to "/Users/hugh/Desktop/COSTCO/tester/There's Something About Mary.mp4"
		set customFormat to "custom"
	end try
	do shell script "echo " & formatType & "***" & customFormat & "***" & sourcefile & "***" & destfile
	
	try
		tell application "Finder" to set turboAppName to name of application file id "com.elgato.Turbo"
	end try
	if not turboAppName = "" then
		tell application turboAppName to activate
		delay 5
		my wait_until_turbo264_idle()
		tell application turboAppName
			--iPod High/iPod Standard/Sony PSP/ AppleTV/iPhone/YouTube/YouTubeHD/HD720p/ HD1080p/custom
			using terms from application "Turbo.264 HD"
				ignoring case
					if (formatType = "iPodHigh") then
						add file sourcefile with destination destfile exporting as iPod High replacing yes
					else if (formatType = "ipodStandard" or formatType = "ipod") then
						add file sourcefile with destination destfile exporting as iPod Standard replacing yes
					else if (formatType = "Sonypsp" or formatType = "psp") then
						add file sourcefile with destination destfile exporting as Sony PSP replacing yes
					else if (formatType = "appleTV") then
						add file sourcefile with destination destfile exporting as AppleTV replacing yes
					else if (formatType = "iPhone") then
						add file sourcefile with destination destfile exporting as iPhone replacing yes
					else if (formatType = "YouTube") then
						add file sourcefile with destination destfile exporting as YouTube replacing yes
					else if (formatType = "YouTubeHD") then
						add file sourcefile with destination destfile exporting as YouTubeHD replacing yes
					else if (formatType = "HD720p") then
						add file sourcefile with destination destfile exporting as HD720p replacing yes
					else if (formatType = "HD1080p") then
						add file sourcefile with destination destfile exporting as HD1080p replacing yes
					else if (formatType = "custom") then
						add file sourcefile with destination destfile exporting as custom with custom setting customFormat replacing yes
					else
						add file sourcefile with destination destfile with replacing
					end if
					encode with no error dialogs
				end ignoring
			end using terms from
		end tell
		my wait_until_turbo264_idle()
		delay 5
		tell application turboAppName to quit
	else
		do shell script "echo " & (current date) & " : Couldn't find Turbo.264 >>" & logFile
	end if
end run
