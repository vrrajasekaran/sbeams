package SBEAMS::Glycopeptide::HTMLPrinter;

###############################################################################
# Program     : SBEAMS::Glycopeptide::HTMLPrinter
# $Id: HTMLPrinter.pm 3976 2005-09-26 17:25:12Z dcampbel $
#
# Description : This is part of the SBEAMS::WebInterface module which handles
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
use CGI::Carp qw( croak);
use SBEAMS::Connection::DBConnector;
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::TableInfo;
use SBEAMS::Connection::Log;
my $log = SBEAMS::Connection::Log->new();

use SBEAMS::Glycopeptide::Settings;
use SBEAMS::Glycopeptide::TableInfo;


###############################################################################
# printPageHeader
###############################################################################
sub printPageHeader {
  my $self = shift;
  $self->display_page_header(@_);
}


# displayUnipepHeader
###############################################################################
sub displayUnipepHeader {
 	my $self = shift;
  my %args = @_;

  #### Obtain main SBEAMS object and use its http_header
  my $sbeams = $self->getSBEAMS();
  my $http_header = $sbeams->get_http_header();

  my $navigation_bar = $args{'navigation_bar'} || "YES";

  my $LOGIN_URI = "$SERVER_BASE_DIR$ENV{REQUEST_URI}";
  if ($LOGIN_URI =~ /\?/) {
    $LOGIN_URI .= "&force_login=yes";
  } else {
    $LOGIN_URI .= "?force_login=yes";
  }

  my $cswitcher = '';
  if ( -e "$PHYSICAL_BASE_DIR/lib/perl/SBEAMS/PeptideAtlas/ContextWidget.pm" ) {
    $log->debug( "it exists, lets use it!" );
    require SBEAMS::PeptideAtlas::ContextWidget;
    my $cwidget = SBEAMS::PeptideAtlas::ContextWidget->new();
    $log->debug( "got a new one" );
    $cswitcher = $cwidget->getContextSwitcher( username => $current_username );
    
  } else {
    $log->debug(  "$PHYSICAL_BASE_DIR/lib/perl/SBEAMS/PeptideAtlas/ContextWidget.pm doesn't exist" )
  }

  # Not going to show this for now...
  $cswitcher = '';

  my $cutoff_widget = $self->get_prophet_control();

  my $LOGIN_LINK = qq~<A HREF="$LOGIN_URI" class="leftnavlink">LOGIN</A>~;

  use LWP::UserAgent;
  use HTTP::Request;
  my $ua = LWP::UserAgent->new();
#  my $skinLink = 'http://www.unipep.org/newlook/';
  my $skinLink = 'http://www.unipep.org';
  my $response = $ua->request( HTTP::Request->new( GET => "$skinLink/.index.dbbrowse.php" ) );
  my @page = split( "\r", $response->content() );
  my $skin = '';
  my $cnt = 0;
#  print STDERR "Original content is " . $response->content() . "\n";
  for my $line ( @page ) {
    $cnt++;
    if ( $line =~ /LOGIN/ ) {
       $line =~ s/\<\!-- LOGIN_LINK --\>/$LOGIN_LINK/;
    } elsif ( $line =~ /CSWITCHER/ ) {
       $line =~ s/\<\!--CSWITCHER--\>/$cswitcher/;
    } elsif ( $line =~ /PSCORE_CUTOFF/ ) {
       $line =~ s/\<\!--PSCORE_CUTOFF--\>/$cutoff_widget/;
    } elsif ( $line =~ /td\s+\{font/ ) {
  #    next;
    } elsif ( $line =~ /body\s+\{font/ ) {
  #    next;
    }
    $skin .= $line;
    last if $line =~ /--- Main Page Content ---/;
  }
  $skin =~ s/\/images\//\/sbeams\/images\//gm;
  
  $self->{'_external_footer'} =  join( "\n", @page[$cnt..$#page] );
  print "$http_header\n\n";
  print <<"  END_PAGE";
  <HTML>
  $skin
  END_PAGE
#  print '<STYLE TYPE=text/css>' . $self->getGlycoStyleSheet() . '</STYLE>';
#  $self->printStyleSheet();

  $self->printJavascriptFunctions();
  }


sub getGlycoStyleSheet {
  use Env qw (HTTP_USER_AGENT);   
   
  my $FONT_SIZE=9;
  my $FONT_SIZE_SM=8;
  my $FONT_SIZE_LG=12;
  my $FONT_SIZE_HG=14;

  if ( $HTTP_USER_AGENT =~ /Mozilla\/4.+X11/ ) {
    $FONT_SIZE=12;
    $FONT_SIZE_SM=11;
    $FONT_SIZE_LG=14;
    $FONT_SIZE_HG=19;
  }

my $css =<<END;
   .table_setup{border: 0px ; border-collapse: collapse;   }
   .pad_cell{padding:5px;  }
   .sequence_font{font-family:courier; ${FONT_SIZE_LG}pt; font-weight: bold; letter-spacing:0.5}
   .white_hyper_text{font-family: Helvetica,Arial,sans-serif; color:#000000;}
   .white_text    {  font-family: Helvetica, Arial, sans-serif; font-size: ${FONT_SIZE}pt; text-decoration: underline; color: white; CURSOR: help;}
   .grey_header{ font-family: Helvetica, Arial, sans-serif; color: #000000; font-size: ${FONT_SIZE_HG}pt; background-color: #CCCCCC; font-weight: bold; padding:1 2}
   .rev_gray{background-color: #555555; ${FONT_SIZE}pt; font-weight: bold; color:white; line-height: 25px;}
	 .blue_bg{ font-family: Helvetica, Arial, sans-serif; background-color: #4455cc; ${FONT_SIZE_HG}pt; font-weight: bold; color: white}
	 .lite_blue_bg{font-family: Helvetica, Arial, sans-serif; background-color: #eeeeff; ${FONT_SIZE_HG}pt; color: #cc1111; font-weight: bold;border-style: solid; border-width: 1px; border-color: #555555 #cccccc #cccccc #555555;}
  	 
       .identified_pep{
  	         background-color: #882222;
  	         ${FONT_SIZE_LG}pt;
  	         font-weight: bold ;
  	         color:white;
  	         Padding:1;
  	         border-style: solid;
  	         border-left-width: 1px;
  	         border-right-width: 1px;
  	         border-top-width: 1px;
  	         border-left-color: #eeeeee;
  	         border-right-color: #eeeeee;
  	         border-top-color: #aaaaaa;
  	         border-bottom-color:#aaaaaa;
  	         }
  	         .predicted_pep{
  	         background-color: #FFCC66;
  	         ${FONT_SIZE_LG}pt;
  	         font-weight: bold;
  	         border-style: solid;
  	         border-width: 1px;
  	 
  	         border-right-color: blue ;
  	         border-left-color:  red ;
  	 
  	         }
  	 
  	         .sseq{ background-color: #CCCCFF; ${FONT_SIZE_LG}pt; font-weight: bold}
  	         .tmhmm{ background-color: #CCFFCC; ${FONT_SIZE_LG}pt; font-weight: bold; text-decoration:underline}
  	         .instruction_text{ font-size: ${FONT_SIZE_LG}pt; font-weight: bold}
  	 
  	         .glyco_site{ background-color: #ee9999;
  	         border-style: solid;
  	         border-width: 1px;
  	         /* top right bottom left */
  	         border-color: #444444 #eeeeee #eeeee #444444; }
  	 
  	 
         a.edit_menuButton:link { 	         a.edit_menuButton:link {
         /* font-size: 12px; */ 	         /* font-size: 12px; */
         background-color: #ff0066; 	         background-color: #ff0066;
 } 	 }
  	 
  	 a.blue_button:link{
  	         background: #366496;
  	         color: #ffffff;
  	         text-decoration: none;
  	         padding:0px 3px 0px 3px;
  	         border-top: 1px solid #CBE3FF;
  	         border-right: 1px solid #003366;
  	         border-bottom: 1px solid #003366; \
  	         border-left:1px solid #B7CFEB;
  	 }
  	 
  	 a.blue_button:visited{
  	         background: #366496;
  	         color: #ffffff;
  	         text-decoration: none;
  	         padding:0px 3px 0px 3px;
  	         border-top: 1px solid #CBE3FF;
  	         border-right: 1px solid #003366;
  	         border-bottom: 1px solid #003366; \
  	         border-left:1px solid #B7CFEB;
  	 }
  	 a.blue_button:hover{
  	         background: #366496;
  	         color: #777777;
  	         text-decoration: none;
  	         padding:0px 3px 0px 3px;
  	         border-top: 1px solid #CBE3FF;
  	         border-right: 1px solid #003366;
  	         border-bottom: 1px solid #003366; \
  	         border-left:1px solid #B7CFEB;
  	 }
  	 
  	 a.blue_button:active{
  	         background: #366496;
  	         color: #ffffff;
  	         text-decoration: none;
  	         padding:0px 3px 0px 3px;
  	         border-top: 1px solid #CBE3FF;
  	         border-right: 1px solid #003366;
  	         border-bottom: 1px solid #003366; \
  	         border-left:1px solid #B7CFEB;
  	 }
     td {white-text} 	         border-width: 1px;
  	 
  	         border-right-color: blue ;
  	         border-left-color:  red ;
  	 
  	         }
  	 
  	         .sseq{ background-color: #CCCCFF; ${FONT_SIZE_LG}pt; font-weight: bold}
  	         .tmhmm{ background-color: #CCFFCC; ${FONT_SIZE_LG}pt; font-weight: bold; text-decoration:underline}
  	         .instruction_text{ font-size: ${FONT_SIZE_LG}pt; font-weight: bold}
  	 
  	         .glyco_site{ background-color: #ee9999;
  	         border-style: solid;
  	         border-width: 1px;
  	         /* top right bottom left */
  	         border-color: #444444 #eeeeee #eeeee #444444; }
  	 
  	 
         a.edit_menuButton:link { 	         a.edit_menuButton:link {
         /* font-size: 12px; */ 	         /* font-size: 12px; */
         background-color: #ff0066; 	         background-color: #ff0066;
 } 	 }
  	 
  	 a.blue_button:link{
  	         background: #366496;
  	         color: #ffffff;
  	         text-decoration: none;
  	         padding:0px 3px 0px 3px;
  	         border-top: 1px solid #CBE3FF;
  	         border-right: 1px solid #003366;
  	         border-bottom: 1px solid #003366; \
  	         border-left:1px solid #B7CFEB;
  	 }
  	 
  	 a.blue_button:visited{
  	         background: #366496;
  	         color: #ffffff;
  	         text-decoration: none;
  	         padding:0px 3px 0px 3px;
  	         border-top: 1px solid #CBE3FF;
  	         border-right: 1px solid #003366;
  	         border-bottom: 1px solid #003366; \
  	         border-left:1px solid #B7CFEB;
  	 }
  	 a.blue_button:hover{
  	         background: #366496;
  	         color: #777777;
  	         text-decoration: none;
  	         padding:0px 3px 0px 3px;
  	         border-top: 1px solid #CBE3FF;
  	         border-right: 1px solid #003366;
  	         border-bottom: 1px solid #003366; \
  	         border-left:1px solid #B7CFEB;
  	 }
  	 
  	 a.blue_button:active{
  	         background: #366496;
  	         color: #ffffff;
  	         text-decoration: none;
  	         padding:0px 3px 0px 3px;
  	         border-top: 1px solid #CBE3FF;
  	         border-right: 1px solid #003366;
  	         border-bottom: 1px solid #003366; \
  	         border-left:1px solid #B7CFEB;
  	 }
     td {white-text}
END
return $css;

}


#  if ( $ENV{REQUEST_URI} =~ /Glyco_prediction/ ) {
#    $self->displayUnipepHeader( %args );
#    return;
#  }
  



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

    my $loadscript = "$args{onload};" if $args{onload};
    $loadscript .= 'sortables_init();' if $args{sort_tables};
    $log->debug( $loadscript );

    #### If the output mode is not html, then we don't want a header here
    if ($sbeams->output_mode() ne 'html') {
      return;
    }

    if( $sbeams->isGuestUser() ) {
      $self->displayUnipepHeader(@_);
      return();
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
    $header_bkg = "background=\"/images/plaintop.jpg\"" if ($DBVERSION =~ /Primary/);

    print qq~
	<!--META HTTP-EQUIV="Expires" CONTENT="Fri, Jun 12 1981 08:20:00 GMT"-->
	<!--META HTTP-EQUIV="Pragma" CONTENT="no-cache"-->
	<!--META HTTP-EQUIV="Cache-Control" CONTENT="no-cache"-->
	</HEAD>

	<!-- Background white, links blue (unvisited), navy (visited), red (active) -->
	<BODY BGCOLOR="#FFFFFF" TEXT="#000000" LINK="#0000FF" VLINK="#000080" ALINK="#FF0000" TOPMARGIN=0 LEFTMARGIN=0 OnLoad="$loadscript self.focus();">
	<table border=0 width="100%" cellspacing=0 cellpadding=1>

	<!------- Header ------------------------------------------------>
	<a name="TOP"></a>
	<tr>
	  <td bgcolor="$BARCOLOR"><a href="http://db.systemsbiology.net/"><img height=64 width=64 border=0 alt="ISB DB" src="$HTML_BASE_DIR/images/dbsmlclear.gif"></a><a href="https://db.systemsbiology.net/sbeams/cgi/main.cgi"><img height=64 width=64 border=0 alt="SBEAMS" src="$HTML_BASE_DIR/images/sbeamssmlclear.gif"></a></td>
	  <td align="left" $header_bkg><H1>$DBTITLE - $SBEAMS_PART<BR>$DBVERSION</H1></td>
	</tr>

    ~;

    print $sbeams->getSortableHTML() if $args{sort_tables};
    my $prophet_control = $self->get_prophet_control();

    if ($navigation_bar eq "YES") {
      print qq~
	<!------- Button Bar -------------------------------------------->
	<tr><td bgcolor="$BARCOLOR" align="left" valign="top">
	<table border=0 width="120" cellpadding=2 cellspacing=0>

	<tr><td><a href="$CGI_BASE_DIR/main.cgi">$DBTITLE Home</a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_PART/main.cgi">$SBEAMS_PART Home</a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/logout.cgi">Logout</a></td></tr>
	<tr><td>&nbsp;</td></tr>
	<tr><td>Browse Data:</td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/Glyco_prediction.cgi" TITLE="Search by accession, sequence, name"><nobr>&nbsp;&nbsp;&nbsp;Search Glycopeptides</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/browse_glycopeptides.cgi" TITLE="View list of all observed proteins"><nobr>&nbsp;&nbsp;&nbsp;Identified Proteins</nobr></a></td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/showPathways" TITLE="View observed peptides in context of KEGG maps"><nobr>&nbsp;&nbsp;&nbsp;Pathway Search</nobr></a></td></tr>
<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/massSearch" TITLE="Search for peptides by mass range"><nobr>&nbsp;&nbsp;&nbsp;Mass Search</nobr></a></td></tr>
<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/bulkSearch" TITLE="Perform batch search with list of accessions"><nobr>&nbsp;&nbsp;&nbsp;Bulk Search</nobr></a></td></tr>
<!--<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/getAnnotations" TITLE="Get annotations from list of reference accessions"><nobr>&nbsp;&nbsp;&nbsp;Fetch Annotations</nobr></a></td></tr>-->
<tr><td><a href="http://www.unipep.org"><nobr>&nbsp;&nbsp;&nbsp;Unipep home</nobr></a></td></tr>

	<tr><td>&nbsp;</td></tr>
	<tr><td>Manage Tables:</td></tr>
	<tr><td><a href="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=GP_biosequence_set"><nobr>&nbsp;&nbsp;&nbsp;BioSequenceSets</nobr></a></td></tr>
	<tr><td>&nbsp;</td></tr>
	<tr><td>$prophet_control</td></tr>

	</table>
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

sub getStatsHTML {
  my $self = shift;
  my $sbeams = $self->getSBEAMS();
  my $current = $self->get_current_prophet_cutoff();
  return $sbeams->getGifSpacer(800);
}

sub get_prophet_control {
  my $self = shift;
  my $current = $self->get_current_prophet_cutoff();
  my @stock = qw( 0.5 0.6 0.7 0.8 0.9 0.95 0.99 1.0 );
  if ( defined $current && !grep /^$current$/, @stock ) {
    push @stock, $current;
    @stock = sort{ $a <=> $b }(@stock);
  }
  my $update_script = 'ONCHANGE="update_prophet_score()"';
  $sbeams ||= $self->getSBEAMS();
  my $self_url = $sbeams->get_self_url();
  $self_url =~ s/\?.*$//g;

  my $url_params = $sbeams->get_url_params( escape => 0,
                                            omit => [qw( glyco_prophet_cutoff )] );

  my $select = $sbeams->new_option_list(  names => \@stock,
                                       'values' => \@stock,
                                       selected => $current,
                                      list_name => 'glyco_prophet_cutoff',
                                          attrs => $update_script
                                        );
  my $form =<<"  END";
  <SCRIPT LANGUAGE=javascript>
    function update_prophet_score() {
      var form = document.getElementById('prophet_form' );
      form.submit();
    }
  </SCRIPT>
  <FORM METHOD=POST ACTION=$self_url NAME=set_prophet_score ID=prophet_form>
  $url_params
  <TABLE>
    <TR>
     <TD NOWRAP=1 ALIGN=RIGHT><B>Prophet cutoff:</B></TD>
     <TD ALIGN=LEFT>$select</TD>
    </TR>
  </TABLE>
  </FORM>
  END
  return $form
}

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

  function toggle_state( element ) {
    var state = element.checked; 
    var name = element.name; 
    var new_state = 'sequence_font';
    if ( state ) {
      new_state = element.name;
    }

    var element_spans = document.getElementsByName( name );
    for (var i=0; i < element_spans.length; i++) {
      element_spans[i].className = new_state; 
    }

    
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

  if ( $self->{'_external_footer'} ) {
    print "$self->{'_external_footer'}\n";
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
