#!/usr/local/bin/perl

###############################################################################
# Program     : GetResultset.cgi
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id: GetResultSet.cgi 6656 2011-01-24 19:04:50Z dcampbel $
#
# Description : This CGI program dumps the ResultSet data to the user
#               in various formats
#
# SBEAMS is Copyright (C) 2000-2005 Institute for Systems Biology
# This program is governed by the terms of the GNU General Public License (GPL)
# version 2 as published by the Free Software Foundation.  It is provided
# WITHOUT ANY WARRANTY.  See the full description of GPL terms in the
# LICENSE file distributed with this software.
#
###############################################################################


###############################################################################
# Set up all needed modules and objects
###############################################################################
use strict;
use Getopt::Long;
use FindBin;

use lib "$FindBin::Bin/../../lib/perl";
use vars qw ($sbeams $sbeamsMOD $q $current_contact_id $current_username
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG $TESTONLY
             $TABLE_NAME $PROGRAM_FILE_NAME $CATEGORY $DB_TABLE_NAME
             @MENU_OPTIONS);

use SBEAMS::Connection qw($q $log);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;
use SBEAMS::PeptideAtlas;

$sbeams = new SBEAMS::Connection;
my $atlas = new SBEAMS::PeptideAtlas;
$atlas->setSBEAMS( $sbeams );

my $pid = $$;


###############################################################################
# Set program name and usage banner for command line use
###############################################################################
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
Usage: $PROG_NAME [OPTIONS] key=value key=value ...
Options:
  --verbose n         Set verbosity level.  default is 0
  --quiet             Set flag to print nothing at all except errors
  --debug n           Set debug flag to level n
  --testonly          Set testonly flag which simulates INSERTs/UPDATEs only

 e.g.:  $PROG_NAME --verbose 2 keyword=value

EOU

#### Process options
unless (GetOptions(\%OPTIONS,"verbose:s","quiet","debug:s","quiet")) {
  print "$USAGE";
  exit;
}

$VERBOSE = $OPTIONS{"verbose"} || 0;
$QUIET = $OPTIONS{"quiet"} || 0;
$DEBUG = $OPTIONS{"debug"} || 0;
$TESTONLY = $OPTIONS{"testonly"} || 0;
if ($DEBUG) {
  print "Options settings:\n";
  print "   VERBOSE = $VERBOSE\n";
  print "     QUIET = $QUIET\n";
  print "     DEBUG = $DEBUG\n";
  print "  TESTONLY = $TESTONLY\n";
}


###############################################################################
# Set Global Variables and execute main()
###############################################################################
main();
exit(0);


###############################################################################
# Main Program:
#
# Call $sbeams->Authenticate() and exit if it fails or continue if it works.
###############################################################################
sub main {

  #### Do the SBEAMS authentication and exit if a username is not returned
  exit unless ($current_username = $sbeams->Authenticate(
    #permitted_work_groups_ref=>['xxx','yyy'],
    #connect_read_only=>1,
    allow_anonymous_access=>1,
  ));

  my $mem = $sbeams->memusage( pid => $pid );
  $log->debug( "Init: " . $mem );

  #### Read in the default input parameters
  my %parameters;
  my $n_params_found = $sbeams->parse_input_parameters(
    q=>$q,parameters_ref=>\%parameters);
  #$sbeams->printDebuggingInfo($q);

  #### Process generic "state" parameters before we start
  #$sbeams->processStandardParameters(parameters_ref=>\%parameters);

  #### Decide what action to take based on information so far
  if (defined($parameters{action}) && $parameters{action} eq "???") {
    # Some action
  } else {
    #$sbeams->display_page_header();
    handle_request(ref_parameters=>\%parameters);
    #$sbeams->display_page_footer();
  }


} # end main



###############################################################################
# Handle Request
###############################################################################
sub handle_request {
  my %args = @_;

  #### Process the arguments list
  my $ref_parameters = $args{'ref_parameters'}
    || die "ref_parameters not passed";
  my %parameters = %{$ref_parameters};

  #### Define some general variables
  my ($i,$element,$key,$value,$line,$result,$sql);
  my %resultset = ();
  my $resultset_ref = \%resultset;

  use Data::Dumper;

  my $apply_action  = $q->param('apply_action');
  my $remove_markup = $parameters{remove_markup};
  my $format = $parameters{format} || 'tsv';
  my $download = $parameters{download};

  #### verify that needed parameters were passed
  unless ($parameters{rs_set_name}) {
    print "ERROR: not all needed parameters were passed.  This should never ".
      "happen!  Please report this error.<BR>\n";
    return;
  }
  my $mem = $sbeams->memusage( pid => $pid );
  $log->debug( "Read resultset: " . $mem );

  #### Read in the result set
  $sbeams->readResultSet(  resultset_file => $parameters{rs_set_name},
                            resultset_ref => $resultset_ref,
                     query_parameters_ref => \%parameters,
                                      pid => $pid,
                                      debug => 1 );

  $mem = $sbeams->memusage( pid => $pid );
  $log->debug( "Done: " . $mem );

  #### Default format is Tab Separated Value
	my $content_type = ( $format =~ /tsv/i ) ? "Content-type: text/tab-separated-values\n\n" :
                     ( $format =~ /excel/i ) ? "Content-type: text/tab-separated-values\n\n" : '';

  $content_type = "Content-type: text/tab-separated-values\n\n" if $parameters{tsv_output};

  if ( $content_type )  { # Works now since downloads can be tsv or excel,
		                      # will need tweaking if we add xml.
    print $content_type;

    $mem = $sbeams->memusage( pid => $pid );
    $log->debug( "Convert to TSV: " . $mem );

    my $tsv_formatted = get_tsv_format( $resultset_ref, $remove_markup );

    $mem = $sbeams->memusage( pid => $pid );
    $log->debug( "Done: " . $mem );

    $mem = $sbeams->memusage( pid => $pid );
    $log->debug( "Convert to mrm format: " . $mem );

    if ( $download =~ /AgilentQQQ_dynamic/i ) {
      my $method = $atlas->get_qqq_dynamic_transition_list( $tsv_formatted );
      print $method;
    } elsif ( $download =~ /AgilentQQQ/i ) {
      my $method = $atlas->get_qqq_unscheduled_transition_list( $tsv_formatted );
      print $method;
    } elsif ( $download =~ /TSV/i ) {
      for my $row ( @{$tsv_formatted} ) {
        print join( "\t", @{$row} ) . "\n";
      }
    } else {
      for my $row ( @{$tsv_formatted} ) {
        print join( "\t", @{$row} ) . "\n";
      }
    }
    $mem = $sbeams->memusage( pid => $pid );
    $log->debug( "Done: " . $mem );


  } else {

    $sbeams->printPageHeader();
    print "<BR><BR>ERROR: Unrecognized format '$parameters{format}'<BR>\n";
    $sbeams->printPageFooter();

  }



} # end handle_request


sub get_tsv_format {

  my $resultset_ref = shift;
  my $remove_markup = shift;

  my $nrows = scalar(@{$resultset_ref->{data_ref}});
  my @tsv = ( $resultset_ref->{column_list_ref} );

  if ( $remove_markup ) {
    for ( my $i = 0; $i < $nrows; $i++ ) {
      my @row = @{$resultset_ref->{data_ref}->[$i]};
      my @return_row;
      for my $item ( @row ) {
        $item =~ s/<[^>]*>//gm;
        $item =~ s/\&nbsp\;//gm;
        push @return_row, $item;
      }
      push @tsv, \@return_row;
    }
  } else {
    for ( my $i = 0; $i < $nrows; $i++ ) {
      push @tsv, $resultset_ref->{data_ref}->[$i];
    }
  }
  return \@tsv;
}
