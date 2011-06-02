#!/usr/local/bin/perl

###############################################################################
# Program     : repository.cgi
# Author      : Zhi Sun
# Description : This script shows the PeptideAtlas repository page
#
# SBEAMS is Copyright (C) 2000-2011 Institute for Systems Biology
# This program is governed by the terms of the GNU General Public License (GPL)
# version 2 as published by the Free Software Foundation.  It is provided
# WITHOUT ANY WARRANTY.  See the full description of GPL terms in the
# LICENSE file distributed with this software.
#
###############################################################################
use strict;
use CGI::Carp qw(fatalsToBrowser croak);
use FindBin;
use POSIX qw(ceil floor);
use lib "$FindBin::Bin/../../lib/perl";
use vars qw ($sbeams $sbeamsMOD $q $current_contact_id $current_username);

use SBEAMS::Connection qw($q $log);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Authenticator;

use SBEAMS::PeptideAtlas;
use SBEAMS::PeptideAtlas::Settings;
use SBEAMS::PeptideAtlas::Tables;

$sbeams = new SBEAMS::Connection;
my $atlas = new SBEAMS::PeptideAtlas;
$atlas->setSBEAMS($sbeams);

exit unless ($current_username = $sbeams->Authenticate(
      permitted_work_groups_ref=>['PeptideAtlas_user','PeptideAtlas_admin',
      'PeptideAtlas_readonly', 'PeptideAtlas_exec'],
      allow_anonymous_access=>1,
  ));

$atlas->displayGuestPageHeader();

my $html = qq~

  <head xmlns:xi="http://www.w3.org/2001/XInclude">
		<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
					
		<title>Repository</title>

		<script type='text/javascript' src="$CGI_BASE_DIR/../usr/javascript/repository/js/portal.js"></script>
		<script type="text/javascript" src="$CGI_BASE_DIR/../usr/javascript/repository/js/jig.min.js"></script> 

		<link rel="stylesheet" type="text/css" href="$CGI_BASE_DIR/../usr/javascript/repository/css/ext-all.css" />
		<script type="text/javascript" src="$CGI_BASE_DIR/../usr/javascript/repository/js/ext-big.js"></script>
		<script type="text/javascript" src="$CGI_BASE_DIR/../usr/javascript/repository/js/grid_ISB.js"></script>

	<!--[if IE]>
			<style>div#ext-gen27 {height:0px; }</style>
			<![endif]-->
		<style>
			#south-panel .x-tool-collapse-south {
			background-position:0 -210px;
			}
			#south-panel .x-tool-collapse-south-over {
			background-position:-15px -210px;
			}
			#south-panel-xcollapsed .x-tool-expand-south {
			background-position:0 -195px;
			}
			#south-panel-xcollapsed .x-tool-expand-south-over {
			background-position:-15px -195px;
			}
			.x-grid3-header-offset{padding-left:1px;width:auto !important;}
			ul.x-tab-strip {        
					width:auto !important;
			}
			#contentbox-left {width: 99% !important;}
			#contentbox-right {width: 1px !important; display:none; margin-right:0px !important;}
			div#display_bar1 { display: none;}
		</style>

		<script type="text/javascript">
							var browseAttributes = {
							sample: '',
							}
		</script>

		</head>
		<body class="datagrid">

			 <form style="width: 1000px;overflow:auto;padding: 5px;-ro-width: auto;" enctype="application/x-www-form-urlencoded" action="/" name="EntrezForm" method="post" onsubmit="return false;" id="EntrezForm">
	<div>
	<br>
	<h5>RAW DATA AVAILABLE FOR DOWNLOAD</h5>
	<br>
					<p class="rep">
						It is our policy to make publicly available for download as much
						of the raw data we use to build the PeptideAtlas as possible.
						This includes datasets that have been previously published or
						otherwise released by the data producers. If you download and use
						these data in a published work, please cite the associated article
						(or data contributors if unpublished);
						an acknowledgement of the PeptideAtlas repository would also be
						appreciated.  There are also many unpublished raw datasets used to
						build the PeptideAtlas, and these are not made available for
						download until publication or release by the producers.
					</p>
	<br>
					<p class="rep">
						If you need help, please write to us with our feedback page on the
						navigation bar.
	<br>
						If you would like to browse the old repository page, click <a href="http://www.peptideatlas.org/repository/index_old.php">here</a>
					</p>

	<br>
	</div>
	<div class="search">
	<span>&nbsp;&nbsp;Search:&nbsp;</span>
	<select id="selectedTitle" name="selectedTitle" style="font-size:92%">
	<option value="all" selected="selected">&nbsp;All </option>
	<option value="acc" >&nbsp;Accession</option>
	<option value="title" >&nbsp;Sample Title</option>
	<option value="tag" >&nbsp;Sample Tag</option>
	<option value="organism" >&nbsp;Organism</option>
	<option value="publication" >&nbsp;Publication</option>
	<option value="instrument" >&nbsp;Instrument</option>
	<!--<option value="date" >&nbsp;Release Date</option>-->
	</select>
	<span>for</span>
	<input type="text" size="38" id="searchq" name="searchq"  >
	<input type="button" id="searchbtn" name="searchbtn" class="sarchBtnOK" value="Search" >

	<span>&nbsp;&nbsp;Select:&nbsp;</span>
	<select id="selectFileType" name="selectFileType" style="font-size:92%">
	<option value="all" selected="selected">&nbsp;All </option>
	<option value="params" >&nbsp;Parameter File</option>
	<option value="raw" >&nbsp;RAW</option>
	<option value="mzXML" >&nbsp;mzXML</option>
	<option value="search_result" >&nbsp;Search Result</option>
	<option value="prot" >&nbsp;TPP Result</option>
	<option value="readme" >&nbsp;README</option>
	</select>
	<span>to</span>
	<input type="button" id="downloadbtn" name="downloadbtn" value="Get Download List">
	&nbsp;&nbsp; 
	<input type="button" id="downloadbtn2" name="downloadbtn2" value="Download Table">

	</div>

               <table cellpadding="0" width="100%" cellspacing="0" id="br1owseWrapper">                    
                    <tr>
                      <td valign="top">
                        <div class="datagrid"> 
                          <div id="sample-layout"></div>
                          <div id="tabsPanel"></div>
                          <div id="center"></div>
                          <div id="samplestudyWrapper">
                             <div id="browse"> 
                                <div id="toolbar"></div>
                                <div id="prot-grid"></div>
                             </div>  <!--"browse"  -->
                           </div>   <!-- "samplestudyWrapper" -->
                        </div> <!-- "datagrid" -->
                    </td>
                    </tr>
	</table>
	</form>
	</body>
~;

print $html;
$atlas->display_page_footer();


exit;

