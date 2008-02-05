#!/usr/local/bin/perl

###############################################################################
# Program     : main.cgi
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id: main.cgi 3243 2005-03-21 09:02:00Z edeutsch $
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
use vars qw ($q $PROGRAM_FILE_NAME
             $current_contact_id $current_username);
use lib qw (../../lib/perl);
#use CGI;
use CGI::Carp qw(fatalsToBrowser croak);

use SBEAMS::Connection qw($q $log);
use SBEAMS::Connection::Settings;

use SBEAMS::PeptideAtlas;

use SBEAMS::Glycopeptide;
use SBEAMS::Glycopeptide::Settings;
use SBEAMS::Glycopeptide::Tables;

my $sbeams = new SBEAMS::Connection;
my $atlas = new SBEAMS::PeptideAtlas;
$atlas->setSBEAMS($sbeams);
my $glyco = new SBEAMS::Glycopeptide;
$glyco->setSBEAMS($sbeams);


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
    exit unless ($current_username = $sbeams->Authenticate(
       permitted_work_groups_ref=>['Glycopeptide_user','Glycopeptide_admin'],
       allow_anonymous_access => 1
          ));

    #### Print the header, do what the program does, and print footer
    $glyco->printPageHeader( onload => 'sorttables_init()' );
    import_sort_table();
    my $intro = get_intro();
    my $content = get_content();
    print $sbeams->getGifSpacer(600);
    print $intro;

    print $content;
    $glyco->printPageFooter();

} # end main


sub get_intro {
  my $build = $glyco->getCurrentBuild();
  my $address = 'dcampbel@systemsbiology.net';
  my $content = qq~
  <P>
  This is the main page of the Glycopeptide module, which is the internal representation of the Unipep database.  Some statistics about the current build, $build, are shown below.  
  <BR><BR>
  Comments are <A HREF='mailto:$address'>welcome!</A>
  </P>
  ~;
  return $content;
}


sub import_sort_table {
  print <<"  END";
  <SCRIPT LANGUAGE=javascript SRC="$HTML_BASE_DIR/usr/javascript/sorttable.js"></SCRIPT>
  END
}



sub get_content {
  my $cutoff = $glyco->get_current_prophet_cutoff();
  my $sql = qq~
  SELECT identified_peptide_sequence, peptide_prophet_score
  FROM $TBGP_IDENTIFIED_PEPTIDE
  ~;
  my @results = $sbeams->selectSeveralColumns( $sql );
  my %stats;
  my $cnt;
  for my $row ( @results ) {
    $cnt++;
    $stats{cnt}++;
    $stats{cys}++ if $row->[0] =~ /C/;
    my ( $missed, $tryp );
    $tryp++ if $row->[0] =~ /^[-|R|K]/;
    $tryp++ if $row->[0] =~ /[R|K]\..$/;
    $missed++ if $row->[0] =~ /^.\..*K[^P].*\..$/;
    $missed++ if $row->[0] =~ /^.\..*R[^P].*\..$/;
    $stats{notryp}++ if $tryp == 0;
    $stats{sing_tryp}++ if $tryp == 1;
    $stats{doub_tryp}++ if $tryp == 2;
    $stats{missed}++ if $missed;
    if ( $row->[1] >= $cutoff ) {
      $stats{cutcnt}++;
      $stats{cutcys}++ if $row->[0] =~ /C/;
      $stats{cutnotryp}++ if $tryp == 0;
      $stats{cutsing_tryp}++ if $tryp == 1;
      $stats{cutdoub_tryp}++ if $tryp == 2;
      $stats{cutmissed}++ if $missed;
    }
  }
  my @table = ( ['Category', "Prophet cutoff ($cutoff)", "Total" ] );
  push @table, [ 'Unique peptides:', $stats{cutcnt} . ' (' . sprintf( "%d\%", $stats{cutcnt}/$stats{cnt}*100 ) . ')', $stats{cnt} ];
  push @table, [ 'Cysteine containing:', $stats{cutcys} . ' (' . sprintf( "%d\%", $stats{cutcys}/$stats{cys}*100 ) . ')', $stats{cys} ];
  push @table, [ 'Singly tryptic:', $stats{cutsing_tryp} . ' (' . sprintf( "%d\%", $stats{cutsing_tryp}/$stats{sing_tryp}*100 ) . ')', $stats{sing_tryp} ];
  push @table, [ 'Doubly tryptic:', $stats{cutdoub_tryp} .  ' (' . sprintf( "%d\%", $stats{cutdoub_tryp}/$stats{doub_tryp}*100 ) . ')', $stats{doub_tryp} ];
  push @table, [ 'Non tryptic:', $stats{cutnotryp} . ' (' . sprintf( "%d\%", $stats{cutnotryp}/$stats{notryp}*100 ) . ')', $stats{notryp} ];
  push @table, [ 'Missed Cleavage:', $stats{cutmissed} . ' (' . sprintf( "%d\%", $stats{cutmissed}/$stats{missed}*100 ) . ')', $stats{missed} ];
  my $table = $atlas->encodeSectionTable( header => 1,
                                          width => 400,
                                          align => [qw(right right right)],
                                          rows => \@table );
  $log->debug($table);
  $table =~ s/(<TABLE)/$1 ID=stats CLASS=sortable/gi;
  $log->debug($table);


  return "<P>$table</P>";
} # end showMainPage


