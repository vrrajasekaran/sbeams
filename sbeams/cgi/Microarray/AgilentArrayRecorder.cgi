#!/usr/local/bin/perl 

###############################################################################
# Program     : AgilentArrayRecorder.cgi
# Author      : Bruz Marzolf <bmarzolf@systemsbiology.org>
# $Id: ArrayRecorder.cgi 5165 2006-10-19 19:18:56Z dcampbel $
#
# Description : This CGI program that allows users to record their
#               Agilent arrays.
#
###############################################################################


###############################################################################
# Get the script set up with everything it will need
###############################################################################
use strict;
use lib qw (../../lib/perl);
use vars qw ($q $sbeams $sbeamsMA $dbh $current_contact_id $current_username
             $current_work_group_id $current_work_group_name
             $current_project_id $current_project_name
             $TABLE_NAME $PROGRAM_FILE_NAME $CATEGORY $DB_TABLE_NAME
             $PK_COLUMN_NAME @MENU_OPTIONS $DEFAULT_COST_SCHEME);

use DBI;
#use CGI;
use CGI::Carp qw(fatalsToBrowser croak);
use POSIX;

use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;

use SBEAMS::Microarray;
use SBEAMS::Microarray::Settings;
use SBEAMS::Microarray::Tables;

use lib "/net/arrays/Pipeline/tools/lib";

#$q = new CGI;
$sbeams = new SBEAMS::Connection;
$sbeamsMA = new SBEAMS::Microarray;
$sbeamsMA->setSBEAMS($sbeams);

###############################################################################
# Global Variables
###############################################################################
$TABLE_NAME = "MA_array_request";
$DEFAULT_COST_SCHEME = 1;
main();

###############################################################################
# Main Program:
#x
# Call $sbeams->InterfaceEntry with pointer to the subroutine to execute if
# the authentication succeeds.
###############################################################################
sub main { 

  #### Do the SBEAMS authentication and exit if a username is not returned
  exit unless ($current_username = $sbeams->Authenticate());

  #### Read in the default input parameters
  my %parameters;
  my $n_params_found = $sbeams->parse_input_parameters(q=>$q,parameters_ref=>\%parameters);
  #$sbeams->printDebuggingInfo($q);
  
  #### Process generic "state" parameters before we start
  $sbeams->processStandardParameters(parameters_ref=>\%parameters);

  #### Print the header, do what the program does, and print footer
  $sbeamsMA->printPageHeader();
  handle_request(parameters_ref=>\%parameters);
  $sbeamsMA->printPageFooter();


} # end main


###############################################################################
# handleRequest
#
# Test for specific form variables and process the request 
# based on what the user wants to do. 
###############################################################################
sub handle_request {
  my %args = @_;
  my $parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$parameters_ref};
  my $tab = $parameters{'tab'} || "main";
  $parameters{'project_id'} = $sbeams->getCurrent_project_id();
  $parameters{'username'} = $sbeams->getCurrent_username();

  ## Print standard page header
  $sbeams->printUserContext();

  #### Decide where to go based on form values
  if ($tab eq 'main') {

#	$sbeamsMA->printPageHeader();
  	print_start_screen(parameters_ref=>\%parameters);
#	$sbeamsMA->printPageFooter();

  }elsif ($tab eq 'arrayCount') {

#	$sbeamsMA->printPageHeader();
	print_array_request_screen(parameters_ref=>\%parameters);
#	$sbeamsMA->printPageFooter();

  }elsif ($tab eq 'arrayInfo') {

#	$sbeamsMA->printPageHeader();
	print_array_info_screen(parameters_ref=>\%parameters);
#	$sbeamsMA->printPageFooter();

  }elsif ($tab eq 'finalize') {

#	$sbeamsMA->printPageHeader();
	finalize(parameters_ref=>\%parameters);
#	$sbeamsMA->printPageFooter();

  }

} # end processRequests



###############################################################################
# Print Start Screen
###############################################################################
sub print_start_screen {
  my %args = @_;
  my $parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$parameters_ref};

  ## Standard Variables
  my $sql;
  my @rows;
  my $current_project = $parameters{'project_selector'} || $sbeams->getCurrent_project_id();
	

  print_start_screen_javascript();

  ## Print Introductory Header
  print qq~
  <H2><U>Welcome to the Microarray Data Entry Interface</U></H2>\n
  <BR>
     This tool is designed as a one-stop interface to recording information about your arrays.
  <BR>
  <FORM METHOD="POST" NAME="arrayProjectChooser"><BR>
  <INPUT TYPE="hidden" NAME="tab" VALUE="">
  $LINESEPARATOR
  <BR>
  <B>
  <FONT COLOR="red">
Step 1: Select Project<BR>
  </FONT>
  Into which project are these arrays going?
  </B>
  <A HREF="ManageTable.cgi?TABLE_NAME=project&ShowEntryForm=1">[Don\'t have a project? Click here to set one up]</A>
  <BR><BR>
  <SELECT NAME="projectSelector" onChange="prepareForSubmission()">
  <OPTION SELECTED VALUE="">--- SELECT FROM ACCESSIBLE PROJECTS ---
~;


  ## Previously, we used only $sbeams->getAccessibleProjects(), but this
  ## causes problems if the user doesn't have administrator access. Augmented
  ## with get_best_permission
  my $project_ids_list = join(',',$sbeams->getWritableProjects()) || '-1';

  $sql = qq~
    SELECT P.project_id, UL.username+' - '+P.name
      FROM $TB_PROJECT P 
      LEFT JOIN $TB_USER_LOGIN UL ON ( P.PI_contact_id = UL.contact_id )
     WHERE P.project_id IN ( $project_ids_list )
       AND P.record_status != 'D'
       AND UL.record_status != 'D'
     GROUP BY P.project_id, P.name, UL.username
     ORDER BY UL.username, P.name
	 ~;
  @rows = $sbeams->selectSeveralColumns($sql);

  foreach my $row_ref (@rows) {
	my ($project_id, $project_name) = @{$row_ref};
	print "  <OPTION VALUE=\"$project_id\">$project_name ($project_id)\n";
  }

  print qq~
  </SELECT>
  </FORM>
	~;
  return;
}

###############################################################################
# Print Start Screen Javascript
###############################################################################
sub print_start_screen_javascript {
	my $javascript = qq~
<SCRIPT LANGUAGE="Javascript">

function prepareForSubmission() {
  document.arrayProjectChooser.tab.value="arrayCount";
  document.arrayProjectChooser.submit();
}

</SCRIPT>		
			~;

	print $javascript;
}



###############################################################################
# Print Array Request Screen
###############################################################################
sub print_array_request_screen {
  my %args = @_;
  my $parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$parameters_ref};

  ## Standard Variables
  my $sql;
  my @rows;
  my $project = $parameters{'projectSelector'};
  my $contact_id = $sbeams->getCurrent_contact_id();
  print_array_request_javascript();

  # Create Slide Type Optionlist
  $sql = qq~
	SELECT slide_type_id, name+' (\$'+CONVERT(varchar(50),price)+')'
	  FROM $TBMA_SLIDE_TYPE
	 WHERE record_status != 'D'
     AND price >= 0
   ORDER BY name
	 ~;
  my $slide_optionlist = $sbeams->buildOptionList($sql);

  # Create Prep Optionlist
  $sql = qq~
	SELECT option_key, option_value
	  FROM $TBMA_ARRAY_REQUEST_OPTION
	 WHERE option_type = 'hybridization_request'
	 ORDER BY sort_order
	 ~;

  my $prep_optionlist = $sbeams->buildOptionList($sql);
  

  # Create Analysis Optionlist
  $sql = qq~
	SELECT option_key, option_value+' (\$'+CONVERT(varchar(50),price)+')'
	  FROM $TBMA_ARRAY_REQUEST_OPTION
	 WHERE option_type = 'scanning_request'
	 ORDER BY sort_order
	 ~;

  my $analysis_optionlist = $sbeams->buildOptionList($sql);
  
  ## Print Introductory Header
  print qq~
  <H2><U>Microarray Data Entry Interface</U></H2>\n
  <FORM METHOD="POST" NAME="arrayCount"><BR>
  <INPUT TYPE="hidden" NAME="tab">
  <INPUT TYPE="hidden" NAME="projectSelector" VALUE="$project">
  $LINESEPARATOR
  <BR>
  <B>
  <FONT COLOR="red">
Step 2: Select \# of Arrays<BR>
  </FONT>
  <TABLE>
  <TR>
   <TD>What are the barcodes of the slides you\'re submitting?&nbsp;&nbsp;</TD>
   <TD><INPUT TYPE="text" NAME="slideBarcodes" SIZE="30"MAXLENGTH="300"></TD>
  </TR>
  <TR>
   <TD>How many arrays are there per slide (usually 1,2,4 or 8)?&nbsp;&nbsp;</TD>
   <TD><INPUT TYPE="text" NAME="arraysPerSlide" SIZE="3"MAXLENGTH="3"></TD>
  </TR>
  <TR>
  	<TD>How many channels are there per slide?&nbsp;&nbsp;</TD>
  	<TD><SELECT NAME="arrayChannels">
       <OPTION SELECTED VALUE="2">2</OPTION>
       <OPTION VALUE="1">1</OPTION>
       </SELECT></TD>
  </TR>
  <TR>
   <TD>What type of arrays are these?</TD>
   <TD><SELECT NAME="arrayType">
       <OPTION SELECTED VALUE="-1">--- SELECT SLIDE TYPE ---
       $slide_optionlist
       </SELECT></TD>
  </TR>
  <TR>
   <TD>What was the requests prep?</TD>
   <TD><SELECT NAME="prepType">
       <OPTION SELECT VALUE="-1">--- SELECT PREP TYPE ---
       $prep_optionlist
       </SELECT></TD>
  </TR>
  <TR>
   <TD>What was the requested analysis?</TD>
   <TD><SELECT NAME="analysisType">
       <OPTION SELECT VALUE="-1">--- SELECT ANALYSIS TYPE ---
       $analysis_optionlist
       </SELECT></TD>
  </TR>
  </TABLE>
  <INPUT TYPE="button" NAME="nextButton" VALUE="Next-->" onClick="prepareForSubmission()">
  </B>

  <BR><BR>

  </FORM>
	~;
  return;
}

###############################################################################
# Print Array Request Javascript
###############################################################################
sub print_array_request_javascript {
  my $javascript = qq~
<SCRIPT LANGUAGE="Javascript">

function prepareForSubmission() {
  //var isNum = verifyNumber();
  //if (isNum == -1) {return;}
  if (document.arrayCount.arrayType.value < 0) {
	alert("Please Select Slide Type");
	return;
  }
  if (document.arrayCount.prepType.value < 0) {
	alert("Please Select Prep Type");
	return;
  }  if (document.arrayCount.analysisType.value < 0) {
	alert("Please Select Analysis Type");
	return;
  }
  document.arrayCount.tab.value="arrayInfo";
  document.arrayCount.submit();
}


function verifyNumber(){
  //need just an integer
  var location = document.arrayCount.slideNumber;
  var testValue = location.value;
  var number = parseInt(testValue);
  if(isNaN(number) || number < 0){
	alert(testValue+" is not valid");
	location.value ="";
	return -1;
  }else {
	return 0;
  }
}//end verifyNumber

</SCRIPT>		
			~;

  print $javascript;
}

###############################################################################
# Print Array Info Screen
###############################################################################
sub print_array_info_screen {
  my %args = @_;
  my $parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$parameters_ref};

  ## Standard Variables
  my $sql;
  my @rows;
  my $slide_barcodes = $parameters{'slideBarcodes'};
  my $arrays_per_slide = $parameters{'arraysPerSlide'};
  my $array_channels = $parameters{'arrayChannels'};
  my $successful = 1;
  my $status_report = "";

  # make sure arrays per slide is not zero
  if( $arrays_per_slide == 0 ) {
    print "<FONT COLOR=\"red\">Number of arrays per slide must be greater than 0.</FONT><BR><BR>\n";
    print "<INPUT TYPE=\"button\" VALUE=\"<--Back\" OnClick=\"history.go(-1)\"><BR>\n";
    return;
  }

  # Parse out barcodes
  my @barcodes;
  my @barcode_ranges = split /,/, $slide_barcodes;
  foreach my $barcode_range (@barcode_ranges) {
    my @barcode_range_ends = split /\-/, $barcode_range;

    # Handle single barcodes vs. ranges
    if( $#barcode_range_ends+1 == 1 ) {
      # Make sure barcode is proper length
      if( length($barcode_range_ends[0]) == 12 ) {
        push @barcodes, $barcode_range_ends[0];
      }
    }
    elsif( $#barcode_range_ends+1 == 2 ) {
      $barcode_range_ends[0] =~ /(\d{7})(\d{5})/;
      my $barcode_start_design = $1;
      my $barcode_start_serial = $2;
      $barcode_range_ends[1] =~ /(\d{7})(\d{5})/;
      my $barcode_end_design = $1;
      my $barcode_end_serial = $2;
      # Make sure barcodes designs are found and the right length
      if( $barcode_start_design ne "" &&
          $barcode_start_design == $barcode_end_design ) {    
        foreach my $serial ($barcode_start_serial..$barcode_end_serial) {
          push @barcodes, $barcode_start_design . $serial;
        }
      }
    }
  }

  # Ensure that these barcodes have not yet been entered in SBEAMS
  my $barcode_list = "";
  for my $n (0..$#barcodes) {
    if( $barcode_list ne "" ) {
      $barcode_list .= ",";
    }
    $barcode_list = $barcode_list . "\'" . $barcodes[$n] . "\'";
  }
  
  $sql = qq~
	SELECT barcode
	  FROM $TBMA_SLIDE
	 WHERE barcode IN ($barcode_list)
     AND record_status != 'D'
	   ~;
  @rows = $sbeams->selectOneColumn($sql);
  if( scalar(@rows) > 0 ) {
    print "<FONT COLOR=\"red\">One or more of these barcodes have already been used.</FONT><BR><BR>\n";
    print "<INPUT TYPE=\"button\" VALUE=\"<--Back\" OnClick=\"history.go(-1)\"><BR>\n";
    return;
  }

  # calculate total number of arrays
  my $array_count = ($#barcodes+1) * $arrays_per_slide;

  # Determine the organism
  $sql = qq~
	SELECT O.organism_name
	  FROM $TB_ORGANISM O
	  LEFT JOIN $TBMA_SLIDE_TYPE S ON (S.organism_id = O.organism_id)
	 WHERE S.slide_type_id = $parameters{'arrayType'}
	   AND S.record_status != 'D'
	   ~;
  @rows = $sbeams->selectOneColumn($sql);
  my $organism = $rows[0];
  $organism =~ tr /A-Z/a-z/;
  
  ###############################
  ## SPECIAL ORGANISM HANDLING ##
  ###############################
  if ($organism eq "halobacterium") {
	$organism = "halo";
  }
  
  ## Create Array Layout Optionlist
  $sql = qq~
	SELECT layout_id
	  FROM $TBMA_ARRAY_LAYOUT
	 WHERE slide_type_id = $parameters{'arrayType'}
     AND record_status != 'D'
	 ~;
  my @rows=$sbeams->selectOneColumn($sql);
  # TODO: proper handling of cases where there isn't exactly 1 array layout
  my $array_layout_id = $rows[0];

  ## Hash of printing batches
  $sql = qq~
	SELECT printing_batch_id
	FROM $TBMA_PRINTING_BATCH
	WHERE slide_type_id = $parameters{'arrayType'}
	AND record_status != 'D'
	~;
  my @rows=$sbeams->selectOneColumn($sql);
  # TODO: proper handling of cases where there isn't exactly 1 print batch
  my $printing_batch_id = $rows[0];

  ## Create Labeling Optionlist
  $sql = qq~
	SELECT labeling_method_id,name
	  FROM $TBMA_LABELING_METHOD
	 ORDER BY sort_order,name
	 ~;
  my $optionlist=$sbeams->buildOptionList($sql);


  ## Create Labeling Protocol Optionlist
  $sql = qq~
SELECT P.protocol_id, P.name
  FROM $TB_PROTOCOL P
  LEFT JOIN $TB_PROTOCOL_TYPE PT ON (PT.protocol_type_id = P.protocol_type_id)
 WHERE PT.name IN ('extract_labeling', 'Genicon Labeling')
   AND P.record_status != 'D'
  ~;
  my $labeling_optionlist=$sbeams->buildOptionList($sql);
 

  ## Create Hybridization Protocol Optionlist
  $sql = qq~
SELECT P.protocol_id, P.name
  FROM $TB_PROTOCOL P
  LEFT JOIN protocol_type PT ON (PT.protocol_type_id = P.protocol_type_id)
 WHERE PT.name = 'hybridization'
   AND P.record_status != 'D'
 ~;
  my $hybridization_optionlist = $sbeams->buildOptionList($sql);


  ## Create Scanning Protocol Optionlist
  $sql = qq~
SELECT P.protocol_id, P.name
  FROM $TB_PROTOCOL P
  LEFT JOIN protocol_type PT ON (PT.protocol_type_id = P.protocol_type_id)
 WHERE PT.name = 'array_scanning'
   AND P.record_status != 'D'
 ~;
  my $scanning_optionlist = $sbeams->buildOptionList($sql);


  ## Create Quantitation Protocol Optionlist
  $sql = qq~
SELECT P.protocol_id, P.name
  FROM $TB_PROTOCOL P
  LEFT JOIN protocol_type PT ON (PT.protocol_type_id = P.protocol_type_id)
 WHERE PT.name = 'image_analysis'
   AND P.record_status != 'D'
 ~;
  my $spotfinding_optionlist = $sbeams->buildOptionList($sql);

  ## Print Introductory Header
  print qq~
  <H2><U>Microarray Data Entry Interface</U></H2>\n
  <FORM METHOD="POST" NAME="arrayInfo"><BR>
  <INPUT TYPE="hidden" NAME="tab">
  <INPUT TYPE="hidden" NAME="project" VALUE="$parameters{'projectSelector'}">
  <INPUT TYPE="hidden" NAME="arrayCount" VALUE="$array_count">
  <INPUT TYPE="hidden" NAME="arraysPerSlide" VALUE="$parameters{'arraysPerSlide'}">
  <INPUT TYPE="hidden" NAME="arrayChannels" VALUE="$parameters{'arrayChannels'}">
  <INPUT TYPE="hidden" NAME="slideType" VALUE="$parameters{'arrayType'}">
  <INPUT TYPE="hidden" NAME="arrayLayout" VALUE="$array_layout_id">
  <INPUT TYPE="hidden" NAME="printingBatch" VALUE="$printing_batch_id">
  <INPUT TYPE="hidden" NAME="analysisType" VALUE="$parameters{'analysisType'}">
  <INPUT TYPE="hidden" NAME="prepType" VALUE="$parameters{'prepType'}">
  $LINESEPARATOR
  <BR>
  <B>
  <FONT COLOR="red">
Step 3: Array Information<BR>
  </FONT>
  </B>
  <BR>
  $status_report<BR>
  <TABLE BORDER>
  <TR BGCOLOR="#1C3887">
   <TD><FONT COLOR="white">Slide Barcode</FONT></TD>
   <TD><FONT COLOR="white">Array \# on Slide</FONT></TD>
   <TD><FONT COLOR="white">Sample \#1 Name</FONT></TD>
   <TD><FONT COLOR="white">Sample \#1 Label</FONT></TD>
   <TD><FONT COLOR="white">Dye Lot \#</FONT></TD>
   ~;
   
   if($array_channels == 2) {
   	print qq~
   <TD><FONT COLOR="white">Sample \#2 Name</FONT></TD>
   <TD><FONT COLOR="white">Sample \#2 Label</FONT></TD>
   <TD><FONT COLOR="white">Dye Lot \#</FONT></TD>
    ~;
   }
   
   print qq~
   <TD><FONT COLOR="white">Labeling Protocol</FONT></TD>
   <TD><FONT COLOR="white">Date Labeled (YYYY-MM-DD)</FONT></TD>
   <TD><FONT COLOR="white">Hybridization Protocol</FONT></TD>
   <TD><FONT COLOR="white">Date Hybridized(YYYY-MM-DD)</FONT></TD>
   <TD><FONT COLOR="white">Scanning Protocol</FONT></TD>
   <TD><FONT COLOR="white">Scan Date(YYYY-MM-DD)</FONT></TD>
   <TD><FONT COLOR="white">Scan Data Flag</FONT></TD>
   <TD><FONT COLOR="white">Image Location</FONT></TD>
   <TD><FONT COLOR="white">Quantitation Protocol</FONT></TD>
   <TD><FONT COLOR="white">Quantitation Date(YYYY-MM-DD)</FONT></TD>
   <TD><FONT COLOR="white">Quantitation Data Flag</FONT></TD>
   <TD><FONT COLOR="white">Quantitation File Location</FONT></TD>
  </TR>
  <TR BGCOLOR="#1C3887">
   <TD><!-- Slide Barcode --></TD>
   <TD><!-- Array Number on Slide --></TD>
  <TD><INPUT TYPE="TEXT" NAME="sample0checked" VALUE="- Set Checked To -" onFocus="blank(this)">
       <INPUT TYPE="button" VALUE="Apply" onClick="Javascript:setChecked(0);"></TD>
   <TD><SELECT NAME="sample0labmeth_all" onChange="Javascript:setAllMethods(0);">
   <OPTION VALUE="-1">--- SET ALL LABELING METHODS TO: ---
   $optionlist;
   </SELECT>
   <TD><!-- Sample 1 Dye Lot --></TD>
      ~;
   
   if($array_channels == 2) {
   	print qq~
   <TD><INPUT TYPE="TEXT" NAME="sample1checked" VALUE="- Set Checked To -"onFocus="blank(this)">
       <INPUT TYPE="button" VALUE="Apply" onClick="Javascript:setChecked(1);"></TD>
   <TD><SELECT NAME="sample1labmeth_all" onChange="Javascript:setAllMethods(1);">
   <OPTION VALUE="-1">--- SET ALL LABELING METHODS TO: ---
   $optionlist;
   </SELECT></TD>
   <TD><!-- Sample 2 Dye Lot --></TD>
   ~;
   }
   
   print qq~
   <TD><SELECT NAME="labprot_all" onChange="Javascript:setAllMethods(2);">
   <OPTION VALUE="-1">--- SET ALL LABELING PROTOCOLS TO: ---
   $labeling_optionlist;
   </SELECT></TD>
   <TD ALIGN="CENTER"><INPUT TYPE="button" VALUE="Set to Now" onClick="Javascript:clickedNow('lab');"></TD>
   <TD><SELECT NAME="hybprot_all" onChange="Javascript:setAllMethods(3);">
   <OPTION VALUE="-1">--- SET ALL HYBRIDIZATION PROTOCOLS TO: ---
   $hybridization_optionlist;
   </SELECT></TD>
   <TD ALIGN="CENTER"><INPUT TYPE="button" VALUE="Set to Now" onClick="Javascript:clickedNow('hyb');"></TD>
   <TD><SELECT NAME="scanprot_all" onChange="Javascript:setAllMethods(4);">
   <OPTION VALUE="-1">--- SET ALL SCANNING PROTOCOLS TO: ---
   $scanning_optionlist;
   </SELECT></TD>
   <TD ALIGN="CENTER"><INPUT TYPE="button" VALUE="Set to Now" onClick="Javascript:clickedNow('scan');"></TD>
   <TD><SELECT NAME="scanflag_all" onChange="Javascript:setAllMethods(5);">
   <OPTION VALUE="-1">--- SET ALL DATA FLAGS TO: ---
   <OPTION VALUE="OK">OK
   <OPTION VALUE="BAD">BAD
   </SELECT></TD>
   <TD><!-- Image Location --></TD>
   <TD><SELECT NAME="quantprot_all" onChange="Javascript:setAllMethods(6);">
   <OPTION VALUE="-1">--- SET ALL SPOTFINDING PROTOCOLS TO: ---
   $spotfinding_optionlist;
   </SELECT></TD>
   <TD ALIGN="CENTER"><INPUT TYPE="button" VALUE="Set to Now" onClick="Javascript:clickedNow('quant');"></TD>
   <TD><SELECT NAME="quantflag_all" onChange="Javascript:setAllMethods(7);">
   <OPTION VALUE="-1">--- SET ALL DATA FLAGS TO: ---
   <OPTION VALUE="OK">OK
   <OPTION VALUE="BAD">BAD
   </SELECT></TD>
   <TD></TD>	 
  </TR>
  ~;

my $m = 0;
foreach my $barcode (@barcodes) {
  $barcode =~ /\A\d{2}(\d{5}).*/;
  my $design_id = $1;
  foreach my $array (1..$arrays_per_slide) {
    # if there's only one array per slide, don't tack the array number onto the end
    # of the barcode
    if($arrays_per_slide == 1) {
      $array = "";
    }
    print qq~
    <TR BGCOLOR="#CCFFFF">
     <TD><INPUT TYPE="hidden" NAME="barcode_$m" VALUE="$barcode">$barcode</TD>
     <TD><INPUT TYPE="hidden" NAME="array_$m" VALUE="$array">$array</TD>
    <TD><NOBR><INPUT TYPE="checkbox" NAME="sample0check_$m">
               <INPUT TYPE="text" NAME="sample0name_$m" SIZE="25" MAXLENGTH="255"></NOBR></TD>
     <TD><SELECT NAME="sample0labmeth_$m">
         <OPTION VALUE="-1" SELECTED>
       $optionlist
       </SELECT></TD>
     <TD><INPUT TYPE="text" NAME="sample0dye_$m" SIZE="6" MAXLENGTH="20"></TD>
        ~;
   
   if($array_channels == 2) {
   	print qq~
     <TD><NOBR><INPUT TYPE="checkbox" NAME="sample1check_$m">
               <INPUT TYPE="text" NAME="sample1name_$m" SIZE="25" MAXLENGTH="255"></NOBR></TD>
     <TD><SELECT NAME="sample1labmeth_$m">
         <OPTION VALUE="-1" SELECTED>
       $optionlist
       </SELECT></TD>
     <TD><INPUT TYPE="text" NAME="sample1dye_$m" SIZE="6" MAXLENGTH="20"></TD>
     ~;
   }
   
     print qq~
     <TD><SELECT NAME="labprot_$m">
         <OPTION VALUE="-1" SELECTED>
       $labeling_optionlist
       </SELECT></TD>
     <TD><INPUT TYPE="text" NAME="labdate_$m" SIZE="25"></TD>	   
     <TD><SELECT NAME="hybprot_$m">
         <OPTION VALUE="-1" SELECTED>
         $hybridization_optionlist
       </SELECT></TD>
     <TD><INPUT TYPE="text" NAME="hybdate_$m" SIZE="25"></TD>
     <TD><SELECT NAME="scanprot_$m">
         <OPTION VALUE="-1" SELECTED>
         $scanning_optionlist
       </SELECT></TD>
     <TD><INPUT TYPE="text" NAME="scandate_$m" SIZE="25"></TD>
     <TD><SELECT NAME="scanflag_$m">
         <OPTION VALUE="-1" SELECTED>
         <OPTION VALUE="OK">OK
       <OPTION VALUE="BAD">BAD
       </SELECT></TD>
     <TD><INPUT TYPE="text" NAME="scanfile_$m" SIZE="50" VALUE = "\/net\/arrays\/Scans\/Agilent\/$barcode"></TD>
     <TD><SELECT NAME="quantprot_$m">
         <OPTION VALUE="-1" SELECTED>
         $spotfinding_optionlist
       </SELECT></TD>
     <TD><INPUT TYPE="text" NAME="quantdate_$m" SIZE="25"></TD>
     <TD><SELECT NAME="quantflag_$m">
         <OPTION VALUE="-1" SELECTED>
         <OPTION VALUE="OK">OK
       <OPTION VALUE="BAD">BAD
       </SELECT></TD>
     <TD><INPUT TYPE="text" NAME="quantfile_$m" SIZE = "50" VALUE = "\/net\/arrays\/Quantitation\/Agilent\/$design_id\/$barcode$array.csv"></TD>
    </TR>
    ~;
    $m++
  }
}
print qq~
  </TABLE>
  <INPUT TYPE="button" NAME="nextButton" VALUE="Done!" onClick="prepareForSubmission();">
  <BR><BR>
  </FORM>
	~;

  print_array_info_javascript($array_count);
  

  return;
}

###############################################################################
# Print Array Info Javascript
###############################################################################
sub print_array_info_javascript {
  my $array_requests = shift @_;
  my $javascript = qq~
<SCRIPT LANGUAGE="Javascript">
    ~;

  my $samples = 2;
  for (my $m=0;$m<$samples;$m++) {
	$javascript .= "var sample".$m."_array = new Array($array_requests);\n";
	$javascript .= "var check".$m."_array = new Array($array_requests);\n";
	$javascript .= "var name".$m."_array = new Array($array_requests);\n";
  }

  $javascript .= "var labprot_array = new Array($array_requests);\n";
  $javascript .= "var hybprot_array = new Array($array_requests);\n";
  $javascript .= "var scanprot_array = new Array($array_requests);\n";
  $javascript .= "var quantprot_array = new Array($array_requests);\n";
  $javascript .= "var scanflag_array = new Array($array_requests);\n";
  $javascript .= "var quantflag_array = new Array($array_requests);\n";
  $javascript .= "var labdate_array = new Array($array_requests);\n";
  $javascript .= "var hybdate_array = new Array($array_requests);\n";
  $javascript .= "var scandate_array = new Array($array_requests);\n";
  $javascript .= "var quantdate_array = new Array($array_requests);\n";

  for (my $i=0;$i<$array_requests;$i++) {
	$javascript .= "labprot_array[".$i."] = document.arrayInfo.labprot_".$i.";\n";
	$javascript .= "hybprot_array[".$i."] = document.arrayInfo.hybprot_".$i.";\n";
	$javascript .= "scanprot_array[".$i."] = document.arrayInfo.scanprot_".$i.";\n";
	$javascript .= "quantprot_array[".$i."] = document.arrayInfo.quantprot_".$i.";\n";
	$javascript .= "scanflag_array[".$i."] = document.arrayInfo.scanflag_".$i.";\n";
	$javascript .= "quantflag_array[".$i."] = document.arrayInfo.quantflag_".$i.";\n";
	$javascript .= "labdate_array[".$i."] = document.arrayInfo.labdate_".$i.";\n";
	$javascript .= "hybdate_array[".$i."] = document.arrayInfo.hybdate_".$i.";\n";
	$javascript .= "scandate_array[".$i."] = document.arrayInfo.scandate_".$i.";\n";
	$javascript .= "quantdate_array[".$i."] = document.arrayInfo.quantdate_".$i.";\n";
	for (my $j=0;$j<$samples;$j++) {
	  $javascript .= "sample".$j."_array[".$i."] = document.arrayInfo.sample".$j."labmeth_".$i.";\n";
	  $javascript .= "check".$j."_array[".$i."] = document.arrayInfo.sample".$j."check_".$i.";\n";
	  $javascript .= "name".$j."_array[".$i."] = document.arrayInfo.sample".$j."name_".$i.";\n";
	}
  }

  $javascript .= qq~

function blank(location) {
  location.value = "";
}

function setChecked(sample_ID) {
  var template;
  if (sample_ID == 0) {
	template = document.arrayInfo.sample0checked.value;
	for (var n=0;n<check0_array.length;n++) {
	  if (check0_array[n].checked){
		name0_array[n].value = template;
	  }
	  check0_array[n].checked = false;
	}
	document.arrayInfo.sample0checked.value = "- Set Checked To -";
  }else if (sample_ID == 1){
	template = document.arrayInfo.sample1checked.value;
	for (var n=0;n<check1_array.length;n++) {
	  if (check1_array[n].checked) {
		name1_array[n].value = template;
	  }
	  check1_array[n].checked = false;
	}
	document.arrayInfo.sample1checked.value = "- Set Checked To -";
  }
}

function clickedNow(id) {
  today = new Date();
  date_value =
      today.getFullYear() + "-" + (today.getMonth()+1) + "-" +
      today.getDate() + " " +
      today.getHours() + ":" +today.getMinutes();


  if (id == "quant") {
	for (var n=0; n<quantdate_array.length;n++){
	  quantdate_array[n].value=date_value;
    }
  }
  if (id == "scan") {
	for (var n=0; n<scandate_array.length;n++){
	  scandate_array[n].value=date_value;
    }
  }
  if (id == "hyb") {
	for (var n=0; n<hybdate_array.length;n++){
	  hybdate_array[n].value=date_value;
    }
  }
  if (id == "lab") {
	for (var n=0; n<labdate_array.length;n++){
	  labdate_array[n].value=date_value;
    }
  }
  return;
}

function setAllMethods(id){
  if (id == 0){
    for (var n=0; n<sample0_array.length;n++){
	sample0_array[n].options[document.arrayInfo.sample0labmeth_all.selectedIndex].selected=true;
    }
	document.arrayInfo.sample0labmeth_all.selectedIndex = 0;
  }
  if (id == 1){
    for (var n=0; n<sample1_array.length;n++){
	sample1_array[n].options[document.arrayInfo.sample1labmeth_all.selectedIndex].selected=true;
    }
	document.arrayInfo.sample1labmeth_all.selectedIndex = 0;
  }
  if (id == 2){
    for (var n=0; n<labprot_array.length;n++){
	labprot_array[n].options[document.arrayInfo.labprot_all.selectedIndex].selected=true;
    }
	document.arrayInfo.labprot_all.selectedIndex = 0;
  }
  if (id == 3){
    for (var n=0; n<hybprot_array.length;n++){
	hybprot_array[n].options[document.arrayInfo.hybprot_all.selectedIndex].selected=true;
    }
	document.arrayInfo.hybprot_all.selectedIndex = 0;
  }
  if (id == 4){
    for (var n=0; n<scanprot_array.length;n++){
	scanprot_array[n].options[document.arrayInfo.scanprot_all.selectedIndex].selected=true;
    }
	document.arrayInfo.scanprot_all.selectedIndex = 0;
  }
  if (id == 5){
    for (var n=0; n<scanflag_array.length;n++){
	scanflag_array[n].options[document.arrayInfo.scanflag_all.selectedIndex].selected=true;
    }
	document.arrayInfo.scanflag_all.selectedIndex = 0;
  }
  if (id == 6){
    for (var n=0; n<quantprot_array.length;n++){
	quantprot_array[n].options[document.arrayInfo.quantprot_all.selectedIndex].selected=true;
    }
	document.arrayInfo.quantprot_all.selectedIndex = 0;
  }
  if (id == 7){
    for (var n=0; n<quantflag_array.length;n++){
	quantflag_array[n].options[document.arrayInfo.quantflag_all.selectedIndex].selected=true;
    }
	document.arrayInfo.quantflag_all.selectedIndex = 0;
  }
}

function prepareForSubmission() {
  document.arrayInfo.tab.value="finalize";
  document.arrayInfo.submit();
}

function verifyNumber(){
  //need just an integer
  var location = document.arrayInfo.slideNumber;
  var testValue = location.value;
  var number = parseInt(testValue);
  if(isNaN(number) || number < 0){
	alert(testValue+" is not valid");
	location.value ="";
	return -1;
  }else {
	return 0;
  }
}//end verifyNumber

function setLocations (slide_barcode, protocol_name, QALocation, scanLocation) {
  setImageLocation(array_name, scanLocation);
  setQALocation(array_name, protocol_name, QALocation);
  return;
}

function setImageLocation(array_name, scanLocation) {
    if (array_name.substr(array_name.length-9,99) == " - *DONE*") {
      array_name = array_name.substr(0,array_name.length-9);
    }

    serial_number = array_name;
    if (serial_number.substr(serial_number.length-1,99) >= "A") {
      serial_number = serial_number.substr(0,array_name.length-1);
    }

    today = new Date();
    date_value =
	"" + today.getFullYear() +
	addLeadingZeros((today.getMonth()+1),2) +
	addLeadingZeros(today.getDate(),2)
	date_value = date_value.substr(2,6);

    start_group = Math.round(serial_number/100-0.5)*100+1;
    start_group = addLeadingZeros(start_group.toString(),5);

    end_group = Math.round(serial_number/100+0.5)*100;
    end_group = addLeadingZeros(end_group.toString(),5);

    array_name = addLeadingZeros(array_name.toString(),5);

    scanLocation.value =
	"/net/arrays/ScanArray_Images/" +
	start_group + "-"+ end_group + "/" +
	array_name + "_" + date_value;
    return;
}

function addLeadingZeros(instring,ndigits) {
  instring = instring.toString();
  while (instring.length < ndigits) { instring = "0" + instring; }
  return instring;
}

function setQALocation(array_name, protocol_name, QALocation) {
  array_name = array_name.toString();

  //Shouldn\'t need, but keep as a safety measure anyway
  if (array_name.substr(array_name.length-9,99) == " - *DONE*") {
    array_name = array_name.substr(0,array_name.length-9);
  }
  array_name = addLeadingZeros(array_name,5);

  start_group = Math.round(array_name/100-0.5)*100+1;
  start_group = addLeadingZeros(start_group.toString(),5);

  end_group = Math.round(array_name/100+0.5)*100;
  end_group = addLeadingZeros(end_group.toString(),5);

  protocol_name = protocol_name.toString();
  extension = ".csv";
  
  if (protocol_name.search(/QuantArray/i)>-1) { extension = ".qa"; }
  if (protocol_name.search(/Dapple/i)>-1) { extension = ".dapple"; }

  QALocation.value =
      "/net/arrays/Quantitation/" +
      start_group + "-"+ end_group + "/" +
      array_name + extension;

  return;
}
</SCRIPT>	   
			~;

  print $javascript;
}




###############################################################################
# finalize
# NOTE: the 'array_name' field within microarray.dbo.array is named
#       the same as the 'slide_number' field in microarray.dbo.slide.
#       Also, the page is hinged upon the standardized naming of print
#       batches.  We can intuit the print batch based upon slide number
#       and organism (from slide type).  However, if the naming convention is 
#       different, this won't work!!
###############################################################################
sub finalize {
  my %args = @_;
  my $parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$parameters_ref};
  
  ## Standard Variables
  my $sql;
  my @rows;
  my $contact_id = $sbeams->getCurrent_contact_id();

  ## Other Variables
  my $project = $parameters{'project'};
  my $cost_scheme_id = $DEFAULT_COST_SCHEME unless ( $parameters{'cost_scheme_id'} >= 1 );
  my $successful = 1;  
  my $error_messages ="";
  my $slide_type_id = $parameters{'slideType'};
  my $analysis_type = $parameters{'analysisType'};
  my $array_layout_id = $parameters{'arrayLayout'};
  my $printing_batch_id = $parameters{'printingBatch'};
  my %array_info;
  
  ## Determine Number of arrays
  my $array_count = $parameters{'arrayCount'};

  ## Number of channels
  my $array_channels = $parameters{'arrayChannels'};

  ## Print Introductory Header
  print qq~
  <H2><U>Welcome to the Microarray Data Entry Interface</U></H2>\n
  <BR>
     This tool is designed as a one-stop interface to recording information about your arrays.
  <BR>
  <FORM METHOD="POST" NAME="arrayProjectChooser"><BR>
  <INPUT TYPE="hidden" NAME="tab" VALUE="">
  $LINESEPARATOR
  <BR>
  ~;

  ######################################################################################
  # Verify that we won't have any problems INSERTing the records.                      #
  # Intuit print batch and array layout.  SKETCHY!  Is there a cleaner way to do this? #
  ######################################################################################

  # Determine the organism
  $sql = qq~
	SELECT O.organism_name
	  FROM $TB_ORGANISM O
	  LEFT JOIN $TBMA_SLIDE_TYPE S ON (S.organism_id = O.organism_id)
	 WHERE S.slide_type_id = $slide_type_id
	   AND S.record_status != 'D'
	   ~;
  @rows = $sbeams->selectOneColumn($sql);
  my $organism = $rows[0];
  $organism =~ tr /A-Z/a-z/;
  
  ###############################
  ## SPECIAL ORGANISM HANDLING ##
  ###############################
  if ($organism eq "halobacterium") {
	  $organism = "halo";
  }
  
  ## Verify that all the prerequisite records are created.
  for (my $m=0;$m<$array_count;$m++) {

    my $file = $parameters{'quantfile_'.$m}; 
    my $array = $parameters{'barcode_'.$m} . $parameters{'array_'.$m};
    $array_info{$array,'quantitation_file'} = $file;

    ## Verify that Array Locations are correct
    if (-e $file) {
      print "<FONT COLOR=\"green\">File $file: Location VERIFIED</FONT><BR>\n";
    }else {
      $error_messages.= "<FONT COLOR=\"red\">$file is not valid</FONT><BR>\n";
      $successful = 0;
    }

    ## Verify that record from 'array' table exists and isn't taken
    $sql = qq~
      SELECT COUNT(*)
        FROM $TBMA_ARRAY
       WHERE array_name = '$array'
       ~;
    @rows = $sbeams->selectOneColumn($sql);
    unless (scalar(@rows) == 1) {
      $successful = 0;
      $error_messages .= qq~
      <FONT COLOR=\"red\">Array \#$array already has a record in SBEAMS.  Contact Array Core.</FONT><BR>
      ~;
    }
  }

  ## Determine whether Agilent slide model exists
  my $slide_model_id;
  $sql = qq~
    SELECT slide_model_id
      FROM $TBMA_SLIDE_MODEL
     WHERE vendor_name = 'Agilent'
       AND model_name = 'Agilent'
       AND record_status != 'D'
  	   ~;
  @rows = $sbeams->selectOneColumn($sql);
  
  # pick the first Agilent model if there is one
  if( scalar(@rows) > 0 ) {
    $slide_model_id = $rows[0];
  }
  # or log an error
  else {
		print "<FONT COLOR=\"red\">Agilent slide model record not found. Contact Array Core.</FONT><BR>";
		return;
  }


  ## Determine whether or not agilent slide lot exists
  my $slide_lot_id;
  $sql = qq~
    SELECT slide_lot_id
      FROM $TBMA_SLIDE_LOT
     WHERE slide_model_id = $slide_model_id
       AND record_status != 'D'
  	   ~;
  @rows = $sbeams->selectOneColumn($sql);

  # pick the first Agilent model if there is one
  if( scalar(@rows) > 0 ) {
    $slide_lot_id = $rows[0];
  }
  # or log an error
  else {
	  $successful = 0;
	  $error_messages .= qq~
		<FONT COLOR=\"red\">Agilent slide lot record not found. Contact Array Core.</FONT><BR>
		~;
  }

  # Agilent arrays are referred to by their barcodes, so
  # for slide_number, the next available number from
  # 3000001-3999999 is used as an arbitrary unique identifier
  $sql = qq~
  	SELECT MAX(slide_number)
      FROM $TBMA_SLIDE
     WHERE slide_number > 3000001
       AND slide_number < 4000000
       AND record_status != 'D'
       ~;
	@rows = $sbeams->selectOneColumn($sql);

  # set current slide number as one above highest in Agilent slide number range
  my $slide_number = $rows[0] + 1;
  if( $slide_number < 3000001 || $slide_number >= 4000000 ) {
    $slide_number = 3000001;
  }

  ## If there are any errors, report them now or continue with adding records to SBEAMS
  unless ($successful == 1) {
	print $error_messages;
	print "<BR><B>Due to the listed errors, this transaction failed.  Please go back and make the corrections.</B>";
	print "<INPUT TYPE=\"button\" VALUE=\"<--Back\" OnClick=\"history.go(-1)\"><BR>\n";
	return;
  }

  #########################################################
  ## At this point, we should be clear to INSERT records ##
  #########################################################
  
  # Determine price of all the arrays (NOTE: NO LABELING/HYBRIDIZATION COSTS ARE INCLUDED)
  $sql =  "SELECT price FROM $TBMA_ARRAY_REQUEST_OPTION WHERE option_key = '$analysis_type' AND option_type LIKE 'scanning%' ";
  @rows = $sbeams->selectOneColumn($sql);
  my $scan_cost = $rows[0];
  
  $sql = " SELECT price FROM $TBMA_SLIDE_TYPE WHERE slide_type_id = '$slide_type_id' ";
  @rows = $sbeams->selectOneColumn($sql);
  my $array_cost = $rows[0];

  my $price = $scan_cost + ($array_count * $array_cost);

  ## Start the transaction
#  print "<BR>\n BEGIN TRANSACTION <BR>\n";
  $sbeams->executeSQL("BEGIN TRANSACTION");

  ## Insert Array Request Records
  my %rowdata;
  my $rowdata_ref;

  $rowdata{'contact_id'} = $contact_id;
  $rowdata{'project_id'} = $project;
  $rowdata{'cost_scheme_id'} = $cost_scheme_id;
  $rowdata{'slide_type_id'} = $slide_type_id;
  $rowdata{'n_slides'} = $array_count;
  $rowdata{'n_samples_per_slide'} = $array_channels;
  $rowdata{'hybridization_request'} = $parameters{'prepType'};
  $rowdata{'scanning_request'}= $analysis_type;
  $rowdata{'request_status'} = "Submitted";
  $rowdata{'price'} = $price;
 	
  $rowdata_ref= \%rowdata;
  my $array_request_id;
  $array_request_id =  $sbeams->updateOrInsertRow(table_name=>$TBMA_ARRAY_REQUEST,
												  rowdata_ref=>$rowdata_ref,
												  insert=>1,
												  return_PK=>1,
												  add_audit_parameters=>1
												  );
  undef %rowdata;

  ## INSERT array_request_slide record for each array
  for (my $m=0;$m<$array_count;$m++) {
  my $barcode = $parameters{'barcode_'.$m};
  my $array = $barcode . $parameters{'array_'.$m};

	## Format array_id so that it's a five digit number (e.g. '2886' --> '02886')
  # BUGFIX - this actually never ran until the array ids got > 9999, whereupon
  # it caused an infinite loop.  Will comment out, since it was a no-op
#	while ($array =~ /\d{5}/){
#	  $array = "0".$array;
#	}

	$rowdata{'array_request_id'} = $array_request_id;
	$rowdata{'slide_index'}= $m;
	$rowdata_ref = \%rowdata;

	my $array_request_slide_id;
	$array_request_slide_id = $sbeams->updateOrInsertRow(table_name=>$TBMA_ARRAY_REQUEST_SLIDE,
														 rowdata_ref=>$rowdata_ref,
														 insert=>1,
														 return_PK=>1,
														 add_audit_parameters=>1);
	$array_info{$array,'array_request_id'} = $array_request_id;
	$array_info{$array,'array_request_slide_id'} = $array_request_slide_id;
	undef %rowdata;

  ## INSERT array_request_sample, labeling record, and hybridization
	my ($sample0_name, $sample1_name);
  if( length($parameters{'sample0name_'.$m}) > 48 ) {
    $sample0_name = substr( $parameters{'sample0name_'.$m}, 0, 46)."..";
  }
	if( $array_channels == 2 && length($parameters{'sample1name_'.$m}) > 48 ) {
		$sample1_name  = substr( $parameters{'sample1name_'.$m}, 0, 46)."..";
  }
 
	for (my $sample_index=0;$sample_index<$array_channels;$sample_index++) {
	  ## INSERT array_request_sample record
	  $rowdata{'array_request_slide_id'} = $array_request_slide_id;
	  $rowdata{'sample_index'} = $sample_index;

    my $full_name = $parameters{'sample'.$sample_index.'name_'.$m};
    $rowdata{'full_name'} = $full_name;
    $rowdata{'name'} = substr($full_name, 0, 46)."..";
                 
	  $rowdata{'labeling_method_id'} = $parameters{'sample'.$sample_index.'labmeth_'.$m};
	  $rowdata_ref = \%rowdata;

	  my $array_request_sample_id;
	  $array_request_sample_id = $sbeams->updateOrInsertRow (table_name=>$TBMA_ARRAY_REQUEST_SAMPLE,
															 rowdata_ref=>$rowdata_ref,
															 insert=>1,
															 return_PK=>1,
															 add_audit_parameters=>1);
	  $array_info{$array,'array_request_sample_'.$sample_index.'_id'} = $array_request_sample_id;
	  undef %rowdata;

	  ## INSERT Labeling Record
	  $rowdata{'array_request_sample_id'} = $array_request_sample_id;
	  $rowdata{'protocol_id'} = $parameters{'labprot_'.$m};
	  $rowdata{'date_labeled'} = $parameters{'labdate_'.$m};
	  $rowdata{'dilution_factor'} = "-1";
	  $rowdata{'volume'} = "-1";
	  $rowdata{'absorbance_lambda'} = "-1";
	  $rowdata{'absorbance_260'} = "-1";
	  $rowdata{'dye_lot_number'} = $parameters{'sample'.$sample_index.'dye_'.$m};
	  $rowdata_ref = \%rowdata;
	  my $labeling_id;
	  $labeling_id = $sbeams->updateOrInsertRow (table_name=>$TBMA_LABELING,
												 rowdata_ref=>$rowdata_ref,
												 insert=>1,
												 add_audit_parameters=>1);
	  $array_info{$array,'labeling_id'} = $labeling_id;
	  undef %rowdata;
	}

  ## INSERT Slide Record
 	$rowdata{'slide_lot_id'} = $slide_lot_id;
	$rowdata{'slide_number'} = $slide_number;
	$rowdata{'barcode'} = $barcode;
	$rowdata{'comment'} = 'Created by AgilentArrayRecorder.cgi.';
	$rowdata_ref = \%rowdata;

  my $slide_id;
	$slide_id = $sbeams->updateOrInsertRow(table_name=>$TBMA_SLIDE,
										   rowdata_ref=>$rowdata_ref,
										   insert=>1,
										   return_PK=>1,
										   add_audit_parameters=>1);

  $array_info{$array,'slide_id'} = $slide_id;
  
  undef %rowdata;

  # increment slide number for next array
  $slide_number++;

	## INSERT Array Record
  $rowdata{'project_id'} = $project;
	$rowdata{'layout_id'} = $array_layout_id;
	$rowdata{'printing_batch_id'} = $printing_batch_id;
	$rowdata{'slide_id'} = $slide_id;
	$rowdata{'array_name'} = $array;
	$rowdata{'array_request_slide_id'} = $array_request_slide_id;
	$rowdata_ref = \%rowdata;

	my $array_id;
	$array_id = $sbeams->updateOrInsertRow(table_name=>$TBMA_ARRAY,
										   rowdata_ref=>$rowdata_ref,
										   insert=>1,
										   return_PK=>1,
										   add_audit_parameters=>1);

	## Format array_id so that it's a five digit number (e.g. '2886' --> '02886')
	while ($array_id =~ /\A\d{5}\Z/){
	  $array_id = "0".$array_id;
	}

	$array_info{$array,'array_id'} = $array_id;


	undef %rowdata;

	## INSERT Hybridization Record
	$rowdata{'name'} = $sample0_name.'_vs_'.$sample1_name;
	$rowdata{'array_id'} = $array_id;
	$rowdata{'protocol_id'} = $parameters{'hybprot_'.$m};
	$rowdata{'date_hybridized'} = $parameters{'hybdate_'.$m};
	$rowdata{'comment'} = 'Created by AgilentArrayRecorder.cgi.';
	$rowdata_ref = \%rowdata;
	my $hybridization_id;
	$hybridization_id = $sbeams->updateOrInsertRow (table_name=>$TBMA_HYBRIDIZATION,
													rowdata_ref=>$rowdata_ref,
													insert=>1,
													return_PK=>1,
													add_audit_parameters=>1);
	$array_info{$array,'hybridization_id'} = $hybridization_id;
	undef %rowdata;
	

	## INSERT array_scan record
	$rowdata{'array_id'} = $array_id;
	$rowdata{'protocol_id'} = $parameters{'scanprot_'.$m};
	$rowdata{'data_flag'} = $parameters{'scanflag_'.$m};
	$rowdata{'date_scanned'} = $parameters{'scandate_'.$m};
	$rowdata{'resolution'} = '10.00';
	$rowdata{'stage_location'} = $parameters{'scanfile_'.$m};
	$rowdata{'comment'} = 'Created by AgilentArrayRecorder.cgi.';
	$rowdata_ref = \%rowdata;
	my $array_scan_id;
	$array_scan_id = $sbeams->updateOrInsertRow (table_name=>$TBMA_ARRAY_SCAN,
												 rowdata_ref=>$rowdata_ref,
												 insert=>1,
												 return_PK=>1,
												 add_audit_parameters=>1);
	$array_info{$array,'array_scan_id'} = $array_scan_id;
	undef %rowdata;

	## INSERT array_quantitation_record
	$rowdata{'array_scan_id'} = $array_scan_id;
	$rowdata{'protocol_id'} = $parameters{'quantprot_'.$m};
	$rowdata{'stage_location'} = $parameters{'quantfile_'.$m};
	$rowdata{'data_flag'} = $parameters{'quantflag_'.$m};
	$rowdata{'date_quantitated'} = $parameters{'quantdate_'.$m};
	$rowdata{'comment'} = 'Created by AgilentArrayRecorder.cgi.';
	$rowdata_ref = \%rowdata;
	my $array_quantitation_id;
	$array_quantitation_id = $sbeams->updateOrInsertRow (table_name=>$TBMA_ARRAY_QUANTITATION,
														 rowdata_ref=>$rowdata_ref,
														 insert=>1,
														 return_PK=>1,
														 add_audit_parameters=>1);
	$array_info{$array,'array_quantitation_id'} = $array_quantitation_id;
	undef %rowdata;
  }
 
  ## End transaction
#  print "<BR>\n COMMIT TRANSACTION <BR>\n";
  $sbeams->executeSQL("COMMIT TRANSACTION");

  ## Print Successful Handling Screen
  print qq~
	<B>Array Records Inserted Successfully!</B><BR>
	To see the array request record:<BR>
	<A HREF =\"$SERVER_BASE_DIR$CGI_BASE_DIR/Microarray/SubmitArrayRequest.cgi?TABLE_NAME=MA_ARRAY_REQUEST&array_request_id=$array_request_id\">$SERVER_BASE_DIR$CGI_BASE_DIR/Microarray/SubmitArrayRequest.cgi?TABLE_NAME=MA_ARRAY_REQUEST&array_request_id=$array_request_id</A><BR>
	<BR>
	To visit this project\'s homepage:<BR>
	<A HREF=\"$SERVER_BASE_DIR$CGI_BASE_DIR/Microarray/ProjectHome.cgi?set_current_project_id=$project\">$SERVER_BASE_DIR$CGI_BASE_DIR/Microarray/ProjectHome.cgi?set_current_project_id=$project</A><BR>
	~;

  ## Fire off an email alerting the admins that a request has been added.
  alert_admins($array_request_id);
  alert_developers($array_request_id,\%array_info);
}


###############################################################################
# alert_admins
###############################################################################
sub alert_admins{
  my $PK = shift @_;
  my $mailprog = "/usr/lib/sendmail";
  my $recipient_name = "Microarray_admin Contact";
  my $recipient = "bmarzolf\@systemsbiology.org";
  my $cc_name = "SBEAMS";
  my $cc = "edeutsch\@systemsbiology.org";
  my $current_username = $sbeams->getCurrent_username();

  #### But if we're running as a dev version then just mail to administrator
  if ($DBVERSION =~ /Dev/) {
	$recipient_name = $cc_name;
	$recipient = $cc;
  }

  open (MAIL, "|$mailprog $recipient,$cc") || croak "Can't open $mailprog!\n";
  print MAIL "From: SBEAMS <edeutsch\@db.systemsbiology.net>\n";
  print MAIL "To: $recipient_name <$recipient>\n";
  print MAIL "Cc: $cc_name <$cc>\n";
  print MAIL "Reply-to: $current_username <${current_username}\@systemsbiology.org>\n";
  print MAIL "Subject: Microarray request submission\n\n";
  print MAIL "A microarray request was just entered into SBEAMS by ${current_username}.  This was sent by ArrayRecorder.cgi\n\n";
  print MAIL "To see the request view this link:\n\n";
  print MAIL "$SERVER_BASE_DIR$CGI_BASE_DIR/Microarray/SubmitArrayRequest.cgi?TABLE_NAME=MA_ARRAY_REQUEST&array_request_id=$PK\n\n";
  close (MAIL);
  
  print "<BR><BR>An email was just sent to the Microarray_admin Group informing them of your request.<BR>\n";
}

###############################################################################
# alert_developers
###############################################################################
sub alert_developers{
  my $PK = shift @_;
  my $parameters_ref = shift @_;
  my %parameters = %{$parameters_ref};
  my $mailprog = "/usr/lib/sendmail";
  my $recipient_name = "Microarray_admin Developer Contact";
  my $recipient = "bmarzolf\@systemsbiology.org";
  my $current_username = $sbeams->getCurrent_username();

  open (MAIL, "|$mailprog $recipient") || croak "Can't open $mailprog!\n";
  print MAIL "From: SBEAMS <edeutsch\@db.systemsbiology.net>\n";
  print MAIL "To: $recipient_name <$recipient>\n";
  print MAIL "Reply-to: $current_username <${current_username}\@systemsbiology.org>\n";
  print MAIL "Subject: Microarray request submission\n\n";
  print MAIL "A microarray request was just entered into SBEAMS by ${current_username}.  This was sent by ArrayRecorder.cgi\n\n";
  print MAIL "To see the request view this link:\n\n";
  print MAIL "$SERVER_BASE_DIR$CGI_BASE_DIR/Microarray/SubmitArrayRequest.cgi?TABLE_NAME=MA_ARRAY_REQUEST&array_request_id=$PK\n\n";
  print MAIL "Here is a listing of the data that was inserted:\n";
  print MAIL "KEY(array,data type) \t VALUE\n";
  foreach my $key (keys %parameters) {
	print MAIL "$key  -  $parameters{$key}\n";
  }
  close (MAIL);
  
  print "<BR><BR>An email was just sent to the Microarray_admin Group informing them of your request.<BR>\n";
}
