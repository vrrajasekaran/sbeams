#!/usr/local/bin/perl

###############################################################################
# Program     : main.cgi
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This script authenticates the user, and then
#               displays the opening access page.
#
# SBEAMS is Copyright (C) 2000-2005 Institute for Systems Biology
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
use vars qw ($q $sbeams $sbeamsBS $PROGRAM_FILE_NAME
             $current_contact_id $current_username);
use lib qw (../../lib/perl);
#use CGI;
use CGI::Carp qw(fatalsToBrowser croak);

use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;

use SBEAMS::Biosap;
use SBEAMS::Biosap::Settings;

#$q   = new CGI;
$sbeams = new SBEAMS::Connection;
$sbeamsBS = new SBEAMS::Biosap;
$sbeamsBS->setSBEAMS($sbeams);


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
    exit unless ($current_username = $sbeams->Authenticate());

    #### Print the header, do what the program does, and print footer
    $sbeamsBS->printPageHeader();
    showMainPage();
    $sbeamsBS->printPageFooter();

} # end main


###############################################################################
# Show the main welcome page
###############################################################################
sub showMainPage {

  $sbeams->printUserContext();

  my $html_ref = $sbeams->getMainPageTabMenu( cgi => $q );

  print qq!
  <BR>
  You are successfully logged into the $DBTITLE - $SBEAMS_PART system.
  Please choose your tasks from the menu bar on the left.<P>
  <BR>
  This system is still under active development.  Please be
  patient and report bugs, problems, difficulties, suggestions to
  <B>edeutsch\@systemsbiology.org</B>.<P>
  <BR>

  $$html_ref
  !;


} # end showMainPage


