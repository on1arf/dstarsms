#! /usr/bin/perl

# This perl-script is a demo / proof-of-concept application that shows
# the possible use of connecting a 3G USB-dongle on a D-STAR repeater
# for sending and receiving text-messages.
# It uses the Device::GSM library from CPAN:
# http://search.cpan.org/~cosimo/Device-Gsm-1.58/ or search for 
# "GSM" on http://cpan.perl.org/

# In this setup, the scripts and files are located in /dstar/scripts
# Demonstration applications initiated from SMS are:
# - send a DSTAR message from a SMS message
# - send a local D-STAR message from a SMS message
# - "ping": check dstarsms.pl tool (sends back SMS on request)
# Demonstrated applications initiated from the D-STAR are:
# - send SMS to sysop when D-STAR repeater has rebooted
# (based on result of "uptime" command)


#
#      Copyright (C) 2011 by Kristoff Bonne, ON1ARF
#
#      This program is free software; you can redistribute it and/or modify
#      it under the terms of the GNU General Public License as published by
#      the Free Software Foundation; version 2 of the License.
#
#      This program is distributed in the hope that it will be useful,
#      but WITHOUT ANY WARRANTY; without even the implied warranty of
#      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#      GNU General Public License for more details.
#

# release information:
# 4/dec/2011: initial release

# first load all perl modules we need

# load modules for GSM
use Device::Gsm;

# exclusive file-locking mechanism
use Fcntl qw(:flock);

# to enable the "switch/case" structure
use Switch;


############################################
# ## Modify this part for customisation ## #
############################################

$dongledevice="/dev/ttyUSB0";

# PIN code of simcard. Leave blank if not used
$pincode = "";

# name of repeater
$repeatername = "on0os";


############################################
# ## Do not modify anything below here  ## #
# ## unless you know what you are doing ## #
############################################


# define some vars
$scriptdir="/dstar/scripts";
$apidir="/dstar/tmp";

# timers for "uptime" test
$uptime_tslastsms=0;
$uptime_periode=1800; # 30 minutes


## Sleep 15 seconds
## This is to give the "killall" in the crontab time to work
sleep 15;

## We start this program every minute in the crontab
## do this check so there are no instances of this program
## running at the same time
## We do this by creating a exclusive lock on a file
## If it fails, there already is another instance of this
## program running

open (LOCKFILE,">$scriptdir/dstarsms.lck");

$lockresult=flock(LOCKFILE, LOCK_EX | LOCK_NB);

if ($lockresult == 0) {
	# lock failed, so there already is a instance of this program running
	# -> exit
	exit;
}; # end if

# some extra debug code.
# Sometimes, the usbserial kernel module gets stuck
# so we remove the usbserial kernel module and reload it
# this works on a Huawei E220 / E270

system ("/sbin/rmmod usbserial");
sleep 2;
# reload module
system ("/sbin/modprobe usbserial vendor=0x12d1 product=0x1003");
sleep 2;

# some of these tools can send messages on the DSTAR network, based on SMS-messages received by the system.
# As "transmitting" on a amateur-radio frequency is only allowed by licensed radio-amateurs; this script uses a
# "whitelist" of "accepted" MSISDN-numbers

# read whitelist for "locmsg"
open (WLFILE,"<$scriptdir/whitelist_locmsg.dat");
while (<WLFILE>) {
	$inpline=$_;
	# remove any trailing \n that might be there	
	chomp $inpline;

	# one MSISDN number per line
	($word1,$rest)=split(" ",$inpline);
	
	# store in memory
	$whitelist_locmsg{$word1}=$word1;
}; # end while
close (WLFILE);

# read whitelist for "bcmsg"
open (WLFILE,"<$scriptdir/whitelist_bcmsg.dat");
while (<WLFILE>) {
	$inpline=$_;
	# remove any trailing \n that might be there	
	chomp $inpline;

	# one MSISDN number per line
	($word1,$rest)=split(" ",$inpline);
	
	# store in memory
	$whitelist_bcmsg{$word1}=$word1;
}; # end while
close (WLFILE);


# this script can also send alarms SMSs based on certain tests. (like reboot happened or internet-connection lost)
# For this, we have a list of MSISDN-numbers we should send this SMS-alarm to

# read list of recipients for "uptime" alarm
open (WLFILE,"<$scriptdir/recipient_uptime.dat");
while (<WLFILE>) {
	$inpline=$_;
	# remove any trailing \n that might be there	
	chomp $inpline;

	# one MSISDN number per line
	($word1,$rest)=split(" ",$inpline);
	
	# store in memory
	$recipient_uptime{$word1}=$word1;
}; # end while


#### Main part of program starts here
####


### initialise USB 3G dongle and get on the network

# create instance of Device::Gsm object

if ($pincode eq "") {
	# no pingcode on SIMcard
	$gsm = new Device::Gsm( port => $dongledevice );
} else {
	$gsm = new Device::Gsm( port => $dongledevice, pin => $pincode );
}; # end else - if




### here starts the endless loop which is the main part of the program

# loop forever
while (true) {

	# make connection to 3G UMTS dongle
	if ( ! $gsm->connect() ) {
	   print "Problem: cannot connect to 3G card! \n";
		exit;
	}

	# Register to GSM network
	$gsm->register();

	# part 1: actions based on received SMS-messages

	# get ALL messages, both on SIM and on device
	@sms= $gsm->messages('ALL');

	# any messages ?
	if ( @sms ) {
	# yep!
	# incoming message!
		foreach $thismessage ( @sms ){

			# get some data from the message
			$msg_sender=$thismessage->sender(); # MSISDN number of sender
			$msg_content=$thismessage->content(); # message itself
			$msg_index=$thismessage->index(); # index of message in memory
			$msg_time=$thismessage->time(); # timestamp

			# logging: add message to log-file
			open (MSGLOG,">>$scriptdir/sms.log");
			print MSGLOG "sender: $msg_sender\n";
			print MSGLOG "timestamp: $msg_time\n";
			print MSGLOG "Content follows below:\n";
			print MSGLOG "$msg_content\n\n"; # terminate by 2 empty lines
			close (MSGLOG);


			# now parse the message content.
			# first two words + rest
			($t1,$t2,$content_rest)=split(" ",$msg_content,3);

			# make lowercase
			$content_word1=lc($t1);
			$content_word2=lc($t2);



			# analyse first word: valid words are "locmsg", "bcmsg" and "ping"

			switch ($content_word1) {
				case ("locmsg") {
					# locmsg: message to LOCAL module, do NOT forwared to other linked systems or DVdongles
					# word2 should contain Module ("a", "b" or "c")
					# rest of sms is send out on DSTAR network, after being trunkated to 20 characters

					# module name should be "a", "b" or "c"
					if (($content_word2 eq "a") || ($content_word2 eq "b") || ($content_word2 eq "c")) {

						# now check if the sender is in our whitelist
						if (defined $whitelist_locmsg{$msg_sender}) {

							# yes, OK. Let's go for it

							# limit message to 20 characters
							$content_tosend=substr($content_rest,0,20);
					
							# save data in two files
							# in the API directory for actually sending the message
							# in the script directory for archiving of last message

							open (FILEOUT,">$apidir/message-$content_word2");
							print FILEOUT "$content_tosend\n";
							close (FILEOUT);

							open (FILEOUT,">$scriptdir/latest.message-$content_word2");
							print FILEOUT "whitelist check passed\n";
							print FILEOUT "$content_tosend\n";
							close (FILEOUT);

							# sleep 6 seconds
							sleep 6;
						} else {
							# no, sent back sms-message
							$gsm->send_sms(
								recipient => $msg_sender,
								content   => "$repeatername: locmsg: you are not allowed to send messages"
							);
 
							# store in archive
							open (FILEOUT,">$scriptdir/latest.message-$content_word2");
							print FILEOUT "whitelist check FAILED\n";
							print FILEOUT "$content_tosend\n";
							close (FILEOUT);

						}; # end else - if

					} else {
						# Send SMS with error text
						$gsm->send_sms(
							recipient => $msg_sender,
							content   => "$repeatername: error in locmsg: module should be A, B or C"
						);
					}; # end else - if


				}; # end case

				case ("bcmsg") {
					# bcmsg: broadcast message to module including all linked stations and dongle users
					# word2 should contain Module ("a", "b" or "c")
					# rest of sms is send out on DSTAR network, after being trunkated to 20 characters

					# module name should be "a", "b" or "c"
					if (($content_word2 eq "a") || ($content_word2 eq "b") || ($content_word2 eq "c")) {
						# limit message to 20 characters
						$content_tosend=substr($content_rest,0,20);
					
						# now check if the sender is in our whitelist
						if (defined $whitelist_bcmsg{$msg_sender}) {

							# yes, OK. Let's go for it

							# save data in two files
							# in the API directory for actually sending the message
							# in the script directory for archiving of last message

							open (FILEOUT,">$apidir/broadcastmessage-$content_word2");
							print FILEOUT "$content_tosend\n";
							close (FILEOUT);

							open (FILEOUT,">$scriptdir/latest.broadcastmessage-$content_word2");
							print FILEOUT "whitelist check passed\n";
							print FILEOUT "$content_tosend\n";
							close (FILEOUT);

							# sleep 6 seconds
							sleep 6;
						} else {
							# no, sent back sms-message
							$gsm->send_sms(
								recipient => $msg_sender,
								content   => "$repeatername: bcmsg: you are not allowed to send messages"
							);
 
							# store in archive
							open (FILEOUT,">$scriptdir/latest.broadcastmessage-$content_word2");
							print FILEOUT "whitelist check FAILED\n";
							print FILEOUT "$content_tosend\n";
							close (FILEOUT);

						}; # end else - if

					} else {
						# Send SMS with error text
						$gsm->send_sms(
							recipient => $msg_sender,
							content   => "$repeatername: error in bcmsg: module should be A, B or C"
						);
					}; # end else - if

				}; # end case

				case ("ping") {
					# pingtest, just to test is "dstarsms" is running

					# so just sent back SMS 
					
					$gsm->send_sms(
						recipient => $msg_sender,
						content   => "$repeatername: pingreply: we live!"
					);

				}; # end case

			}; # end switch

			$gsm->delete_sms ($thismessage->index());

		}; # end foreach
	}; # end if



	# part 2:
	# these are test done on the box, based on a number of preprogrammed tests in this script
	# they are not triggered by the reception of an SMS

	# check 1: uptime of box. Send SMS if uptime below 30 minutes ( = box has been rebooted)

	# get uptime: look in /proc/uptime. 1ste value is uptime
	open (UPTIMEIN,"</proc/uptime");
	$inpline=<UPTIMEIN>;
	close UPTOMEIN;

	# remove any trailing \n that might be there	
	chomp $inpline;

	# uptime is first word
	($uptime,$dummy)=split(" ",$inpline);

	# uptime less then 30 minutes
	if ($uptime < 1800) {
		# yep. But let's first check if we have not yet send a sms for this alarm
		$now=time();

		# Only one SMS will be send per "uptime_periode" (default: 30 minutes)
		if (($now - $uptime_tslastsms) > $uptime_periode) {
			# not send a SMS in the last 30 minut
			# so, let's do it

			# go throu all MSISDN-numbers in recipient_uptime list
			foreach $thismsisdn (keys %recipient_uptime) {
				$gsm->send_sms(
					recipient => $thismsisdn,
					content   => "$repeatername ALARM: uptime less then 30 minutes: $uptime seconds!"
				);
			}; # end foreach

			
			# set timestamp
			$uptime_tslastsms=$now;
		}; # end if

	}; # end if
	# ok, done. Sleep 10 seconds
	sleep 10;

}; # end forever

