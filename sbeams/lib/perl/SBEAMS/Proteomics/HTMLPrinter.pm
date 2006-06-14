package SBEAMS::Proteomics::HTMLPrinter;

###############################################################################
# Program     : SBEAMS::Proteomics::HTMLPrinter
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This is part of the SBEAMS::WebInterface module which handles
#               standardized parts of generating HTML.
#
#		This really begs to get a lot more object oriented such that
#		there are several different contexts under which the a user
#		can be in, and the header, button bar, etc. vary by context
#
# SBEAMS is Copyright (C) 2000-2005 Institute for Systems Biology
# This program is governed by the terms of the GNU General Public License (GPL)
# version 2 as published by the Free Software Foundation.  It is provided
# WITHOUT ANY WARRANTY.  See the full description of GPL terms in the
# LICENSE file distributed with this software.
#
###############################################################################


use strict;
use vars qw($sbeams $current_contact_id $current_username
             $current_work_group_id $current_work_group_name
             $current_project_id $current_project_name $current_user_context_id);
use CGI::Carp qw(fatalsToBrowser croak);
use SBEAMS::Connection::DBConnector;
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::TableInfo;

use SBEAMS::Proteomics::Settings;
use SBEAMS::Proteomics::TableInfo;

use constant MENU_WIDTH => 138;

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
  $self->display_page_header(@_);
}


###############################################################################
# display_page_header
###############################################################################
sub display_page_header {
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
    my $http_header = $sbeams->get_http_header();

    print qq~$http_header
	<HTML><HEAD>
	<TITLE>$DBTITLE - $SBEAMS_PART</TITLE>
    ~;


    $self->printJavascriptFunctions();
    $self->printStyleSheet();


    #### Determine the Title bar background decoration
    my $header_bkg = "bgcolor=\"$BGCOLOR\"";
    $header_bkg = "background=\"$HTML_BASE_DIR//images/plaintop.jpg\"" if ($DBVERSION =~ /Primary/);
    my $gwidth = ( MENU_WIDTH ) ? MENU_WIDTH/2 : 64;

    print qq~
	<!--META HTTP-EQUIV="Expires" CONTENT="Fri, Jun 12 1981 08:20:00 GMT"-->
	<!--META HTTP-EQUIV="Pragma" CONTENT="no-cache"-->
	<!--META HTTP-EQUIV="Cache-Control" CONTENT="no-cache"-->
	</HEAD>

	<!-- Background white, links blue (unvisited), navy (visited), red (active) -->
	<BODY BGCOLOR="#FFFFFF" TEXT="#000000" LINK="#0000FF" VLINK="#000080" ALINK="#FF0000" TOPMARGIN=0 LEFTMARGIN=0 OnLoad="self.focus();">
	<table border=0 width="100%" cellspacing=0 cellpadding=1>

	<!------- Header ------------------------------------------------>
	<a name="TOP"></a>
	<tr>
	  <td bgcolor="$BARCOLOR"><a href="http://db.systemsbiology.net/">
    <img height=64 width=64 border=0 alt="ISB DB" src="$HTML_BASE_DIR/images/dbsmltblue.gif"></a>
    <a href="https://db.systemsbiology.net/sbeams/cgi/main.cgi">
    <img height=64 width=64 border=0 alt="SBEAMS" src="$HTML_BASE_DIR/images/sbeamssmltblue.gif"></a>
    </td>
	  <td align="left" $header_bkg><H1>$DBTITLE - $SBEAMS_PART<BR>$DBVERSION</H1></td>
	</tr>
    ~;

    #print ">>>http_header=$http_header<BR>\n";

    if (uc($navigation_bar) eq 'YES' || uc($navigation_bar) eq 'SHORT') {
      print qq~
	<!------- Button Bar -------------------------------------------->
	<tr><td bgcolor="$BARCOLOR" align="left" valign="top">
	<table border=0 width="120" cellpadding=2 cellspacing=0>

	<tr><td><a href="$CGI_BASE_DIR/main.cgi">$DBTITLE Home</a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/main.cgi">$SBEAMS_PART Home</a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/logout.cgi">Logout</a></td></tr>
      ~;

      if (uc($navigation_bar) eq 'YES') {

        my $spad = '&nbsp;' x 3;

        my $datamenu = qq~
        <TABLE>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/main.cgi"><nobr>&nbsp;&nbsp;&nbsp;My Home</a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=project"<nobr>&nbsp;&nbsp;&nbsp;Projects</a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_proteomics_experiment"><nobr>&nbsp;&nbsp;&nbsp;Experiments</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_proteomics_sample"><nobr>&nbsp;&nbsp;&nbsp;Samples</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=protocol"><nobr>&nbsp;&nbsp;&nbsp;Protocols</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_publication"><nobr>&nbsp;&nbsp;&nbsp;Publications</nobr></a></td></tr>
        </TABLE>
  ~;

        my $browsemenu = qq~
        <TABLE>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/SummarizeFractions"><nobr>&nbsp;&nbsp;&nbsp;Summarize Fractions</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/GetSearchHits"><nobr>&nbsp;&nbsp;&nbsp;Browse Search Hits</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/SummarizePeptides"><nobr>&nbsp;&nbsp;&nbsp;Summarize over</nobr><BR>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Proteins/Peptides</a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/CompareExperiments"><nobr>&nbsp;&nbsp;&nbsp;Compare Exp's</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/CompareMSRuns"><nobr>&nbsp;&nbsp;&nbsp;Compare MSRuns</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/CompareBySpectrum"><nobr>&nbsp;&nbsp;&nbsp;Compare By Spec</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/BrowseBioSequence.cgi"><nobr>&nbsp;&nbsp;&nbsp;Browse BioSeqs</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/BrowseAPD"><nobr>&nbsp;&nbsp;&nbsp;Browse APD</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/BrowsePossiblePeptides"><nobr>&nbsp;&nbsp;&nbsp;Browse Possible</nobr><BR><nobr>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Tryptic Peptides</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/BrowseProteinSummary"><nobr>&nbsp;&nbsp;&nbsp;Protein Summary</nobr></a></td></tr>
        </TABLE>
  ~;

        my $coremenu = qq~
        <TABLE>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_biosequence_set"><nobr>&nbsp;&nbsp;&nbsp;BioSequenceSets</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_dbxref"><nobr>&nbsp;&nbsp;&nbsp;DB XRefs</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_gradient_program"><nobr>&nbsp;&nbsp;&nbsp;Gradient Program</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_user_annotation_label"><nobr>&nbsp;&nbsp;&nbsp;User Annot Label</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_proteomics_experiment_request"><nobr>&nbsp;&nbsp;&nbsp;Request Experiments</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_experiment_type"><nobr>&nbsp;&nbsp;&nbsp;Request Management</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=PR_raw_data_file"><nobr>&nbsp;&nbsp;&nbsp;Data Processing</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=APD_peptide_summary"><nobr>&nbsp;&nbsp;&nbsp;APD Tables</nobr></a></td></tr>
        </TABLE>
  ~;

        my $othermenu = qq~
        <TABLE>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/Help?document=all"><nobr>${spad}Documentation</nobr></a></td></tr>
	<tr><td><a href="http://db.systemsbiology.net:8080/proteomicsToolkit/"><nobr>&nbsp;&nbsp;&nbsp;Proteomics Toolkit</nobr></a></td></tr>
	<tr><td><a href="http://mss.systemsbiology.net/"><nobr>&nbsp;&nbsp;&nbsp;MassSpec Schedule</nobr></a></td></tr>
        </TABLE>
  ~;

  my ($corecontent,$corelink) = $sbeams->make_toggle_section( content => $coremenu,
                                                                 name => 'pr_core_menu',
                                                               sticky => 1 );
  my ($browsecontent,$browselink) = $sbeams->make_toggle_section( content => $browsemenu,
                                                                     name => 'pr_browse_menu',
                                                                  visible => 1,
                                                                   sticky => 1 );
  my ($datacontent,$datalink) = $sbeams->make_toggle_section( content => $datamenu,
                                                                 name => 'pr_data_menu',
                                                               sticky => 1 );
  my ($othercontent,$otherlink) = $sbeams->make_toggle_section( content => $othermenu,
                                                                visible => 1,
                                                                   name => 'pr_other_menu',
                                                                 sticky => 1 );
  my $gif_spacer = $sbeams->getGifSpacer(MENU_WIDTH);
        print qq~
	<tr><td>$gif_spacer</td></tr>
	<tr><td NOWRAP>$datalink Manage Data:</td></tr>
	<tr><td>$datacontent </td></tr>
	<tr><td NOWRAP>$browselink Browse Data:</td></tr>
	<tr><td>$browsecontent </td></tr>
	<tr><td NOWRAP>${corelink}Core Management:</td></tr>
	<tr><td>$corecontent </td></tr>
	<tr><td NOWRAP>${otherlink}Other Tools:</td></tr>
	<tr><td>$othercontent </td></tr>

        ~;
      }

      print qq~
	</table>
	</td>

	<!-------- Main Page ------------------------------------------->
	<td valign=top>
	<table border=0 bgcolor="#ffffff" cellpadding=4>
   <TR><TD>
    <IMG SRC="$HTML_BASE_DIR/images/clear.gif" width=1000 height=1>
   </TD></TR>
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
	picked=new Array(); // global array to remember selected items
	curEmpty=0;       // pointer to first empty location in output
	maxEntries =1;    // global to only allow one sample to be entered
	
	function add2list(sourceID,targetID) {
		source=document.getElementById(sourceID);
		target=document.getElementById(targetID);
		maxItems=source.options.length;
		//alert('MAX ITEMS'+ maxItems + "Source" + " " + source);
		for (i=0;i<maxItems;i++) {
  			if (source.options[i].selected==true && picked[i]!=true && curEmpty < maxEntries) {
     			target.options[curEmpty].text  = source.options[i].text;
     			target.options[curEmpty].value = source.options[i].value;
     			target.options[curEmpty].selected = true;
     			picked[i]=true; curEmpty++;
     		} 
     	} 
     }
	
	function removefromlist(sourceID,targetID) {
		source=document.getElementById(sourceID);
		target=document.getElementById(targetID);
		maxItems=source.options.length;
		//alert('MAX ITEMS'+ maxItems + "Source \\n" + source + "\\n" + "CUREMPTY" + " " + curEmpty);
		for (i=0;i<maxItems;i++) {
  			if (target.options[i].selected==true ) {
     			target.options[i].text='';
     		picked=new Array(); curEmpty=0;
     		} 
     	} 
     }
		

	function submitsample(inputobj) {
		var currentform = inputobj.form;
		var exp_id = currentform.experiment_id.value;
		var form_name = currentform.name
		var blanksource_list = true;
		// Return the array position for the option that was selected
		var current_selected_number = currentform.sample_id.selectedIndex;
		if (! current_selected_number ){
			//For some reason the added to select list is not coming through so check for any entries 
			//we will assume that it is the only one being given so it should be in the option list array at 0
			current_selected_number = 0;
			//alert("DEFAULT TO " +currentform.sample_id.options[current_selected_number].text);
			// Hack to prevent values from being blanked on the form to select samples from all samples page.
			blanksource_list = false; 
		}
		//Grab the value of the option value that was selected
		var current_selection  = currentform.sample_id.options[current_selected_number].value;
		var isselected = currentform.sample_id.options[current_selected_number].selected
		//alert("DEBUG INFO\\n" +  form_name + " *  "+exp_id + " **  " + current_selected_number + " " +current_selection  + "\\nIS SELECTED " +isselected   );           
		if (current_selection > 0){
	     	
	     currentform.submit();
	     
	     //Blank out the values so they cannot be used again, only appropriate on the main page
	     if (blanksource_list == true){
	     	currentform.sample_id.options[current_selected_number] = null;
	     	//refresh the window
	     	window.location = window.location;
	     }
	    }else{
	    	alert("There was no Sample Selected");
	    }
	} 
	
		function refreshDocument() {
	    //confirm( "apply_action ="+document.MainForm.apply_action.options[0].selected+"=");
        document.MainForm.apply_action_hidden.value = "REFRESH";
        document.MainForm.action.value = "REFRESH";
	    document.MainForm.submit();
	} // end refreshDocument


	function showPassed(input_field) {
            //confirm( "input_field ="+input_field+"=");
            confirm( "selected option ="+document.forms[0].slide_id.options[document.forms[0].slide_id.selectedIndex].text+"=");
	    return;
	} // end showPassed



        // -->
        </SCRIPT>

    ~;

}


###############################################################################
# documentation_list
###############################################################################
sub documentation_list {
#link for schema needs help
  my $self = shift;
print qq~
<CENTER>
<H3>Proteomics Documentation</H3>
</CENTER>
<UL>
<LI><A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/Help?document=ProteomicsTutorial">Tutorial</A>
<LI><a href="$HTML_BASE_DIR/doc/$SBEAMS_SUBDIR/${SBEAMS_PART}_Schema.gif">Schema</A>
<LI><A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/Help?document=RecentNews">Proteomics Module Recent News</A>
</UL>
    ~;
}

###############################################################################
# printPageFooter
###############################################################################
sub printPageFooter {
  my $self = shift;
  $self->display_page_footer(@_);
}


###############################################################################
# display_page_footer
###############################################################################
sub display_page_footer {
  my $self = shift;
  my %args = @_;


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

} # end display_page_footer



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
