#!/usr/local/bin/perl -w

###############################################################################
# Program     : email_data_contributors.pl
# Author      : Nichole King <nking@systemsbiology.org>
# $Id$
#
# Description : This script gathers info about samples to be encorporated into
##              APD, and emails the data contributors asking them to edit
#               their sample pages. 
#
###############################################################################



###############################################################################
   # Generic SBEAMS setup for all the needed modules and objects
###############################################################################
use strict;
use Getopt::Long;
use FindBin;

use Mail::Sendmail; 


use lib "$FindBin::Bin/../../perl";
#use lib qw(/tools/lib/perl5/site_perl ../lib);
use vars qw ($sbeams $sbeamsMOD $q $current_username
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG $TESTONLY
            );

#### Set up SBEAMS core module
use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;
$sbeams = SBEAMS::Connection->new();

use SBEAMS::Proteomics;
use SBEAMS::Proteomics::Settings;
use SBEAMS::Proteomics::Tables;

use SBEAMS::PeptideAtlas;
use SBEAMS::PeptideAtlas::Settings;
use SBEAMS::PeptideAtlas::Tables;

$sbeams = new SBEAMS::Connection;
$sbeamsMOD = new SBEAMS::PeptideAtlas;
$sbeamsMOD->setSBEAMS($sbeams);
$sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);

##Don;t need these right?:
#use CGI;
#$q = CGI->new();

###############################################################################
# Set program name and usage banner for command like use
###############################################################################
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
Usage: $PROG_NAME [OPTIONS]
Options:
    --testprint            If set, prints all email text to screen
    --testsend             If set, sends all email to me
    --sendtoall            If set, sends email to primary email contacts
    --sendto               Send email to "name1 name2 name3", for example
    --peptide_summary_name Name of the APD build record

e.g.:  ./email_data_contributors.pl --testprint --peptide_summary_name "Human PeptideAtlas Experiments P>=0.7 (version July 2004)"
e.g.:  ./email_data_contributors.pl --peptide_summary_name "Human PeptideAtlas Experiments P>=0.7 (version July 2004)" --sendto "wyan phaller jwatts"

EOU

####### Process options #######################
unless (GetOptions(\%OPTIONS,"testprint","testsend","sendtoall",
       "sendto:s","peptide_summary_name:s",
     )) {
    print "$USAGE";
    exit;
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
                  work_group=>'PeptideAtlas_admin',
    ));


    $sbeams->printPageHeader() unless ($QUIET);
    handleRequest();
    $sbeams->printPageFooter() unless ($QUIET);


} # end main

###############################################################################
# handleRequest
###############################################################################
sub handleRequest {
    my %args = @_;

    #### Set the command-line options
    my $testprint = $OPTIONS{"testprint"} || '';
    my $testsend = $OPTIONS{"testsend"} || '';
    my $sendtoall = $OPTIONS{"sendtoall"} || '';
    my $sendto = $OPTIONS{"sendto"} || '';
    my $peptide_summary_name = $OPTIONS{"peptide_summary_name"} || '';

    #### Verify required parameters
    unless ($peptide_summary_name) {
        print "$USAGE";
        print "\nERROR: You must specify a --peptide_summary_name\n\n";
        exit;
    }

    ## --sendtoall && (--testprint || --testsend)  will not work
    if ($sendtoall  && ($testsend || $testprint)) {
        print "ERROR: select --sendtoall without a --test[option], but not both\n";
        print "$USAGE";
        exit;
    }

    unless ($sendtoall || $testsend || $testprint || $sendto) {
        print "$USAGE";
        print "ERROR: select --sendtoall  or --sendto  or  --testprint  or --testsend  for action\n";
        exit;
    }


    #### If there are any parameters left, complain and print usage
    if ($ARGV[0]){
        print "ERROR: Unresolved command line parameter '$ARGV[0]'.\n";
        print "$USAGE";
        exit;
    }

    #### Print out the header
    unless ($QUIET) {
        $sbeams->printUserContext();
        print "\n";
    }

    #### Get the search_batch_id_list for the supplied peptide_summary_name
    my $sql;
    $sql = qq~
      SELECT experiment_list
        FROM $TBAPD_PEPTIDE_SUMMARY
       WHERE peptide_summary_name = '$peptide_summary_name'
         AND record_status != 'D'
    ~;
    ## note, if sending email on an old build, will have to go through
    ## Proteomics records to get back to sample_id (through sample_tag)...

    
    my @rows = $sbeams->selectOneColumn($sql);  # should return a single entry
    my $search_batch_id_list = @rows[0];

    unless (scalar(@rows) == 1) {
    print "ERROR: Unable to find the peptide_summary_name '$peptide_summary_name' ".
        "with $sql\n\n";
    return;
    }

    #handle the Email 
    handleEmail(peptide_summary_name => $peptide_summary_name,
                search_batch_id_list => $search_batch_id_list,
                testprint => $testprint,
                testsend => $testsend,
                sendto => $sendto,
    );
} # end handleRequest

###############################################################################
# handleEmail -- Uses search_batch_id_list entries to gather info from PeptideAtlas
#                sample table
#             -- If testprint is true, prints to screen
#                Else If testsend is true, sends all email to me
##               Else sends email to primary contacts
###############################################################################
sub handleEmail {
    my %args = @_;
    my $search_batch_id_list = $args{'search_batch_id_list'};
    my $peptide_summary_name = $args{'peptide_summary_name'};
    my $testprint = $args{'testprint'} || 0;
    my $testsend = $args{'testsend'} || 0;
    my $sendto = $args{'sendto'} || 0;

    my (@sample_id,  @sample_tag, @contact, @info, @url);

    my @search_batch_array = split(",",$search_batch_id_list);
    
    my $i=0;
    foreach my $search_batch_id (@search_batch_array) {

        my $sql;

        #### Get the current list of peptides in the peptide table:
        $sql = qq~
            SELECT sample_id,sample_tag,primary_contact_email
            FROM $TBAT_SAMPLE
            WHERE search_batch_id = '$search_batch_id'
            AND record_status != 'D'
        ~; 
        my @rows = $sbeams->selectSeveralColumns($sql);

        unless (@rows)  {
            die "Unable to find any sample info for search_batch_id=$search_batch_id.\n";
        }

        $sample_id[$i] = @rows->[0]->[0];
        $url[$i] = "https://db.systemsbiology.net/sbeams/cgi/PeptideAtlas/ManageTable.cgi?TABLE_NAME=AT_sample&sample_id=$sample_id[$i]";
        $sample_tag[$i] = @rows->[0]->[1];
        $contact[$i] = @rows->[0]->[2];

        $i++;
    }  ## end of foreach in search_batch_array


    ## keys=contact, values= string of array indices holding contact
    my %contact_hash;
    for ($i=0; $i < $#search_batch_array; $i++) {
        if ($contact_hash{$contact[$i]}) {
            $contact_hash{$contact[$i]} = join " ", $contact_hash{$contact[$i]}, $i; 
        } else {
            $contact_hash{$contact[$i]} = $i; 
        }
    }  ## end making contact_hash


    ## gathering urls for contact:
    my %url_list;
   
    foreach my $index_str (values ( %contact_hash ) ) {

        my @index_array = split(" ", $index_str);

        for (my $ii = 0; $ii <= $#index_array; $ii++) {
    
            my $ind=$index_array[$ii]; 
    
            $url_list{$contact[$ind]} = join "\n", $url_list{$contact[$ind]}, $url[$ind];
        }
    }

    my @recipients;
    if ($sendto) {
        @recipients = split(" ", $sendto); 
    }

    foreach (sort keys %contact_hash) {
        if ($sendto) { ## email only specified contacts:
            for (my $i=0; $i<$#recipients;$i++){
                if ($_ =~ $recipients[$i]) { ##parse for match to spec. contacts
                    emailContact(contact => $_,
                        list_urls => $url_list{$_},
                        testprint => $testprint,
                        testsend => $testsend,
                    );
                }
            }
        } else { ## email entire contact hash:
            emailContact(contact => $_,
                list_urls => $url_list{$_},
                testprint => $testprint,
                testsend => $testsend,
            );
        }
    }

    
}  #end handleEmail

############################################################################################
sub emailContact {
    my %args = @_;
    my $testprint = $args{'testprint'} || 0;
    my $testsend = $args{'testsend'} || 0;
    my $list_urls = $args{'list_urls'};

    my $contact = $args{'contact'};
    my $recipient = $contact;
    $recipient = "nking\@systemsbiology.org" if ($testprint || $testsend);

    my $cc_name = "Nichole King";
    my $cc = "nking\@systemsbiology.org"; 

    my %mail;

    $mail{To}   = "<$recipient>";
    $mail{From} = "nking\@systemsbiology.org";
    $mail{Cc}   = "$cc_name <$cc>";
    $mail{Subject} = "Your information in PeptideAtlas";
    $mail{Message} = "\nDear PeptideAtlas Data Contributor or Proxy,\n\n
   Please follow the links below to edit the **publicly available** 
information about your data in PeptideAtlas.  The new build is finished, 
so please make changes to your sample record as soon as possible.

Thank you for participating,
    Cheers,
        Nichole

    Use [UPDATE] button after making changes, and please let me know if 
there are problems.

Here are the links for $contact: \n

    $list_urls \n \n";

    if ($testprint) {
        foreach (keys %mail) {
           print "$mail{$_} \n";
        }
    } else {
        sendmail (%mail) or die $Mail::Sendmail::error;
    }

    ##NOTE: should wrap it in HTML/MIME for email...MAC email not handling 1st url?
}
