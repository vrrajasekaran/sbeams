#!/usr/local/bin/perl

###############################################################################
# Program     : ManageTable.cgi
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This CGI program that allows users to
#               manage the contents of a table.
#               This means viewing, inserting, updating,
#               and deleting records.
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
use vars qw ($sbeams $sbeamsMOD $q $dbh $current_contact_id $current_username
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG $DATABASE
             $current_work_group_id $current_work_group_name
             $current_project_id $current_project_name
             $TABLE_NAME $PROGRAM_FILE_NAME $CATEGORY $DB_TABLE_NAME
             $PK_COLUMN_NAME @MENU_OPTIONS);
use DBI;
#use CGI;
use CGI::Carp qw(fatalsToBrowser croak);

use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;
use SBEAMS::Connection::TableInfo;
#$q = new CGI;
$sbeams = new SBEAMS::Connection;

use SBEAMS::Genotyping;
use SBEAMS::Genotyping::Settings;
use SBEAMS::Genotyping::Tables;
use SBEAMS::Genotyping::TableInfo;
$sbeamsMOD = new SBEAMS::Genotyping;

$sbeamsMOD->setSBEAMS($sbeams);
$sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);

require 'ManageTable.pllib';



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
# Set maximum post (file upload) to 30 MB
$CGI::POST_MAX = 1024 * 30000;
main();
exit(0);



###############################################################################
# Main Program:
#
# Call $sbeams->InterfaceEntry with pointer to the subroutine to execute if
# the authentication succeeds.
###############################################################################
sub main {

  #### Do the SBEAMS authentication and exit if a username is not returned
  exit unless ($current_username = $sbeams->Authenticate(
    #connect_read_only=>1,
    #allow_anonymous_access=>1,
    #permitted_work_groups_ref=>['Proteomics_user','Proteomics_admin'],
  ));

  #### Read in the default input parameters
  my %parameters;
  my $n_params_found = $sbeams->parse_input_parameters(
    q=>$q,parameters_ref=>\%parameters);
  #$sbeams->printDebuggingInfo($q);

  #### Process generic "state" parameters before we start
  $sbeams->processStandardParameters(parameters_ref=>\%parameters);


  $TABLE_NAME = $parameters{'TABLE_NAME'}
    || croak "TABLE_NAME not specified.";

  croak "This TABLE_NAME=$TABLE_NAME cannot be managed by this program."
    unless ($sbeamsMOD->returnTableInfo($TABLE_NAME,
      "ManageTableAllowed"))[0] eq "YES";

  ($CATEGORY) = $sbeamsMOD->returnTableInfo($TABLE_NAME,"CATEGORY");
  ($PROGRAM_FILE_NAME) = $sbeamsMOD->returnTableInfo($TABLE_NAME,
    "PROGRAM_FILE_NAME");
  ($DB_TABLE_NAME) = $sbeamsMOD->returnTableInfo($TABLE_NAME,"DB_TABLE_NAME");
  ($PK_COLUMN_NAME) = $sbeamsMOD->returnTableInfo($TABLE_NAME,
    "PK_COLUMN_NAME");
  @MENU_OPTIONS = $sbeamsMOD->returnTableInfo($TABLE_NAME,"MENU_OPTIONS");


  #### Decide what action to take based on information so far
  if ($parameters{"GetFile"} && $parameters{"$PK_COLUMN_NAME"}) {
    getFile(); return;
  }
  $sbeamsMOD->printPageHeader();
  if      ($parameters{action} eq 'VIEWRESULTSET') { printOptions();
  } elsif ($parameters{action} eq 'REFRESH') { printEntryForm();
  } elsif ($parameters{action} eq 'SAVE TEMPLATE') { saveTemplate();
  } elsif ($parameters{action} eq 'SET FIELDS TO THIS TEMPLATE') {
    printEntryForm();
  } elsif ($parameters{action} eq 'DELETE THIS TEMPLATE') {
    deleteTemplate(
      selected_template => $parameters{selected_template},
      program_file_name => $PROGRAM_FILE_NAME,
    );
  } elsif ($parameters{action}) { processEntryForm();
  } elsif ($q->param('apply_action_hidden')) { printEntryForm();
  } elsif ($q->param('ShowEntryForm')) { printEntryForm();
  } elsif ($parameters{"$PK_COLUMN_NAME"}) { printEntryForm();
  } else { printOptions(); }

  $sbeamsMOD->printPageFooter();


} # end main



###############################################################################
# preFormHook
#
# This is a hook to do some processing before all the lines of data entry
# form have been displayed based on the current table name.  This might be
# used to set some defaults or something.
###############################################################################
sub preFormHook {
  my %args = @_;

  my $query_parameters_ref = $args{'parameters_ref'};


  #### If table XXXX
  if ($TABLE_NAME eq "XXXX") {
    $query_parameters_ref->{YYYY} = 'XXXX'
      unless ($query_parameters_ref->{YYYY});
  }

  #### If table GT_experiment
  if ($TABLE_NAME eq "GT_experiment") {
    $query_parameters_ref->{want_validation} = 'Y'
      unless ($query_parameters_ref->{want_validation});
    $query_parameters_ref->{want_pooling} = 'N'
      unless ($query_parameters_ref->{want_pooling});
    $query_parameters_ref->{want_typing} = 'Y'
      unless ($query_parameters_ref->{want_typing});
    $query_parameters_ref->{is_multiplexing_allowed} = 'Y'
      unless ($query_parameters_ref->{is_multiplexing_allowed});
    $query_parameters_ref->{dna_type} = 'Genomic'
     unless ($query_parameters_ref->{dna_type});
    }

  #### Otherwise, no special processing, so just return undef
  return;

} # end preFormHook



###############################################################################
# postFormHook
#
# This is a hook to do some processing after all the lines of data entry
# form have been displayed but before the table has been closed based on
# the current table name.
###############################################################################
sub postFormHook {
  my %args = @_;

  my $query_parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$query_parameters_ref};


  #### If table XXXX
  if ($TABLE_NAME eq "XXXX") {
    return "An error of some sort $parameters{something} invalid";
  }


  #### Otherwise, no special processing, so just return undef
  return;

} # end postFormHook



###############################################################################
# preUpdateDataCheck
#
# For certain tables, there are additional checks that should be made before
# an INSERT or UPDATE is performed.
###############################################################################
sub preUpdateDataCheck {
  my %args = @_;

  my $query_parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$query_parameters_ref};


  #### If table XXXX
  if ($TABLE_NAME eq "XXXX") {
    return "An error of some sort $parameters{something} invalid";
  }


  #### Otherwise, no special processing, so just return empty string
  return '';

} # end preUpdateDataCheck


###############################################################################
# postUpdateOrInsertHook
#
# This is a hook to do some processing after the record has been updated
# or inserted.
###############################################################################
sub postUpdateOrInsertHook {
  my %args = @_;

  my $query_parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$query_parameters_ref};
  my $pk_value = $args{'pk_value'};


  #### If table XXXX
  if ($TABLE_NAME eq "XXXX") {
    return "An error of some sort $parameters{something} invalid";
  }


  #### If table GT_experiment
  if ($TABLE_NAME eq "GT_experiment") {

    #### Get the predicted location of the samples file
    my $samples_file = "GT_experiment/".
      "$query_parameters_ref->{experiment_id}".
      "_samples_file.dat";


    #### Read in the samples file and create hash out of its contents
    open (SAMPLESFILE,"$UPLOAD_DIR/$samples_file") ||
      die "Cannot open $UPLOAD_DIR/$samples_file";

    my $row_index = 1;
    my @data_rows = ();
    my @columns = ();
    while (<SAMPLESFILE>) {
      #### Ignore if it's the column header line
      next if ($_ =~ /olvent/);

      #### Strip leading and trailing space
      $_ =~ s/^\s+//;
      $_ =~ s/\s+$//;


      #### Separate the columns
      @columns = split(/\t/,$_);
      #### If there are 7 columns, save the values
      if (scalar(@columns) == 7) {
        push(@data_rows,\@columns);
      #### Else complain about a bad number of columns
      } else {
        print "Skipping samples file row $row_index with ".
          "incorrect number of columns: '$_'<BR>\n";
      }

      #### Increment the row counter
      $row_index++;

    } # end while <SAMPLESFILE>

    #### Store the results to the sample table
    my @child_data_columns = qw(plate_id well_position sample_name
      dna_concentration initial_well_volume stock_dna_solvent dna_dilution_solvent);
    updateChildTable(
      parent_table_name => $TABLE_NAME,
      parent_pk_column_name => $PK_COLUMN_NAME,
      parent_pk_value => $parameters{$PK_COLUMN_NAME},
      child_table_name => 'GT_sample',
      child_pk_column_name => 'sample_id',
      child_data_columns => \@child_data_columns,
      child_data_values => \@data_rows,
    );

    #### Get the predicted location of the assays file
    my $assay_file = "GT_experiment/".
      "$query_parameters_ref->{experiment_id}".
      "_assays_file.dat";

    #### Read in the requested assay file and create hash out of its contents
    open (ASSAYFILE,"$UPLOAD_DIR/$assay_file") ||
      die "Cannot open $UPLOAD_DIR/$assay_file";

    $row_index = 1;
    @data_rows = ();
    my @columns = ();
    while (<ASSAYFILE>) {
      #### Ignore if it's the column header line
      next if $_ =~ /^Name/;

      #### Strip leading and trailing space
      $_ =~ s/^\s+//;
      $_ =~ s/\s+$//;


      #### Separate the columns
      @columns = split(/\t/,$_);

      #### If there are 2 columns, save the values
      if (scalar(@columns) == 2) {
        push(@data_rows,\@columns);

      #### Else complain about a bad number of columns
      } else {
        print "Skipping assays file row $row_index with ".
          "incorrect number of columns: '$_'<BR>\n";
      }

      #### Increment the row counter
      $row_index++;

    } # end while <ASSAYFILE>

    #### Store the results to the requested_genotyping_assay table
    my @child_data_columns = qw(requested_assay_name requested_assay_sequence);
    updateChildTable(
      parent_table_name => $TABLE_NAME,
      parent_pk_column_name => $PK_COLUMN_NAME,
      parent_pk_value => $parameters{$PK_COLUMN_NAME},
      child_table_name => 'GT_requested_genotyping_assay',
      child_pk_column_name => 'requested_genotyping_assay_id',
      child_data_columns => \@child_data_columns,
      child_data_values => \@data_rows,
    );

    return;

  } # end if $TABLE_NAME='GT_experiment'

  #### Otherwise, no special processing, so just return undef
  return;

} # end postUpdateOrInsertHook

