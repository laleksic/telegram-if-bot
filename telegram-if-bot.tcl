package require http
package require tls
package require json

::http::register https 443 ::tls::socket

set botToken [lindex $argv 0]
set terpCommandLine ""
foreach arg [lreplace $argv 0 0] {
	append terpCommandLine "\"[string map {\" \\\"} $arg]\" "
}

puts "Telegram bot token: $botToken"
   
# Validate telegram bot token
set url "https://api.telegram.org/bot$botToken/getMe"  
set http [::http::geturl $url]
set json [::http::data $http]
set data [::json::json2dict $json]
set ok [dict get $data ok]    

if {!$ok} {
    error "Invalid bot token."
}

puts "Interpreter command line: $terpCommandLine"
set terp [open "|$terpCommandLine" r+]

set lastUpdateId 0
set sessionStarted no
set sessionChatId 0

proc getUpdates {} {
	global lastUpdateId
	global botToken

	set json "{
		\"offset\": [expr {$lastUpdateId + 1}],
		\"timeout\": 100
	}"

	set http [::http::geturl "https://api.telegram.org/bot$botToken/getUpdates" -type "application/json" -query $json]
	set json [::http::data $http]
	set data [::json::json2dict $json]
	return $data
}

proc sendMessage {chatId text} {
	global botToken

	if {[string trim $text] == ""} {
		return
	}

	set json "{
		\"chat_id\": $chatId,
		\"text\": \"[string map {\" \\\"} $text]\"
	}"

	set http [::http::geturl "https://api.telegram.org/bot$botToken/sendMessage" -type "application/json" -query $json]
	set json [::http::data $http]
	set data [::json::json2dict $json]
	set ok [dict get $data ok]

	if {!$ok} {
		error "Telegram API error $json."
	}
}

proc terpRead {} {
	global terp

	set text ""
	
	while 1 {
		set line [gets $terp]
		if {[eof $terp]} {
			close $terp
			exit
		} elseif {[string equal $line "\x03"]} {
			break
		} else {
			append text $line\n
		}
	}

	return [string trim $text]
}

proc terpWrite {cmd} {
	global terp

	puts $terp $cmd
	if {[eof $terp]} {
		close $terp
		exit
	}	
	flush $terp
	if {[eof $terp]} {
		close $terp
		exit
	}
}

# Main loop

while 1 {
	global lastUpdateId
	global terp
	global sessionStarted
	global sessionChatId

	set data [getUpdates]
	set ok [dict get $data ok]

	if {!$ok} {
		error "Telegram API error."
	}

	set result [dict get $data result]
	foreach update $result {
		set updateId [dict get $update update_id]
		if {$updateId >= $lastUpdateId} {
			set lastUpdateId $updateId
		}

		if {[dict exists $update message]} {
			set message [dict get $update message]
			if {[dict exists $message text]} {
				set text [dict get $message text]
				set chat [dict get $message chat]
				set chatId [dict get $chat id]

				if {$sessionStarted} {
					if {$chatId == $sessionChatId} {
						if {[string index $text 0] == ">"} {
							set text [string range $text 1 end]
							puts "Command: $text"
							terpWrite $text
							sendMessage $chatId [terpRead]							
						}
					} 
				} else {
					puts "Starting session"
					sendMessage $chatId [terpRead]
					set sessionStarted yes
					set sessionChatId $chatId
				}
			}
		}
	}
}
