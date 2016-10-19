#!/usr/bin/perl -w
####################################################
#
# Perl source file for project createholds 
# Purpose:
# Method:
#
# Creates holds for an arbitrary but specified user.
#    Copyright (C) 2014  Andrew Nisbet
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Author:  Andrew Nisbet, Edmonton Public Library
# Created: Wed Dec 10 11:11:17 MST 2014
# Rev: 
#          0.3 - Make hold first in hold queue.
#          0.2 - Removing cleaning of incoming item ids because the test doesn't account
#                for variation of ids such as on order ids. A hold on an invalid item will
#                fail in Symphony anyway. 
#          0.0 - Dev. 
#
####################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'}  = qq{:/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/usr/bin:/usr/sbin};
$ENV{'UPATH'} = qq{/s/sirsi/Unicorn/Config/upath};
###############################################

my $WORKING_DIR  = qq{.};
my $HOLD_TRX     = "$WORKING_DIR/create_hold.trx";
my $HOLD_RSP     = "$WORKING_DIR/create_hold.rsp";
my $TMP          = "$WORKING_DIR/create_hold.tmp";
my $HOLD_TYPE    = qq{COPY};
my $PICKUP_LOCATION  = qq{EPLZORDER};
my $SYSTEM_CARD  = "";
my $HOLDPOSITION = qq{Y};    # By default this script places holds at the top of the queue. This is 
                             # done because it is used by automation to ensure that holds for system 
							 # cards get processed before customer holds. Think about av incomplete.
my $VERSION      = qq{0.3};

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-qtUx] -B<barcode> [-l <library_code>]
Creates holds for a user. The script expects a list of items on stdin
which must have the barcode of the item; one per line.

Use the '-B' switch will determine which user account is 
to be affected.

 -B: REQUIRED User ID.
 -l: Sets the hold pickup location. Default $PICKUP_LOCATION.
 -q: Please hold normally, that is, hold goes on the end of the queue. 
     The default is to create hold as position #1 on queue because 
     this script is used to create holds for system cards which get priority.
 -t: Creates title level holds (create COPY level holds by default).
 -U: Actually places holds. Default just produce transaction commands.
 -x: This (help) message.

example: 
 $0 -x
 cat item_ids.lst | $0 -B 21221012345678 -U
 cat item_ids.lst | $0 -B 21221012345678 -tU
 echo 31221102353351 | $0 -B 21221012345678 -tUq
 cat item_ids.lst | $0
 
Version: $VERSION
EOF
    exit;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'B:l:qtUx';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
    if ( $opt{'B'} )
	{
		$SYSTEM_CARD = $opt{'B'};
	}
	else
	{
		usage();
	}
	$HOLD_TYPE    = qq{TITLE} if ( $opt{'t'} );
	$HOLDPOSITION = qq{N} if ( $opt{'q'} );
}

# Trim function to remove whitespace from the start and end of the string.
# param:  string to trim.
# return: string without leading or trailing spaces.
sub trim( $ )
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

# Creates an APIServer hold command for a specific item.
# param:  $userId string - Id of the DISCARD card. 
# param:  $barCode string - item barcode. 
# param:  $copyNumber string - copy number of the item to hold.
# param:  $callNumber string - item's call number. 
# param:  $sequenceNumber string - sequence number of the transaction.
# param:  $holdPickupLibrary - the name of the library where the item is sent to fulfil the hold.
# return: string of api command.
sub createHold( $$$$$$ )
{
	my ( $userId, $barCode, $copyNumber, $callNumber, $sequenceNumber, $holdPickupLibrary ) = @_;
	# looks like: 
	# E201210121434290943R ^S32JZFFADMIN^FEEPLMNA^FcNONE^FWADMIN^UO21221015766709^Uk^NQ31221040008513^IQILS Test Call Number^IS3^DHNO^HB10/12/2013^HEGROUP^HFN^HKCOPY^HOEPLMNA^dC3^Fv3000000^^O
	#                      ^S42JZFFADMIN^FEEPLMNA^FcNONE^FWADMIN^UODISCARD-BTGFTG^Uk^NQ31221079059551^IQ9^IS10^DHNO^HBNEVER^HEGROUP^HFN^HKCOPY^HOEPLMNA^dC3^Fv3000000^^O
	#
	#
	# except that we need a copy level hold to be placed first on the hold queue which looks like:
	# E201402191335450010R ^S70JZFFADMIN^FEEPLMNA^FcNONE^FWADMIN^UO21221012345678^Uk^NQ31221108123196^IQEasy readers P PBK^IS1^DHNO^HB2/19/2015^HEGROUP^HFY^HGPlace first on queue.^HKCOPY^HOEPLMNA^dC3^4MN^Fv3000000^^O
	my $transactionRequestLine = '^S';
	$transactionRequestLine .= $sequenceNumber = '0' x ( 2 - length( $sequenceNumber ) ) . $sequenceNumber;
	$transactionRequestLine .= 'JZFFADMIN';
	$transactionRequestLine .= '^FEEPLMNA';
	$transactionRequestLine .= '^FcNONE';
	$transactionRequestLine .= '^FWADMIN';
	$transactionRequestLine .= '^UO'.$userId;
	$transactionRequestLine .= '^Uk';  # user alternative ID
	$transactionRequestLine .= '^NQ'.$barCode;
	$transactionRequestLine .= '^IQ'.$callNumber;
	$transactionRequestLine .= '^IS'.$copyNumber;
	$transactionRequestLine .= '^DHNO';
	$transactionRequestLine .= '^HBNEVER'; #.$holdExpiryDate;
	$transactionRequestLine .= '^HEGROUP';
	$transactionRequestLine .= '^HF'.$HOLDPOSITION; # HF - Hold position. 'HFN' put on bottom of queue with '-q', 'HFY' at top default.
	$transactionRequestLine .= '^HK'.$HOLD_TYPE;    # Copy (by default) or title level hold with 't'.
	$transactionRequestLine .= '^HO'.$holdPickupLibrary; # Hold pickup library.
	$transactionRequestLine .= '^dC3'; # workflows.
	$transactionRequestLine .= '^OM';  # master override (and why not?)
	$transactionRequestLine .= '^Fv3000000';
	$transactionRequestLine .= '^^O';
	return "$transactionRequestLine\n";
}

init();
# Clean the list of items on input.
open HOLDKEYS, ">$TMP"  or die "**Error: unable to open tmp file '$TMP', $!\n";
while (<>) 
{
	my $barcode = trim ( $_ );
	print HOLDKEYS "$barcode\n";
}
close HOLDKEYS;

my $results                   = `cat $TMP | selitem -iB -oIB | selcatalog -iC -oCSt | selcallnum -iN -oNSD 2>/dev/null`;
my @records                   = split( '\n', $results );
my $transactionSequenceNumber = 0;
my $count                     = 0;
my $pickupLocation            = $PICKUP_LOCATION;
if ( $opt{'l'} )
{
	$pickupLocation = $opt{'l'};
}
open( API_SERVER_TRANSACTION_FILE, ">$HOLD_TRX" ) or die "Couldn't write to '$HOLD_TRX' $!\n";
foreach my $record ( @records )
{
	# print "$record\n";
	# Item key     | barcode        |Author Title                                             |Callnum|
	# 790890|12|121|31221091962790  |Snow White and the seven dwarfs [videorecording]|DVD J 398.22 SNO| 
	my ( $catKey, $callSeq, $copyNumber, $barcode, $titleAuthor, $callNumber ) = split( '\|', $record );
	$transactionSequenceNumber = 1 if ( $transactionSequenceNumber++ >= 99 );
	print API_SERVER_TRANSACTION_FILE createHold( $SYSTEM_CARD, $barcode, $copyNumber, $callNumber, $transactionSequenceNumber, $pickupLocation );
	$count++;
	$barcode = trim( $barcode );
}
close( API_SERVER_TRANSACTION_FILE );

# Remove the cleaned barcode list.
unlink $TMP;
# Place holds for all items in list.
if ( $opt{'U'} )
{
	`apiserver -h <$HOLD_TRX >$HOLD_RSP` if ( -s $HOLD_TRX );
}
# EOF
