DSTAR SMS TOOL
--------------


This perl-script is a demo / proof-of-concept application that shows
the possible use of connecting a 3G USB-dongle on a D-STAR repeater
for sending and receiving text-messages.

It uses the Device::GSM library from CPAN:
http://search.cpan.org/~cosimo/Device-Gsm-1.58/ or search for 
"GSM" on http://cpan.perl.org/


In this setup, the scripts and files are located in /dstar/scripts

Demonstration applications initiated from SMS are:
- send a DSTAR message from a SMS message
- send a local D-STAR message from a SMS message
- "ping": check dstarsms.pl tool (sends back SMS on request)

Demonstrated applications initiated from the D-STAR are:
- send SMS to sysop when D-STAR repeater has rebooted
(based on result of "uptime" command)



As mentioned, this is just a demo / proof of concept application.

Other possible uses are:
- control remote linking/unlinking via SMS
- initiate reboot of server
- initiate reboot of internet-router (via external script that
telnets to router)
- notify D-STAR sysop when internet connection is down


As this is plain perl-code, this can run on any linux machine, either
a D-STAR repeater itself, an external linux machine or even a 
linux-based control-board.


Everybody interested in extending this script, feel free to
contact me or drop a message in the "DStar-gateway" list on
yahoogroups:
http://groups.yahoo.com/group/DStar-Gateway/


73
Kristoff - ON1ARF
04/dec/2011
