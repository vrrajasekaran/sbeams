#!/usr/local/bin/perl

###############################################################################
# Program     : main.cgi
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This program shows a users personal view of the data
#
# SBEAMS is Copyright (C) 2000-2003 by Eric Deutsch
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
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG $DATABASE
             $TABLE_NAME $PROGRAM_FILE_NAME $CATEGORY $DB_TABLE_NAME
             @MENU_OPTIONS);

use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;

use SBEAMS::SNP;
use SBEAMS::SNP::Settings;
use SBEAMS::SNP::Tables;

$sbeams = new SBEAMS::Connection;
$sbeamsMOD = new SBEAMS::SNP;
$sbeamsMOD->setSBEAMS($sbeams);
$sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);


#use CGI;
#$q = new CGI;


###############################################################################
# Set program name and usage banner for command like use
###############################################################################
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
Usage: $PROG_NAME [OPTIONS] key=value kay=value ...
Options:
  --verbose n         Set verbosity level.  default is 0
  --quiet             Set flag to print nothing at all except errors
  --debug n           Set debug flag

 e.g.:  $PROG_NAME [OPTIONS] [keyword=value],...

EOU

#### Process options
unless (GetOptions(\%OPTIONS,"verbose:s","quiet","debug:s")) {
  print "$USAGE";
  exit;
}

$VERBOSE = $OPTIONS{"verbose"} || 0;
$QUIET = $OPTIONS{"quiet"} || 0;
$DEBUG = $OPTIONS{"debug"} || 0;
if ($DEBUG) {
  print "Options settings:\n";
  print "  VERBOSE = $VERBOSE\n";
  print "  QUIET = $QUIET\n";
  print "  DEBUG = $DEBUG\n";
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
    #permitted_work_groups_ref=>['SNP_user','SNP_admin',
    #  'SNP_readonly'],
    #connect_read_only=>1,
    #allow_anonymous_access=>1,
  ));


  #### Read in the default input parameters
  my %parameters;
  my $n_params_found = $sbeams->parse_input_parameters(
    q=>$q,parameters_ref=>\%parameters);
  #$sbeams->printDebuggingInfo($q);


  #### Process generic "state" parameters before we start
  $sbeams->processStandardParameters(parameters_ref=>\%parameters);


  #### Decide what action to take based on information so far
  if ($parameters{action} eq "???") {
    # Some action
  } else {
    $sbeamsMOD->display_page_header();
    handle_request(ref_parameters=>\%parameters);
    $sbeamsMOD->display_page_footer();
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


  #### Define some generic varibles
  my ($i,$element,$key,$value,$line,$result,$sql);
  my @rows;


  #### Show current user context information
  $sbeams->printUserContext();
  $current_contact_id = $sbeams->getCurrent_contact_id();


  #### Get information about the current project from the database
  $sql = qq~
        SELECT PR.project_id,PL.name,PL.project_tag,PL.project_status,PL.PI_contact_id
          FROM project PL
    INNER JOIN SEQUENOM..SEQUENOM.PROJECT PR
            ON ( PL.project_tag = PR.project_id)
  ~;
  @rows = $sbeams->selectSeveralColumns($sql);

  my $project_id = '';
  my $project_name = 'NONE';
  my $project_tag = 'NONE';
  my $project_status = 'N/A';
  my $PI_contact_id = 0;
  if (@rows) {
    ($project_id,$project_name,$project_tag,$project_status,$PI_contact_id) = @{$rows[0]};
  }
  my $PI_name = $sbeams->getUsername($PI_contact_id);

  #### Print out some information about this project
  print qq~
	<H1>Current Project: <A class="h1" HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=project&project_id=$project_id">$project_name</A></H1>
	<TABLE WIDTH="100%" BORDER=0>
	<TR><TD><IMG SRC="$HTML_BASE_DIR/images/space.gif" WIDTH="20" HEIGHT="1"></TD>
	             <TD COLSPAN="2" WIDTH="100%"><B>Status:</B> $project_status</TD></TR>
	<TR><TD></TD><TD COLSPAN="2"><B>Project Tag:</B> $project_tag</TD></TR>
	<TR><TD></TD><TD COLSPAN="2"><B>Owner:</B> $PI_name</TD></TR>
	<TR><TD></TD><TD COLSPAN="2"><B>Access Privileges:</B> <A HREF="$CGI_BASE_DIR/ManageProjectPrivileges">[View/Edit]</A></TD></TR>
	<TR><TD></TD><TD COLSPAN="2"><B>Experiments:</B></TD></TR>
	<TR><TD></TD><TD><IMG SRC="$HTML_BASE_DIR/images/space.gif" WIDTH="20" HEIGHT="1"></TD>
	                 <TD WIDTH="100%"><TABLE BORDER=0>
  ~;


  #### If the current user is not the owner, the check that the
  #### user has privilege to access this project
  if ($project_id > 0) {

    my $best_permission = $sbeams->get_best_permission();

    #### If not at least data_reader, set project_id to a bad value
    $project_id = -99 unless ($best_permission > 0 && $best_permission <=40);

  }


  #### Get all the experiments for this project
  if ($project_id > 0) {
    $sql = qq~
	SELECT snp_source_id,source_name
	  FROM $TBSN_SNP_SOURCE
	 WHERE snp_source_id = '9999'
	 ORDER BY source_name
    ~;
    @rows = $sbeams->selectSeveralColumns($sql);
  } else {
    @rows = ();
  }


  #### If there are experiments, display them
  if (@rows) {
    foreach my $row (@rows) {
      my ($experiment_id,$experiment_tag,$experiment_name) = @{$row};

      #### Find out what search_batches exist for this experiment
      $sql = qq~
	SELECT S.search_batch_id,S.search_batch_subdir,BSS.set_tag
	  FROM $TBSN_SNP S
	 INNER JOIN $TBSN_BIOSEQUENCE_SET BSS
	       ON ( S.biosequence_set_id = BSS.biosequence_set_id )
	 WHERE S.experiment_id = '$experiment_id'
	 ORDER BY BSS.set_tag,SB.search_batch_subdir
      ~;
      my @search_batch_rows = $sbeams->selectSeveralColumns($sql);

      print qq~
	<TR><TD NOWRAP>- <font color="green">$experiment_tag:</font> $experiment_name</TD>
	<TD NOWRAP>&nbsp;&nbsp;&nbsp;<A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_proteomics_experiment&experiment_id=$experiment_id">[View/Edit]</A></TD>
	<TD NOWRAP>&nbsp;&nbsp;&nbsp;<A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/SummarizeFractions?action=QUERYHIDE&QUERY_NAME=PR_SummarizeFractions&experiment_id=$experiment_id">[View Fractions]</A></TD>
      ~;

      foreach my $search_batch_row (@search_batch_rows) {
        my ($search_batch_id,$search_batch_subdir,$set_tag) = @{$search_batch_row};
        print qq~
	  <TD>&nbsp;&nbsp;&nbsp;<font color="green">$set_tag</font> ($search_batch_id:&nbsp;<A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/SummarizePeptides?action=QUERY&QUERY_NAME=PR_SummarizePeptides&search_batch_id=$search_batch_id&probability_constraint=\%3E.9&n_annotations_constraint=%3E0&sort_order=tABS.row_count%20DESC&display_options=GroupReference&input_form_format=minimum_detail">P&gt;0.9</A>&nbsp;--&nbsp;<A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/SummarizePeptides?action=QUERY&QUERY_NAME=PR_SummarizePeptides&search_batch_id=$search_batch_id&annotation_status_id=Annot&n_annotations_constraint=%3E0&sort_order=tABS.row_count%20DESC&display_options=GroupReference&input_form_format=minimum_detail">Annot</A>)</TD>
        ~;
      }


      print qq~
	</TR>
      ~;
    }
  } else {
    if ($project_id = -99) {
      print "	<TR><TD WIDTH=\"100%\">You do not have access to this project.  Contact the owner of this project if you want to have access.</TD></TR>\n";
    } else {
      print "	<TR><TD WIDTH=\"100%\">NONE</TD></TR>\n";
    }
  }


  #### Finish the table
  print qq~
	</TABLE></TD></TR>
	</TABLE>
  ~;



  ##########################################################################
  #### Print out all projects owned by the user

  $sbeams->printProjectsYouOwn();



  ##########################################################################
  #### Print out all projects user has access to

  $sbeams->printProjectsYouHaveAccessTo();


  ##########################################################################
  #### Print out some recent resultsets

  $sbeams->printRecentResultsets();


  ##########################################################################
  #### Print out a bunch of other misc links

  print qq~
	<BR>
	This system is still under active development.  Please be
	patient and report bugs, problems, difficulties, suggestions to
	<B>kdeutsch\@systemsbiology.org</B>.<P>
	<BR>
	<BR>

  ~;



  return;

} # end handle_request


