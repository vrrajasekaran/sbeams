package SBEAMS::Microarray::HTMLPrinter;

###############################################################################
# Program     : SBEAMS::Microarray::HTMLPrinter
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This is part of the SBEAMS::Microarray module which handles
#               standardized parts of generating HTML.
#
#		This really begs to get a lot more object oriented such that
#		there are several different contexts under which the a user
#		can be in, and the header, button bar, etc. vary by context
###############################################################################


use strict;
use vars qw($sbeams $current_contact_id $current_username
             $current_work_group_id $current_work_group_name
             $current_project_id $current_project_name $current_user_context_id);
use CGI::Carp qw(fatalsToBrowser croak);
use SBEAMS::Connection::DBConnector;
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::TableInfo;

use SBEAMS::Microarray::Settings;
use SBEAMS::Microarray::TableInfo;


###############################################################################
# Constructor
###############################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;
    return($self);
}


###############################################################################
# printPageHeader
###############################################################################
sub printPageHeader {
  my $self = shift;
  my %args = @_;

  my $navigation_bar = $args{'navigation_bar'} || "YES";

  #### If the output mode is interactive text, display text header
  my $sbeams = $self->getSBEAMS();
  if ($sbeams->output_mode() eq 'interactive') {
    $sbeams->printTextHeader();
    return;
  }


  #### If the output mode is not html, then we don't want a header here
  if ($sbeams->output_mode() ne 'html') {
    return;
  }


  #### Obtain main SBEAMS object and use its http_header
  $sbeams = $self->getSBEAMS();

	$current_contact_id = $sbeams->getCurrent_contact_id();
	
	if ($sbeams->getCurrent_contact_id() ne 107)
	{
    $self->displaySBEAMSPageHeader(@_);
	}
	else # Currently only guest mode is SCGAP, will likely change...
	{
		$self->displaySCGAPPageHeader(@_);
	}
}


sub displaySCGAPPageHeader
{ 
	my $self = shift;
  my %args = @_;

  #### Obtain main SBEAMS object and use its http_header
  my $sbeams = $self->getSBEAMS();
  my $http_header = $sbeams->get_http_header();
  use LWP::UserAgent;
  use HTTP::Request;
  my $ua = LWP::UserAgent->new();
  my $scgapLink = 'http://scgap.systemsbiology.net';
  my $response = $ua->request( HTTP::Request->new( GET => "$scgapLink/skin.php" ) );
  my @page = split( "\r", $response->content() );
  my $skin = '';
  for ( @page ) {
    last if $_ =~ / End of main content/;
    $skin .= $_;
  }
  $skin =~ s/\/images\//\/sbeams\/images\//gm;
 
  print "$http_header\n\n";
  print <<"  END_PAGE";
  <HTML>
    $skin
  END_PAGE

  $self->printJavascriptFunctions();
}

sub displaySBEAMSPageHeader
{
	my $self = shift;
  my %args = @_;

  #### Obtain main SBEAMS object and use its http_header
  my $sbeams = $self->getSBEAMS();
  my $http_header = $sbeams->get_http_header();

  my $navigation_bar = $args{'navigation_bar'} || "YES";

  print qq~$http_header
	<HTML><HEAD>
	<TITLE>$DBTITLE - Microarray</TITLE>
  ~;


  $self->printJavascriptFunctions();
  $self->printStyleSheet();


  #### Determine the Title bar background decoration
  my $header_bkg = "bgcolor=\"$BGCOLOR\"";
    $header_bkg = "background=\"/images/plaintop.jpg\"" if ($DBVERSION =~ /Primary/);

    print qq~
	<!--META HTTP-EQUIV="Expires" CONTENT="Fri, Jun 12 1981 08:20:00 GMT"-->
	<!--META HTTP-EQUIV="Pragma" CONTENT="no-cache"-->
	<!--META HTTP-EQUIV="Cache-Control" CONTENT="no-cache"-->
	</HEAD>

	<!-- Background white, links blue (unvisited), navy (visited), red (active) -->
	<BODY BGCOLOR="#FFFFFF" TEXT="#000000" LINK="#0000FF" VLINK="#000080" ALINK="#FF0000" TOPMARGIN=0 LEFTMARGIN=0 >
	<table border=0 width="100%" cellspacing=0 cellpadding=0>

	<!------- Header ------------------------------------------------>
	<a name="TOP"></a>
	<tr>
		<td colspan=3>
			<table border=0 width=100% cellspacing=0 cellpadding=0>
				<tr>
				  <td bgcolor="#000000" align=left><img alt="MICROARRAY" src="$HTML_BASE_DIR/images/microarray.gif"></td>
				  <td bgcolor="#000000" align=right valign=center><font color="#ffffff"><a href="$CGI_BASE_DIR/logout.cgi"><img src="$HTML_BASE_DIR/images/logout.gif" border=0 alt="LOGOUT"></a><img src="$HTML_BASE_DIR/images/space.gif" height=1 width=25></td>
				</tr>
			</table>
		</td>
	</tr>

    ~;

    #print ">>>http_header=$http_header<BR>\n";

    if ($navigation_bar eq "YES") {
      print qq~
	<!------- Button Bar -------------------------------------------->
	<tr><td bgcolor="#ffffff" align="left" valign="top" width="150">
	<table bgcolor="#ffffff" border=0 width="100%" cellpadding=2 cellspacing=0>
	<tr><td><a href="$CGI_BASE_DIR/main.cgi"><img src="$HTML_BASE_DIR/images/ma_sbeams_home.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/main.cgi"><img src="$HTML_BASE_DIR/images/ma_array_home.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ProjectHome.cgi"><IMG SRC="$HTML_BASE_DIR/images/ma_project_home.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/GridAlignCheck.cgi"><img src="$HTML_BASE_DIR/images/ma_alignment_check.jpg"></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ProjectHome.cgi?tab=data_pipeline"><img src="$HTML_BASE_DIR/images/ma_pipeline.jpg"></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ProjectHome.cgi?tab=data_download"><img src="$HTML_BASE_DIR/images/ma_data_download.jpg"></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/GetExpression"><img src="$HTML_BASE_DIR/images/ma_get_expression.jpg"></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/GetAffy_GeneIntensity.cgi"><img src="$HTML_BASE_DIR/images/ma_get_affy_intensity.jpg"></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ProjectHome.cgi?tab=miame_status"><img src="$HTML_BASE_DIR/images/ma_miame_status.jpg"></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/SubmitArrayRequest.cgi?TABLE_NAME=MA_array_request"><img src="$HTML_BASE_DIR/images/ma_array_requests.jpg"></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=protocol"><img src="$HTML_BASE_DIR/images/ma_protocols.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_labeling"><img src="$HTML_BASE_DIR/images/ma_labeling.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_hybridization"><img src="$HTML_BASE_DIR/images/ma_hybridization.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_array_quantitation"><img src="$HTML_BASE_DIR/images/ma_quantitation.jpg"></a></td></tr>
    ~;

      $current_work_group_name = $sbeams->getCurrent_work_group_name();
      if ($current_work_group_name eq "Microarray_admin" || $current_work_group_name eq "Admin" || 1) {
       print qq~
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=contact"><img src="$HTML_BASE_DIR/images/ma_contacts.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_array"><img src="$HTML_BASE_DIR/images/ma_arrays.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_array_scan"><img src="$HTML_BASE_DIR/images/ma_array_scans.jpg"></a></td></tr>
       ~;
      }

      $current_work_group_name = $sbeams->getCurrent_work_group_name();
      if ($current_work_group_name eq "Microarray_admin" || $current_work_group_name eq "Admin") {
       print qq~
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_slide_lot"><img src="$HTML_BASE_DIR/images/ma_slide_lots.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_array_layout"><img src="$HTML_BASE_DIR/images/ma_array_layout.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_printing_batch"><img src="$HTML_BASE_DIR/images/ma_printing_batches.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=MA_slide_type"><img src="$HTML_BASE_DIR/images/ma_slide_types_costs.jpg"></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/ManageTable.cgi?TABLE_NAME=user_login"><img src="$HTML_BASE_DIR/images/ma_admin.jpg"></a></td></tr>
       ~;
      }
      
      if ( exists $CONFIG_SETTING{Microarray_affy_help_docs_url} && $CONFIG_SETTING{Microarray_affy_help_docs_url} =~ /http/){
      
      	print qq~ 
		<tr><td><a class='blue_button' href="$CONFIG_SETTING{Microarray_affy_help_docs_url}">Affy Help Docs</a></td></tr>
	      ~;
      }else{
      	print qq~ <tr><td><a class='blue_button' href="$HTML_BASE_DIR/doc/Microarray/affy_help_pages/index.php">Affy Help Docs</a></td></tr>
	~;
     }	
      print qq~
	</table>
	</td>
	<td width=2 bgcolor="#cc0000">
		<img src="$HTML_BASE_DIR/images/space.gif" width=5 height=1>
	</td>

	<!-------- Main Page ------------------------------------------->
	<td valign=top>
	<table border=0 bgcolor="#ffffff" cellpadding=4>
	<tr><td>

    ~;
    } else {
      print qq~
	</TABLE>
      ~;
    }

}

# 	<table border=0 width="680" bgcolor="#ffffff" cellpadding=4>


###############################################################################
# printStyleSheet
#
# Print the standard style sheet for pages.  Use a font size of 10pt if
# remote client is on Windows, else use 12pt.  This ends up making fonts
# appear the same size on Windows+IE and Linux+Netscape.  Other tweaks for
# different browsers might be appropriate.
###############################################################################
sub printStyleSheet {
    my $self = shift;

    #### Obtain main SBEAMS object and use its style sheet
    $sbeams = $self->getSBEAMS();
    $sbeams->printStyleSheet();

}


###############################################################################
# printJavascriptFunctions
#
# Print the standard Javascript functions that should appear at the top of
# most pages.  There probably should be some customization allowance here.
# Not sure how to design that yet.
###############################################################################
sub printJavascriptFunctions {
  my $self = shift;
  my $javascript_includes = shift;

  print qq~

<SCRIPT LANGUAGE="JavaScript">
<!--

function refreshDocument() {
  document.MainForm.apply_action_hidden.value = "REFRESH";
  document.MainForm.submit();
}

function refreshPairWiseOnly()
{
    document.MainForm.pair_wise_only.value = "YES";
	document.MainForm.submit();
}

function showPassed(input_field) {
  confirm( "selected option ="+document.MainForm.slide_id.options[document.MainForm.slide_id.selectedIndex].text+"=");
  return;
}

function confirmPasswdChange() {
  if (confirm( "The old password for this user will no longer be "+"valid.")) {
    return true;
  }else {
    return false;
  }
}

function ClickedNowButton(input_field) {
  field_name = input_field.name;
  today = new Date();
  date_value =
      today.getFullYear() + "-" + (today.getMonth()+1) + "-" +
      today.getDate() + " " +
      today.getHours() + ":" +today.getMinutes();
  
  if (field_name == "date_labeled") {
      document.MainForm.date_labeled.value = date_value;
  }else if (field_name == "date_hybridized") {
      document.MainForm.date_hybridized.value = date_value;
  }else if (field_name == "date_received") {
      document.MainForm.date_received.value = date_value;
  }else if (field_name == "date_scanned") {
      document.MainForm.date_scanned.value = date_value;
  }else if (field_name == "date_quantitated") {
      document.MainForm.date_quantitated.value = date_value;
  }

  return;
}

function setDefaultImagesLocation() {
    array_name = document.MainForm.array_id.options[document.MainForm.array_id.selectedIndex].text;
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

    document.MainForm.stage_location.value =
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

function setDefaultQALocation() {
  array_name = document.MainForm.array_scan_id.options[document.MainForm.array_scan_id.selectedIndex].text;
  array_name = array_name.toString();
  if (array_name.substr(array_name.length-9,99) == " - *DONE*") {
    array_name = array_name.substr(0,array_name.length-9);
  }

  start_group = Math.round(array_name/100-0.5)*100+1;
  start_group = addLeadingZeros(start_group.toString(),5);

  end_group = Math.round(array_name/100+0.5)*100;
  end_group = addLeadingZeros(end_group.toString(),5);

  protocol_name = document.MainForm.protocol_id.options[document.MainForm.protocol_id.selectedIndex].text;
  protocol_name = protocol_name.toString();
  extension = ".csv";
  
  if (protocol_name.search(/QuantArray/i)>-1) { extension = ".qa"; }
  if (protocol_name.search(/Dapple/i)>-1) { extension = ".dapple"; }

  document.MainForm.stage_location.value =
      "/net/arrays/Quantitation/" +
      start_group + "-"+ end_group + "/" +
      array_name + extension;

  return;
}

  function setArrayName() {
    array_name = document.MainForm.array_name.value=document.MainForm.slide_id.options[document.MainForm.slide_id.selectedIndex].text;
    array_name = array_name.toString();
    if (array_name.substr(array_name.length-9,99) == " - *DONE*") {
      array_name = array_name.substr(0,array_name.length-9);
    }
    while (array_name.length < 5) { array_name = "0" + array_name; }

    document.MainForm.array_name.value = array_name;
    return;
}

function setLayoutFileName() {
  document.MainForm.source_filename.value =
      "/net/arrays/Slide_Templates/" +
      document.MainForm.name.value + ".key"
      return;
}
function changetabnumber (){
    document.Selectedfiles_form._tab.value = 1;
    if(confirm("Really delete checked files?")){

    }else{
	var all_files = document.Selectedfiles_form.files;
 	var numb_files = all_files.length;
 
 	for (var i = 0; i < numb_files; i++){
 		all_files[i].value = '';
 	}
	alert("Ok none of the current " + numb_files + " files will be deleted"); 
    } 
   return;
}


// -->
</SCRIPT>
~;

}





###############################################################################
# printPageFooter
###############################################################################
sub printPageFooter {
  my $self = shift;


  #### Allow old-style single argument
  my $n_params = scalar @_;
  my %args;
  #### If the old-style single argument exists, create args hash with it
  if ($n_params == 1) {
    my $flag = shift;
    $args{close_tables} = 'NO';
    $args{close_tables} = 'YES' if ($flag =~ /CloseTables/);
    $args{display_footer} = 'NO';
    $args{display_footer} = 'YES' if ($flag =~ /Footer/);
  } else {
    %args = @_;
  }


  #### If the output mode is interactive text, display text header
  my $sbeams = $self->getSBEAMS();
  if ($sbeams->output_mode() eq 'interactive') {
    $sbeams->printTextHeader(%args);
    return;
  }


  #### If the output mode is not html, then we don't want a header here
  if ($sbeams->output_mode() ne 'html') {
    return;
  }


  #### Process the arguments list
  my $close_tables = $args{'close_tables'} || 'YES';
  my $display_footer = $args{'display_footer'} || 'YES';
  my $separator_bar = $args{'separator_bar'} || 'NO';


  #### If closing the content tables is desired
  if ($close_tables eq 'YES') {
    print qq~
	</TD></TR></TABLE>
	</TD></TR></TABLE>
    ~;
  }


  #### If displaying a fat bar separtor is desired
  if ($separator_bar eq 'YES') {
    print "<BR><HR SIZE=5 NOSHADE><BR>\n";
  }


  #### If finishing up the page completely is desired
  if ($display_footer eq 'YES') {
    #### Default to the Core footer
    $sbeams->display_page_footer(display_footer=>'YES');
  }

}


###############################################################################
# print_tabs
###############################################################################
sub print_tabs {
    my $self= shift;
    my %args = @_;
    my $SUB_NAME = "print_tabs";
    
## Decode argument list
    my $tab_titles_ref = $args{'tab_titles_ref'}
    || die "ERROR[$SUB_NAME]:tab_titles_ref not passed";
    my $selected_tab = $args{'selected_tab'} || 0;
    my $parent_tab = $args{'parent_tab'};
    my $page_link = $args{'page_link'}
    || die "ERROR[$SUB_NAME]:page_link not passed";
    my $unselected_bg_color   = $args{'unselected_bg_color'}   || "\#224499";
    my $unselected_font_color = $args{'unselected_font_color'} || "\#ffffff";
    my $selected_bg_color     = $args{'selected_bg_color'}     || "\#ffcc33";
    my $selected_font_color   = $args{'selected_font_color'}   || "\#000000";
    my $line_color            = $args{'line_color'}            || "\#3366cc";
    
    
    
## Define standard variables
    my @tab_titles = @{$tab_titles_ref};
    my $counter = 0;
    
## Start TABLE
    print qq~
	<TABLE BORDER="0" CELLSPACING="0" CELLPADDING="0">
	<TR>
	~;
    
## for each desired tab, make one
    while (@tab_titles) {
	my $tab_title = shift(@tab_titles);
	my $link = $tab_title;
	while ($link =~ /\s+/) {
	    $link =~ s(\s+)(_);
	}
	$link =~ tr/A-Z/a-z/;
	if ($counter == $selected_tab) {
	    print qq~
		<TD WIDTH="15">&nbsp;</TD>
		<TD BGCOLOR="$selected_bg_color" ALIGN="CENTER" WIDTH="95" NOWRAP><FONT COLOR="$selected_font_color" SIZE="-1">$tab_title</FONT></TD>
		~;
	}else {
	    my $print_parent_tab =  $parent_tab ? "&tab=$parent_tab": '';
	    print qq~
		<TD WIDTH="15">&nbsp;</TD>
		<TD BGCOLOR="$unselected_bg_color" ALIGN="CENTER" WIDTH="95" NOWRAP><A HREF="$page_link?tab=$link$print_parent_tab"><FONT COLOR="$unselected_font_color" SIZE="-1">$tab_title</FONT></A></TD>
		~;
	}
	$counter++;
	
    }
    
## Draw line underneath tabs
    print qq~
	<TD WIDTH="15">&nbsp;</TD>
	</TR>
	<TR>
        <TD colspan=12 BGCOLOR="$line_color"><IMG WIDTH=1 height=1 alt=""></TD>
	~;
    
## Finish table
    print qq~
	</TR>
	</TABLE>
	~;
    
    return;
}


###############################################################################
# Print QuickLinks
###############################################################################
sub printQuickLinks {
	my $self = shift;
	my $q = shift;

}

###############################################################################
# change_views_javascript
###############################################################################
sub change_views_javascript {
	
	
print qq~
<SCRIPT LANGUAGE="Javascript">
<!--
function change_views_javascript(input_obj){
 var form = input_obj.form;
 var val = form.display_type.val ;
 onClick="parent.location='?display_type='" + val + "'";
 

document.get_all_files.submit();
}
//-->
</SCRIPT>
~;

}
###############################################################################
# updateCheckBoxButtons_javascript
###############################################################################
sub updateCheckBoxButtons_javascript {
	
	
print qq~
<SCRIPT LANGUAGE="Javascript">
<!--
function updateCheckBoxButtons(input_obj){
 var form = input_obj.form;
 var all_checkboxes = form.click_all_files;
 var updatedVals;
 
 var regexp = /(.+?)__(.*)/; //Exmple 42__XML
 
 var results = input_obj.value.match(regexp);
  
 var file_types = new Object();
 
 for (var i=0; i<all_checkboxes.length; i ++){				//Loop through the all checkbox buttons and store their checked value in an object
 	
  	var hold = form.click_all_files[i].value;			// grab the value of the checkbox
	file_types[hold] = form.click_all_files[i].checked;		// set for each data type if it is checked or not
	
 }
 
 if (all_checkboxes.length == null){					//If there is only one element we will not get back an array and file_types will not exists
	var hold = form.click_all_files.value;
	file_types[hold] = form.click_all_files.checked;
}

 
 
 if (all_files ){

 }else{
	var all_files = form.get_all_files				//Do not re-make the all_files array if it has already been made.  Not sure why this works but it does
 }

 for (var i = 0; i<all_files.length; i ++) {
 	
 	var results = form.get_all_files[i].value.match(regexp);	//split apart the checkbox val 
 									
									//grab the file_extension
	var file_ext = results[2];					//remember that the first javascript regex match returned is the full string then the parenthesized sub expressions
 	
	var click_all_check_val =  file_types[file_ext];		//set the file extension click_all_files checked val
	 
	
	form.get_all_files[i].checked = click_all_check_val ;		//Set the checkbox to what ever the all_checkbox checked value was
	  
 
 }

  return;
}

//-->
</SCRIPT>
~;

}

###############################################################################
# make_checkbox_contol_table
###############################################################################
sub make_checkbox_contol_table {

	my $self = shift;
	my %args = @_;
	
	my @box_names = @ {$args{box_names}};
	my @default_file_types = @ {$args{default_file_types}};
	
	print qq~<table border=0>
			  <tr>
			    <td colspan=2>Click to select or de-select all arrays</td>
			  </tr>
			~;
			  
		      	
		foreach my $file_type (@box_names){
			
			my $checked = '';
			
			if ( grep {$file_type eq $_} @default_file_types) {
				$checked = "CHECKED";
			}
			print qq~  <tr>
				  	<td>$file_type </td>
				  	<td><input type='checkbox' name='click_all_files' value='$file_type' $checked onClick="Javascript:updateCheckBoxButtons(this)"></td>
				  </tr>
				~;
		}
			 
		print "</table>";


}






###############################################################################

1;

__END__
###############################################################################
###############################################################################
###############################################################################

=head1 NAME

SBEAMS::WebInterface::HTMLPrinter - Perl extension for common HTML printing methods

=head1 SYNOPSIS

  Used as part of this system

    use SBEAMS::WebInterface;
    $adb = new SBEAMS::WebInterface;

    $adb->printPageHeader();

    $adb->printPageFooter();

    $adb->getGoBackButton();

=head1 DESCRIPTION

    This module is inherited by the SBEAMS::WebInterface module,
    although it can be used on its own.  Its main function 
    is to encapsulate common HTML printing routines used by
    this application.

=head1 METHODS

=item B<printPageHeader()>

    Prints the common HTML header used by all HTML pages generated 
    by theis application

=item B<printPageFooter()>

    Prints the common HTML footer used by all HTML pages generated 
    by this application

=item B<getGoBackButton()>

    Returns a form button, coded with javascript, so that when it 
    is clicked the user is returned to the previous page in the 
    browser history.

=head1 AUTHOR

Eric Deutsch <edeutsch@systemsbiology.org>

=head1 SEE ALSO

perl(1).

=cut
