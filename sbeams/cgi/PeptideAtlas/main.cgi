#!/usr/local/bin/perl

###############################################################################
# Program     : main.cgi
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This script authenticates the user, and then
#               displays the opening access page.
#
# SBEAMS is Copyright (C) 2000-2003 by Eric Deutsch
# This program is governed by the terms of the GNU General Public License (GPL)
# version 2 as published by the Free Software Foundation.  It is provided
# WITHOUT ANY WARRANTY.  See the full description of GPL terms in the
# LICENSE file distributed with this software.
#
###############################################################################


###############################################################################
# Get the script set up with everything it will need
###############################################################################
use strict;
use vars qw ($q $sbeams $sbeamsPeptideAtlas $PROGRAM_FILE_NAME
             $current_contact_id $current_username);
use lib qw (../../lib/perl);
use CGI;
use CGI::Carp qw(fatalsToBrowser croak);

use SBEAMS::Connection;
use SBEAMS::Connection::Settings;

use SBEAMS::PeptideAtlas;
use SBEAMS::PeptideAtlas::Settings;

$q   = new CGI;
$sbeams = new SBEAMS::Connection;
$sbeamsPeptideAtlas = new SBEAMS::PeptideAtlas;
$sbeamsPeptideAtlas->setSBEAMS($sbeams);


###############################################################################
# Global Variables
###############################################################################
$PROGRAM_FILE_NAME = 'main.cgi';
main();


###############################################################################
# Main Program:
#
# Call $sbeams->Authentication and stop immediately if authentication
# fails else continue.
###############################################################################
sub main { 

    #### Do the SBEAMS authentication and exit if a username is not returned
    exit unless ($current_username = $sbeams->Authenticate( allow_anonymous_access => 1 ) );

    #### Print the header, do what the program does, and print footer
    $sbeamsPeptideAtlas->printPageHeader();
    showMainPage();
    $sbeamsPeptideAtlas->printPageFooter();

} # end main


###############################################################################
# Show the main welcome page
###############################################################################
sub showMainPage {

  $sbeams->printUserContext();

  if ( $sbeams->isGuestUser ) {
    print <<"    END";
	  <BR>
  	You are logged into the $DBTITLE - $SBEAMS_PART system as a guest user.
  	<BR>
    END
  } else {
    print qq!
	  <BR>
  	You are successfully logged into the $DBTITLE - $SBEAMS_PART system.
  	Please choose your tasks from the menu bar on the left.<P>
  	<BR>
  	This system is still under active development.  Please be
  	patient and report bugs, problems, difficulties, suggestions to
  	<B>edeutsch\@systemsbiology.org</B>.<P>
  	<BR>
    !;
  }
  print <<"  END";
  <UL>
  <LI> <A Href="http://www.peptideatlas.org/">About PeptideAtlas</A>
 	<LI> <A Href="GetPeptides">Browse PeptideAtlas </A>
 	<LI> <A Href="GetPeptide">Browse Peptide View [in progress]</A>
	 </UL>

  <BR>
  <BR>
  END

} # end showMainPage
