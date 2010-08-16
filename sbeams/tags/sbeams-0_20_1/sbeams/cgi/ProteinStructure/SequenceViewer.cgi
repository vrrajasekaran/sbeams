#!/usr/local/bin/perl

###############################################################################
# Program     : SequenceViewer
# Author      : Michael H. Johnson <mjohnson@systemsbiology.org>
#
# Description : Given coordinates and a genome, prints out the sequence
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

use SBEAMS::Connection;
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;

use SBEAMS::ProteinStructure;
use SBEAMS::ProteinStructure::Settings;
use SBEAMS::ProteinStructure::Tables;

$sbeams = new SBEAMS::Connection;
$sbeamsMOD = new SBEAMS::ProteinStructure;
$sbeamsMOD->setSBEAMS($sbeams);
$sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);


use CGI;
use CGI::Carp qw(fatalsToBrowser croak);
$q = new CGI;


###############################################################################
# Set program name and usage banner for command like use
###############################################################################
$PROG_NAME = $FindBin::Script;

$USAGE = <<EOU;
Usage: $PROG_NAME [OPTIONS] key=value key=value ...
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
    permitted_work_groups_ref=>['ProteinStructure_user',
      'ProteinStructure_admin','ProteinStructure_readonly','Admin'],
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
  if ($parameters{action} eq "xxxx") {
  } else {
    $sbeamsMOD->display_page_header(
      navigation_bar=>$parameters{navigation_bar});
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
  my ($i,$element,$key,$value,$line,$result);
  my $newline = "\n";
  my $sql;
  my @rows;


  #### Define some variables for a query and resultset
  my %resultset = ();
  my $resultset_ref = \%resultset;
  my (%url_cols,%hidden_cols,%max_widths,$show_sql);


  #### Read in the standard form values
  my $apply_action  = $parameters{'action'} || $parameters{'apply_action'};
  my $TABLE_NAME = $parameters{'QUERY_NAME'};


  #### Set some specific settings for this program
  my $PROGRAM_FILE_NAME="SequenceViewer.cgi";
  my $base_url = "$CGI_BASE_DIR/$SBEAMS_SUBDIR/$PROGRAM_FILE_NAME";

  #### Get the necessary biosequence_set_ids
  my $genome_id = $parameters{'genome_id'};
  my $biosequence_id = $parameters{'biosequence_id'};

  #### If a biosequence_id isn't provided, coordinates are needed, at least
  my $start = $parameters{'start_coordinate'};
  my $stop = $parameters{'stop_coordinate'};

  #### Allow for offset from start/stop
  my $start_offset = $parameters{'start_offset'} || 0;
  my $stop_offset = $parameters{'stop_offset'} || 0;

  #### Start/Stop when factoring in offsets
  my ($adjusted_start, $adjusted_stop);

  #### Display the user-interaction input form
  if ($sbeams->output_mode() eq 'html') {
    print qq~
<SCRIPT LANGUAGE="Javascript">

function verifyNumber(testValue,testLocation){
  var location;
  if(testLocation=="stop_offset"){location=document.ZoomForm.stop_offset;}
  if(testLocation=="start_offset") {location=document.ZoomForm.start_offset;}

  //need just an integer
  if(testLocation=="start_offset" || testLocation=="stop_offset"){
    var number = parseInt(testValue);
    if(isNaN(number)){
      alert(testValue+" not a number");
      location.value ="";
      return;
    }
    else{location.value = number;return;}
  }

}//end verifyNumber
</SCRIPT>

<tr><td><H1>Sequence Viewer</H1></td></tr>
<tr><td height="1"><img src="$HTML_BASE_DIR/images/bg_Nav.gif" width="518" height="1" border="0"></td></tr>
<tr><td height="5"><img src="$HTML_BASE_DIR/images/clear.gif" width="1" height="1" border="0"></td></tr>

<tr><td>
<FORM NAME="ZoomForm" ACTION="$base_url" METHOD="POST">
<INPUT NAME="biosequence_id" TYPE="hidden" VALUE="$parameters{biosequence_id}">
<INPUT NAME="start_coordinate" TYPE="hidden" VALUE="$parameters{start_coordinate}">
<INPUT NAME="stop_coordinate" TYPE="hidden" VALUE="$parameters{stop_coordinate}">
<INPUT TYPE="text" SIZE="4" NAME="start_offset" VALUE="$parameters{start_offset}" onChange="verifyNumber(this.value, this.name)">
----[SEQUENCE]----
<INPUT TYPE="text" SIZE="4" NAME="stop_offset" VALUE="$parameters{stop_offset}" onChange="verifyNumber(this.value, this.name)">
<INPUT TYPE="submit" NAME="action" VALUE="GO">
</FORM>
</td></tr>


<tr><td>
$LINESEPARATOR
<BR>
<PRE>~;
  }

  #### Get all the necessary biosequence information, if possible
  ## We need EITHER
  ## biosequence_id => name, start, stop, chromosome name
  ## -OR-
  ## genome_id & start & stop
  my ($biosequence_name, $biosequence_desc,$biosequence_genome_name, $organism_id);
  my ($genome_name, $genome_seq);


  #### If no valid biosequence_set_id was selected, stop here
  unless ( ($biosequence_id) || 
		   ($start && $stop && $genome_id) ) {
	print "$biosequence_id<BR>start:$start<BR>stop:$stop<BR>genome:$genome_name<BR";
    $sbeams->reportException(
      state => 'ERROR',
      type => 'INSUFFICIENT CONSTRAINTS',
      message => "Could not find sufficient information to print sequence in chromosomal context",
    );
    return;
  }

  ## Get coordinate information from biosequence_id
  if ($biosequence_id) {
	$sql = qq~
	  SELECT BS.biosequence_name, BS.biosequence_desc, 
	         BSPS.start_in_chromosome, BSPS.end_in_chromosome, 
	         BSPS.chromosome, BSS.organism_id
	    FROM $TBPS_BIOSEQUENCE BS
		JOIN $TBPS_BIOSEQUENCE_PROPERTY_SET BSPS ON (BSPS.biosequence_id = BS.biosequence_id)
		JOIN $TBPS_BIOSEQUENCE_SET BSS ON (BSS.biosequence_set_id = BS.biosequence_set_id)
	   WHERE BS.biosequence_id = '$biosequence_id'
	   ~;
	@rows = $sbeams->selectSeveralColumns($sql);
	unless (scalar(@rows) < 1) {
	  ($biosequence_name, $biosequence_desc, $start, 
	   $stop, $biosequence_genome_name, $organism_id) = @{$rows[0]};
	}
  }

  #### Get Genome Sequence
  if ($genome_id) {
	$sql = qq~
	SELECT BS.biosequence_seq,BS.biosequence_name
	  JOIN 
  	  FROM $TBPS_BIOSEQUENCE BS
     WHERE BS.biosequence_id = '$genome_id'
	 ~;
  }else{
	$sql = qq~
	SELECT BS.biosequence_seq,BS.biosequence_name
  	  FROM $TBPS_BIOSEQUENCE BS
      JOIN $TBPS_BIOSEQUENCE_SET BSS ON (BS.biosequence_set_id = BSS.biosequence_set_id)
     WHERE BS.biosequence_name = '$biosequence_genome_name'
       AND BSS.organism_id = '$organism_id'
	   ~;
  }
  my @rows = $sbeams->selectSeveralColumns($sql);
  ($genome_seq,$genome_name) = @{$rows[0]};


  #### Ensure that we have enough information to continue
  unless ( $start && $stop && $genome_seq ) {
	print "$biosequence_id<BR>start:$start<BR>stop:$stop<BR>genome:$genome_name<BR";
    $sbeams->reportException(
      state => 'ERROR',
      type => 'INSUFFICIENT CONSTRAINTS',
      message => "Could not find sufficient information to print sequence in chromosomal context",
    );
    return;
  }

  if ($genome_name ne $biosequence_genome_name) {
	$sbeams->reportException (
	  state   => 'WARNING',
	  type    => 'DATA MISMATCH',
	  message => "Chromosome name ($genome_name) is not the same as reported by the gene ($biosequence_genome_name)",
	  );
	return;
  }
		
  #### Print Header
  my $header;
  if ($biosequence_name) {
	$header = ">$biosequence_name $biosequence_desc";
  }else {
	$header = ">$genome_name $start - $stop";
  }

  #### Handle reverse complement: if gene is on reverse strand, switch
  #### the offset values, and be sure to translate everything
  my $reverse_complement = 0;

  if ($start > $stop ){
	$reverse_complement = 1;
	$stop--;
  }else {
	$start--;
  }

  ## grab the ORF
  my $ORF =  grab_sequence('start'=>$start,
						   'stop'=>$stop,
						   'genome'=>$genome_seq,
						   'reverse_complement'=>$reverse_complement);
  ## Grab Offsets
  my ($start_offset_seq,$stop_offset_seq);

  if ($start_offset != 0) {
	if ($reverse_complement == 0) {
	  $start_offset_seq = grab_sequence('start'=>($start-$start_offset),
										'stop'=>$start,
										'genome'=>$genome_seq,
										'reverse_complement'=>$reverse_complement);
	  $header.=" start_offset=\"";
	  $header .="+" if ($start_offset>0);
	  $header .="$start_offset"."nt\"";
	}else {
	  $start_offset_seq = grab_sequence('start'=>($stop+$start_offset),
										'stop'=>$stop,
										'genome'=>$genome_seq,
										'reverse_complement'=>$reverse_complement);
	  $header.=" start_offset=\"";
	  $header .="+" if ($start_offset>0);
	  $header .="$start_offset"."nt\"";
	}
  }

  if ($stop_offset != 0) {
	if ($reverse_complement == 0) {
	  $stop_offset_seq = grab_sequence('start'=>$stop,
									   'stop'=>($stop + $stop_offset),
									   'genome'=>$genome_seq,
									   'reverse_complement'=>$reverse_complement);
	  $header.=" stop_offset=\"";
	  $header .="+" if ($stop_offset>0);
	  $header .="$stop_offset"."nt\"";
	}else {
	  $stop_offset_seq = grab_sequence('start'=>$start,
									   'stop'=>($start-$stop_offset),
									   'genome'=>$genome_seq,
									   'reverse_complement'=>$reverse_complement);
	  $header.=" stop_offset=\"";
	  $header .="+" if ($stop_offset>0);
	  $header .="$stop_offset"."nt\"";
	}
  }

  #### Color and format the sequence
  my %colorings = ();
  my $start_len = length($start_offset_seq);
  my $orf_len = length($ORF);
  my $stop_len = length($stop_offset_seq);

  if ($start_len > 0 ) {
	$colorings{0} = "<FONT COLOR=\"red\">";
	$colorings{$start_len} = "</FONT>";
  }
  $colorings{$start_len} = "<FONT COLOR=\"blue\">";
  $colorings{$start_len + $orf_len} = "</FONT>";
  if ($stop_len > 0) {
	$colorings{$start_len + $orf_len} = "<FONT COLOR=\"red\">";
	$colorings{$start_len + $orf_len + $stop_len} = "</FONT>";
  }

  print "$header$newline";  
  print format_sequence('sequence'=>($start_offset_seq.$ORF.$stop_offset_seq),
						'color_ref'=>\%colorings,
						'newline'=>$newline);
  print "$newline</PRE>";


#	$header.=" stop_offset=\"";
#	$header .="+" if ($stop_offset>0);
#	$header .="$stop_offset"."nt\"";
#
#	$colorings{$non_adjusted_length + $start_offset} = "<FONT COLOR=\"red\">";
#	$colorings{$non_adjusted_length + $start_offset + $stop_offset} = "</FONT>";
#  #### Get subseqeunce, Ensuring that we have enough 
#  my $length = abs ($adjusted_stop-$adjusted_start);
#  my $t = length($genome_seq);
#  print "STATUS: genome sequence length = $t\n";
#  if ( $length + $adjusted_start > length($genome_seq) ) {
#	print "WARNING: Truncated due to wrapping around chromosome \n";
#	$length = length($genome_seq) - $adjusted_start;
#  }elsif ($adjusted_start < 0){
#	print "WARNING: Truncated due to wrapping around chromosome \n";
#	$adjusted_start = 0;
#  }



#  #### Get sub sequence
#  my $sequence;
#  if ($reverse_complement == 1) {
#	$sequence = reverse substr( $genome_seq, $adjusted_start, $length);
#	$sequence =~ tr/ACGTacgt/TGCAtgca/;
#  }else {
#	$sequence = substr( $genome_seq, $adjusted_start, $length);
#  }
#
#  $sequence = format_sequence('sequence'=>$sequence,
#							  'color_ref'=>\%colorings,
#							  'newline'=>$newline);


} # end handle_request

###############################################################################
# grab_sequence: grabs subseqeuence
###############################################################################
sub grab_sequence {
  my %args = @_;
  my $start = $args{'start'} || die "ERROR[grab_sequence]: start needed\n";
  my $stop = $args{'stop'} || die "ERROR[grab_sequence]: stop needed\n";
  my $genome  = $args{'genome'} || die "ERROR[grab_sequence]: genome needed\n";
  my $reverse_complement = $args{'reverse_complement'} || 0;

  my $length = length($genome);
  my $sequence = "";

  if ($reverse_complement) {
	my $t = $start;
	$start = $stop;
	$stop = $t;
  }

  my $wrapped_from_start = 0;
  my $wrapped_from_stop = 0;
  my $current_start = $start;
  my $current_stop = $stop;

  ## Get as much of the sequence without wrapping;
  if ($stop > $length) {
	$current_stop = $length;
	$wrapped_from_stop = $stop - $length;
  }
  if ($start < 0) {
	$current_start = 0;
	$wrapped_from_start = $start;
  }

  my $stringlen = $current_stop - $current_start;
  $sequence = substr($genome, $current_start, $stringlen);

  ## Forward Wrapping
  my $MAX_ALLOWED_SIZE = 10000;
  while ( $wrapped_from_stop > 0 && length($sequence) < $MAX_ALLOWED_SIZE) {
	if ($current_stop > $length){
	  $current_stop = $length;
	  $wrapped_from_stop = $current_stop - $length;
	}else {
	  $wrapped_from_stop = 0;
	}
	$sequence .= substr($genome, 0, $current_stop);
  }

  ## Reverse Wrapping- $wrapped_from_start is NEGATIVE
  while ( $wrapped_from_start < 0 && length($sequence) < $MAX_ALLOWED_SIZE) {
	if (abs($wrapped_from_start) > $length) {
	  $sequence = $genome.$sequence;
	  $wrapped_from_start += $length;
	}else {
	  $sequence = substr($genome, $wrapped_from_start) . $sequence;
	  $wrapped_from_start = 0;
	}
  } 

  if ($reverse_complement == 1) {
	$sequence = reverse $sequence;
	$sequence =~ tr /ACGTacgt/TGCAtgca/;
  }
  return $sequence;
}
###############################################################################
# format_sequence: print colorized, neatly printed sequence
###############################################################################
sub format_sequence {
  my %args = @_;
  my $seq = $args{'sequence'} || die "ERROR[format_sequence]: sequence needed\n";
  my $newline = $args{'newline'} || "\n";
  my $color_ref = $args{'color_ref'};

  my $sequence = "";
  my @temp = split //,$seq;
  for (my $m=0;$m<scalar(@temp);$m++) {
	$sequence .= $color_ref->{$m} if (defined ($color_ref->{$m}));
	$sequence .= $temp[$m];
	$sequence .= $newline if (($m % 60) == 59 && $m != scalar(@temp) );
  }
  if ( defined( $color_ref->{scalar(@temp)} ) ){
	print $color_ref->{scalar(@temp)};
  }
  $sequence .=  $newline;
  return $sequence;
}


###############################################################################
# evalSQL: Callback for translating global table variables to names
###############################################################################
sub evalSQL {
  my $sql = shift;

  return eval "\"$sql\"";

} # end evalSQL


sub verify_biosequence_set_ids {
  my %args = @_;
  my $ids = $args{'ids'} || die "biosequence_set_ids need to be passed.";
  
  my $sql = qq~
	SELECT biosequence_set_id,project_id
	FROM $TBPS_BIOSEQUENCE_SET
	WHERE biosequence_set_id IN ( $ids )
	 AND record_status != 'D'
    ~;
    my %project_ids = $sbeams->selectTwoColumnHash($sql);
    my @accessible_project_ids = $sbeams->getAccessibleProjects();
    my %accessible_project_ids;
    foreach my $id ( @accessible_project_ids ) {
      $accessible_project_ids{$id} = 1;
    }

    my @input_ids = split(',',$ids);
    my @verified_ids;
    foreach my $id ( @input_ids ) {

      #### If the requested biosequence_set_id doesn't exist
      if (! defined($project_ids{$id})) {
		$sbeams->reportException(
          state => 'ERROR',
          type => 'BAD CONSTRAINT',
          message => "Non-existent biosequence_set_id = $id specified",
        );

      #### If the project for this biosequence_set is not accessible
      } elsif (! defined($accessible_project_ids{$project_ids{$id}})) {
		$sbeams->reportException(
          state => 'ERROR',
          type => 'PERMISSION DENIED',
          message => "Your current privilege settings do not allow you to access biosequence_set_id = $id.  See project owner to gain permission.",
        );

      #### Else, let it through
      } else {
		push(@verified_ids,$id);
      }

    }

  return @verified_ids;
}
