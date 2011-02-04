#!/usr/local/bin/perl  

#######################################################################
# write_repository_lists -- generates the public and "not public" 
#   xml files for the repository area and handles population of
#   apache accessible files in the public repository area.  
#   The file versioning system within uses timestamp, timestamp
#   property files, and database stored properties to handle
#   versioning. It determines when new files are to be written
#   by comparing properties in the current repository file
#   to properties written into SBEAMS PeptideAtlas records.
#   The information in a timestamp properties text
#   file represents the content of a file in the 
#   apache accessible repository area.  The database properties 
#   information represents the content of file in the sbeams archive
#   file area.  A use case is:  the sbeams archive mzXML files get
#   reconverted to modern mzXML format, and the database properties
#   get updated.  This script would see that that the latest repository
#   mzXML files are lagging behind the files in /sbeams/archive and
#   so would then make new timestamped tar archives and place them
#   in the apache accessible repository area.
#
#   Author: Nichole King
#
#   $Ning Zhang @09062007 Modified the script
#   in order to only show the latest search results and newest mzXML.
#   Before the change, multiple search batches may be existed for one
#   sample and they are showed in the web page and pa_public_archive.
#   (1)change in get_data_url() =>get rid of existing mzXML.tar.gz
#   (2)change in write_public_file =>only get the latest search batch results
#   (3)change it run on phoebe
#	
#	Zhi Sun @200908 
#   upload all file to tranche
#   upload newer format of mzXML file and search result to tranche. 
#   remove links for old files
#
# Zhi Sun @201010
#   Create html page directly from this script, remove the dependency of the sForm
#
#######################################################################
use strict;
use Getopt::Long;
use FindBin;
use File::stat;
use XML::Parser;
use IO::File;
use LWP::UserAgent;

use lib "$FindBin::Bin/../../perl";

use vars qw ($sbeams $sbeamsMOD $q $current_username 
             $PROG_NAME $USAGE %OPTIONS $TEST $VERBOSE
             $sbeams_data_path
             $repository_path $tranche_path 
             $errorfile $timestamp_pattern
             $public_php_outfile $notpublic_php_outfile
            );

#### Set up SBEAMS core module
use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;

## PeptideAtlas classes
use SBEAMS::PeptideAtlas;
use SBEAMS::PeptideAtlas::Settings;
use SBEAMS::PeptideAtlas::Tables;

## Proteomics (for search_batch::data_location)
use SBEAMS::Proteomics::Tables;

use SBEAMS::PeptideAtlas::SpectraDescriptionSetParametersParser; 	 
use SBEAMS::PeptideAtlas::SearchResultsParametersParser;


$sbeams = new SBEAMS::Connection;
$sbeamsMOD = new SBEAMS::PeptideAtlas;
$sbeamsMOD->setSBEAMS($sbeams);
$sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);

my $ua = new LWP::UserAgent;
$ua->timeout(120);


## USAGE:
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
Usage: [OPTIONS] key=value key=value ...
Options:
  --test                 test this code, no disk writing

  --test_samples         if would like to run test, using specific samples,
                         can specify them here separated by commas
                         (e.g.,  --test_samples "26,34")

  --run                  run program

  --make_tmp_files       output files are named rep*.tmp to minimize 
                         interruption of active download service

  --sbeams_data_path     path to sbeams data 

  --repository_path      path to directory that apache accesses


e.g.:  ./$PROG_NAME --sbeams_data_path "/regis/sbeams/archive" --repository_path "/regis/sbeams2/pa_public_archive" --make_tmp_files --test --verbose 1

EOU

## get arguments:
GetOptions(\%OPTIONS, "test", "run", "make_tmp_files", "verbose:s",
"sbeams_data_path:s",
"repository_path:s", "test_samples:s");

our $buffer='';
our $notpublic_buffer = '';
our $rowbuffer = '';
## check for required arguments:
unless ( ($OPTIONS{"test"} || $OPTIONS{"run"} || $OPTIONS{"test_samples"} ) && 
$OPTIONS{"sbeams_data_path"} && $OPTIONS{"repository_path"})
{
    print "$USAGE";

    exit;
};

## check format of test_samples if it's used
if ($OPTIONS{"test_samples"})
{
    my @t = split(",", $OPTIONS{"test_samples"});

    unless ($#t >= 0)
    {
        print " Please specify sample ids, seprated by commas.\n"
            . " For example:  --test_samples '54,92'";

        exit;
    }
}


## set some vars based upon arguments:
$TEST = $OPTIONS{"test"} || 0;

$VERBOSE = $OPTIONS{"verbose"} || 0;

$sbeams_data_path = $OPTIONS{"sbeams_data_path"};

$repository_path = $OPTIONS{"repository_path"};

$timestamp_pattern = "+%Y%m%d%H%M";

our %TrancheDescription =();


if ($TEST || $OPTIONS{"test_samples"} )
{
    $repository_path = "$repository_path/TESTFILES";
}



## paths for output files:
$public_php_outfile = "$repository_path/repository_public.php";

$notpublic_php_outfile = "$repository_path/repository_notpublic.php";

$errorfile = "$repository_path/errorfile.txt";

if ( $OPTIONS{"make_tmp_files"} )
{
    $public_php_outfile = $public_php_outfile . ".tmp2";    

    $notpublic_php_outfile = $notpublic_php_outfile . ".tmp2";    
}

#$tranche_path = "/net/dblocal/www/html/devZS/sbeams/lib/scripts/PeptideAtlas/tranche_project";
$tranche_path = "/regis/sbeams/bin/";
#### execute main #####
main();

exit(0);


###############################################################################
# main
###############################################################################
sub main 
{
    #### Do the SBEAMS authentication and exit if a username is not returned
    exit unless ( $current_username = 
        $sbeams->Authenticate(connect_read_only => '1')
    );

    ## make sure that user is on atlas:
    check_host();


    ## check that can write to files (also initializes them):
    check_files();

    ## check that mandatory sample annotation exists
    unless ($TEST)
    {
        check_samples();
    }


    ## write namespace and root tag to xml file:
    initializePhp(public => 1);

    initializePhp(public => 0);

    ## write $public_php_outfile, tar up relevant files and move em if needed
    write_public_file();

    ## write $notpublic_php_outfile
    write_private_file();


    ## write ending root node and check that xml is well-formed
    finalizePhp(public => 1);
    finalizePhp(public => 0);

    print "\nWrote the following files:\n";
    print "$public_php_outfile\n"; 
    open (OUT, ">$public_php_outfile") ;
    print OUT "$buffer\n";
    close OUT;
    print "$notpublic_php_outfile\n"; 
    open (OUT2, ">$notpublic_php_outfile") ;
    print OUT2 "$notpublic_buffer\n";
    close OUT2;

    print "$errorfile\n"; 

    print "\nDial up jsp page on browser to generate static HTML and
    copy that viewed source to web location. \n";

} ## end main

#######################################################################
# check_host -- check that host name is atlas as we need to write to
#   /sbeams/
#######################################################################
sub check_host()
{
    ## make sure that this is running on atlas for queries
    my $uname = `uname -a`;
    unless ($uname =~ /.*(dione).*/)
    {
       die "you must run this on dione";
    }
}

#######################################################################
# check_files -- check that can write to files, and
#   initialize them
#######################################################################
sub check_files()
{
    my @outfiles =  ($public_php_outfile, $notpublic_php_outfile, $errorfile);

    for (my $i=0; $i <= $#outfiles; $i++)
    {
        my $outfile = $outfiles[$i];

        open(OUTFILE,">$outfile") or die 
           "cannot open $outfile for writing";

        close(OUTFILE) or die "cannot close $outfile";
    }
}


#######################################################################
# check_samples -- checks that all samples have needed annotation.
# for example, we shouldn't post data missing data_contributors field
#######################################################################
sub check_samples
{
    my $sql = qq~
        SELECT S.sample_tag, S.data_contributors
        FROM $TBAT_SAMPLE S
        WHERE S.record_status != 'D'
        AND is_public='Y'
        ORDER BY S.sample_tag
    ~;

    my @rows = $sbeams->selectSeveralColumns($sql) or 
        die "Couldn't find sample records using $sql";

    my $exit_flag = 0; ## false

    foreach my $row (@rows)
    {
        my ($st, $dc) = @{$row};

        if ($dc eq "")
        {
            print "[ERROR] $st is missing data_contributors\n";

            #$exit_flag = 1; zhi
        }

    }

    if ($exit_flag)
    {
        die "\nNeed to fill in data_contributors before running this\n";
    } else
    {
        print "\nHave all of minimum required sample annotation\n";
    }

}


#######################################################################
# write_public_file -- writes repository_public.xml file.  
#    While at it, sees if files exist in public archive area, and if
#    so, sees if they are the most current known.  If the files are not
#    the most current, it makes tar archives of the most
#    current and copies them to the public archive area, with a timestamp
#    in their name, and a timestamped properties file containing the
#    the fundamental properties of the file to check for changes
#    (changes such as mzXML schema version, for example).
#
#    NOTE: method essentially stores the results from a query for all sample 
#    records into a data structure and re-uses the structure.  if
#    one day find ourselves memory limited, will need to break
#    get_publication_info(), get_public_sample_info(), and 
#    get_data_directories() into queries that produce smaller returns
#    here and change iteration accordingly...this procedure should
#    probably be it's own module too.
#######################################################################
sub write_public_file
{
    my $sql;

    if ($OPTIONS{"test_samples"})
    {
        ## get a string of sample id formatted for use in IN clause of
        ## SQL statement
        my $test_sample_ids = formatSampleIDs(
            sample_ids => $OPTIONS{"test_samples"});
        $sql = qq~
        SELECT distinct S.sample_accession, S.sample_tag, S.sample_id,
        O.organism_name, S.is_public
        FROM $TBAT_SAMPLE S
        JOIN $TBAT_ATLAS_BUILD_SAMPLE ABS ON (ABS.sample_id = S.sample_id)
        JOIN $TBAT_ATLAS_BUILD AB ON (AB.atlas_build_id = ABS.atlas_build_id)
        JOIN $TBAT_BIOSEQUENCE_SET BS ON (BS.biosequence_set_id = AB.biosequence_set_id)
        JOIN $TB_ORGANISM O ON (BS.organism_id = O.organism_id)
        WHERE S.is_public = 'Y' AND S.record_status != 'D'
        AND S.sample_id IN ($test_sample_ids)
        ORDER BY O.organism_name, S.sample_tag
        ~;
        
    } elsif ($TEST)
    {   ## Use 2 records for TEST
        $sql = qq~
        SELECT distinct S.sample_accession, S.sample_tag, S.sample_id,
        O.organism_name, S.is_public
        FROM $TBAT_SAMPLE S
        JOIN $TBAT_ATLAS_BUILD_SAMPLE ABS ON (ABS.sample_id = S.sample_id)
        JOIN $TBAT_ATLAS_BUILD AB ON (AB.atlas_build_id = ABS.atlas_build_id)
        JOIN $TBAT_BIOSEQUENCE_SET BS ON (BS.biosequence_set_id = AB.biosequence_set_id)
        JOIN $TB_ORGANISM O ON (BS.organism_id = O.organism_id)
        WHERE S.is_public = 'Y' AND S.record_status != 'D'
        ORDER BY O.organism_name, S.sample_tag
        ~;
#AND S.sample_id != '198' AND S.sample_id != '292'
    } else
    {
        $sql = qq~
        SELECT distinct S.sample_accession, S.sample_tag, S.sample_id,
        O.organism_name, S.is_public
        FROM $TBAT_SAMPLE S
        JOIN $TBAT_ATLAS_BUILD_SAMPLE ABS ON (ABS.sample_id = S.sample_id)
        JOIN $TBAT_ATLAS_BUILD AB ON (AB.atlas_build_id = ABS.atlas_build_id)
        JOIN $TBAT_BIOSEQUENCE_SET BS ON (BS.biosequence_set_id = AB.biosequence_set_id)
        JOIN $TB_ORGANISM O ON (BS.organism_id = O.organism_id)
        WHERE S.is_public = 'Y' AND S.record_status != 'D'
        AND S.sample_id != '198' AND S.sample_id != '292'
        ORDER BY O.organism_name, S.sample_tag
        ~;
        ## xx temporarily adding ignore MicroProt datasets as their 
        ## interact file names are too highly specialized...
    }

    my @rows = $sbeams->selectSeveralColumns($sql) or 
        die "Couldn't find sample records using $sql";

   my $date = `date`;
   my $sample_number = scalar @rows -1;
   $buffer .= qq~ <p class="rep">
      There are
      $sample_number  experimental datasets available for download ($date)</p><br/>
      <form action="http://db.systemsbiology.net/webapps/repository/sForm" method="post">

      <input type="button" value="Mark All Matching Records" onClick="MarkSelectedTexts()">
      <input type="button" value="Generate Hash File" onClick="GenerateHashFile()">
      <input type="button" value="TrancheDownloader" onClick="window.open('https://proteomecommons.org/tranche/advanced.jsp')">

      <table class="rep" id="table1">

      <tbody>
      <tr><th class="rep">
              Sample Accession
            </th><th class="rep">
              Name
            </th><th class="rep">
                Organism
            </th><th class="rep"><a target="_blank" href="http://www.peptideatlas.org/repository/resources_help.php">
                Resources
              </a></th><th class="rep">
                Description
            </th><th class="rep">

                Data Contributors
            </th><th class="rep">
                Related Publications
            </th></tr>
     ~;

    ## store query results in $sample_info
    for (my $i=1; $i< scalar @rows; $i+=1) 
    {
        my $row = $rows[$i];
        %TrancheDescription =();
        my (@file_array_for_README, @pubmed_id_array_for_README);
        my (@pub_cit_array_for_README, @pub_url_array_for_README);
        my ($sample_accession, $sample_tag, $sample_id, $organism, 
            $is_public) = @{$row};

        next if($organism eq 'Chimpanzee');
        #next if( $sample_accession !~ /PAe0012(89|82|91|86|88|80|81|90|87)/);
        print "$sample_accession\n";

        my $sql2 = qq~
        SELECT S.sample_description, S.data_contributors
        FROM $TBAT_SAMPLE S
        WHERE S.sample_id = $sample_id
        AND S.record_status != 'D'
        ~;

        my @rows2 = $sbeams->selectSeveralColumns($sql2) or 
            die "Couldn't find sample records using $sql2";
        my ($sample_description, $data_contributors);

        ## store query results in $sample_info
        foreach my $row2 (@rows2) 
        {
            my ($d, $c) = @{$row2}; 
            ## replace dos end of line markers (\r) and (\n) with space
            $sample_description = $d;
            $data_contributors = $c;
            $sample_description =~ s/\r/ /g;
            $sample_description =~ s/\n/ /g;
            $data_contributors =~ s/\r/ /g;
            $data_contributors =~ s/\n/ /g;
        }
        
        $TrancheDescription{sample_description} = $sample_description;
        $TrancheDescription{data_contributors} = $data_contributors;

        ## write to xml file, the start of the sample tag, and some of the sample info:
        startSampleTag(
            sample_accession => $sample_accession,
            sample_tag => $sample_tag,
            organism => $organism,
            description => $sample_description,
            data_contributors => $data_contributors,
        );
        ######### handle the remaining resources  ####
        #### resource mzXML_format
        #### resource RAW_format
        #### resource Search_Results
        #### resource ProteinProphet_file
        #### resource sequest.params
        #### resource qualscore_results
        #### publication citation
        #### resource README


        ## (1 sample record <--> 1 spectra_description_set). i.e. not pointing to last mzXML file
        ## anymore in the repository xml file for clarity, but the older archive files will still
        ## be present in the apache accessible archive area for anyone dialing up the url directly.
        my $spectra_data_dir = get_spectra_location( sample_id => $sample_id);

        ## get mzXML url, check properties of database with timestamp properties file ( if lagging,
        ## pack up new files etc, or if the archive doesn't already exist create the archive file, etc)
        my $mzXML_url= get_mzXML_url(  
                       sample_id => $sample_id, 
                       organism => $organism,
                       sample_accession => $sample_accession, 
                       spectra_data_dir => $spectra_data_dir,
                       );
        my $mzXML_size  = getFileSize( file => $repository_path, 
                                      accession => $sample_accession."_mzXML",
                                       url  => $mzXML_url);

        addResourceTag(attr_name => "mzXML_format", 
                       attr_value => $mzXML_url, 
                       file_size => $mzXML_size);
       push(@file_array_for_README, "mzXML_$mzXML_size");


        ## get orig data type by searching data dir for known suffixes
        my $origDataType = get_orig_data_type( data_dir => $spectra_data_dir);
        if ($origDataType)
        {
            ## get original data url, if don't see it in the public repository, pack up files etc, 
            ## [this uses a subset of get_data_url, so one day, could redesign those few subs...]
            ## For some of the older HUPO datasets, the original spectra aren't available,
            ## so we only have the dtas.  We're giving those a datatype/suffix of dtapack
            ## which means there are a few special edits for it in several places in this
            ## script (search for dta to edit those)

            my $orig_data_url = get_orig_data_url(  
                sample_id => $sample_id,
                organism => $organism,
                sample_accession => $sample_accession, 
                spectra_data_dir => $spectra_data_dir,
                orig_data_type => $origDataType,
            );
       
            my $attr = $origDataType . "_format";
            my $orig_data_size = getFileSize( file => $repository_path, 
                                              accession => $sample_accession."_$origDataType",
                                              url => $orig_data_url);
            ## write xml resource element for this:
            addResourceTag(attr_name => $attr, 
                           attr_value => $orig_data_url,  
                           file_size => $orig_data_size);
            push(@file_array_for_README, $origDataType."_$orig_data_size");
        }

        ###########  iterate over all search batches for this sample #############
       	#unlike before, we only want to latest search results
       	#in other words, the highest atlas_search_batch_id

        my $sql2 = qq~
            SELECT distinct ASB.TPP_version, ASB.atlas_search_batch_id, ASB.data_location,
            ASB.search_batch_subdir
            FROM $TBAT_ATLAS_SEARCH_BATCH ASB
            JOIN $TBAT_SPECTRA_DESCRIPTION_SET SDS
            ON (ASB.atlas_search_batch_id = SDS.atlas_search_batch_id)
            JOIN $TBAT_SAMPLE S ON (S.sample_id = SDS.sample_id)
            WHERE S.sample_id = '$sample_id'
            AND S.is_public = 'Y' AND S.record_status != 'D'
            ORDER BY ASB.atlas_search_batch_id DESC
        ~;

        my @rows2 = $sbeams->selectSeveralColumns($sql2) or 
        die "Couldn't find ATLAS_SEARCH_BATCH records for sample $sample_id";

       	#Ning changed the following code
        #foreach my $row2 (@rows2) 
        #{
            my ($TPP_version, $atlas_search_batch_id, $data_location,
                $search_batch_subdir) = @{$rows2[0]};
            
            $data_location = $data_location . "/" . $search_batch_subdir;

            ## if path has /data3/sbeams/archive/, remove that
            $data_location =~ s/^(\/data3\/sbeams\/archive\/)(.+)$/$2/gi;

            ## if path starts with a /, remove that
            $data_location =~ s/^(\/)(.+)$/$2/gi;

            ## make absolute path
            $data_location = "$sbeams_data_path/$data_location";
            $data_location=~ s/interact.*$//;

            ## make sure it exists:
            unless ( -d $data_location )
            {
               die "$data_location does not exist";
            }

            ## for each row returned, get a url (checking for timestamp properties file, etc)
            ## NOTE, this leads to copy over of the sequest.params file and the qualscore_results
            ## too, so will recover those filenames next with file tests
            my $search_results_url = get_search_results_url (
                TPP_version => $TPP_version,
                organism => $organism,
                atlas_search_batch_id => $atlas_search_batch_id, 
                sample_accession => $sample_accession,
                search_results_dir => $data_location,
            );

            my $search_results_size = getFileSize( file => $repository_path,
                                              accession => $sample_accession."_Search_Results" ,
                                                   url  => $search_results_url);
            ## write url to xml file as attribute in a resource element
            addResourceTag(attr_name => "Search_Results", 
                           attr_value => $search_results_url, 
                           file_size => $search_results_size,
                           asbid => $atlas_search_batch_id);

            push(@file_array_for_README, "Search_Results_".$search_results_size);

            ## retrieve and write tags for sequest.params and qualscore_results 
            my $prefix = $sample_accession . "_" . $atlas_search_batch_id;
            my $sequest_params_file_name = "$prefix" . "_sequest.params";
            my $hqus_file_name = "$prefix" . "_qualscore_results";
            my $sequest_params_file_url = get_an_sb_file_url (
                file_name => $sequest_params_file_name,
                sb_file_name => "sequest.params",
                search_results_dir => $data_location,
                organism => $organism,
                
            );
            my $hqus_file_url = get_an_sb_file_url (
                file_name => $hqus_file_name,
                sb_file_name => "qualscore_results",
                search_results_dir => $data_location,
                organism => $organism,
            );

            $sequest_params_file_name = "$repository_path/$sequest_params_file_name";
            $hqus_file_name = "$repository_path/$hqus_file_name";
                
            if (-e $sequest_params_file_name)
            {
                push(@file_array_for_README,  "sequest_0");
                ## write url to xml file as attribute in a resource elementn
                addResourceTag(attr_name => "sequest_params", 
                    attr_value => $sequest_params_file_url,
                    asbid => $atlas_search_batch_id);
            }

            if (-e $hqus_file_name)
            {
                ## write url to xml file as attribute in a resource element
                addResourceTag(attr_name => "qualscore_results", 
                    attr_value => $hqus_file_url,
                    asbid => $atlas_search_batch_id);
                push(@file_array_for_README, "qualscore_0")
            }

            ## for each row returned, get a url (checking for timestamp properties file, etc)
            my $protein_prophet_url = get_protein_prophet_url (
                TPP_version => $TPP_version,
                organism => $organism,
                atlas_search_batch_id => $atlas_search_batch_id,
                sample_accession => $sample_accession,
                search_results_dir => $data_location
            );
            my $ProteinProphet_size = getFileSize( file => $repository_path,
                                              accession => $sample_accession."_prot",
                                                   url  =>$protein_prophet_url  ); 
            ## write url to xml file as attribute in a resource element
            addResourceTag(attr_name => "ProteinProphet_file", 
                attr_value => $protein_prophet_url, 
                asbid => $atlas_search_batch_id,
                file_size => $ProteinProphet_size);

            push(@file_array_for_README, "prot_$ProteinProphet_size");

      #}

        ####  handle publication citations  #####
        my $sql3 = qq~
            SELECT P.publication_name, P.uri, P.pubmed_ID
            FROM $TBAT_PUBLICATION P
            JOIN $TBAT_SAMPLE_PUBLICATION SP ON (P.publication_id = SP.publication_id)
            JOIN $TBAT_SAMPLE S ON (S.sample_id = SP.sample_id)
            WHERE S.sample_id = '$sample_id'
            AND SP.record_status != 'D'
        ~;

        my @rows3 = $sbeams->selectSeveralColumns($sql3);

        $rowbuffer .= qq~ <td class="rep"> ~;

        foreach my $row3 (@rows3) 
        {
            my ($pub_name, $pub_url, $pubmed_id) = @{$row3};

            ## write url to xml file as attribute in a resource element
            addPublicationTag( citation => $pub_name, url => $pub_url);

            push(@pubmed_id_array_for_README, $pubmed_id);

            push(@pub_cit_array_for_README, $pub_name);

            push(@pub_url_array_for_README, $pub_url);
        } 

        $rowbuffer .= "</td>";

        ## writes the readme file and returns its URL
        my $readme_url = write_readme_and_get_readme_url(
            sample_accession => $sample_accession,
            sample_tag => $sample_tag,
            organism => $organism,
            description => $sample_description,
            data_contributors => $data_contributors,
            array_of_file_urls_ref => \@file_array_for_README,
            array_of_pub_cit_ref => \@pub_cit_array_for_README,
            array_of_pub_url_ref => \@pub_url_array_for_README,
            array_of_pubmed_ids_ref => \@pubmed_id_array_for_README,
        );
        
       my $readmehash;
       $readmehash = `grep README "$repository_path\/$sample_accession\_tranche.hash"`;
       if($readmehash){
          chomp $readmehash;
          $readmehash =~ /\w+\s+(.*)/;
          $readmehash = $1;
       }
       else {
         my $sample_location = "$repository_path/$sample_accession"."_README";
         $readmehash = upload2tranche(
                   sample_location => $sample_location,
                   organism => $organism);
       }
        ## write url to xml f`ile as attribute in a resource element
        addResourceTag(attr_name => "README", attr_value => $readme_url);
        addResourceTag(attr_name => "README_TRANCHE", attr_value => $readmehash);
        ## write to xml file, the end of the sample tag
        $buffer .= $rowbuffer;

        endSampleTag();
    } ## end loop over samples
}

#######################################################################
# startSampleTag - write sample start tag and sample info to xml file
# @param sample_accession
# @param sample_tag
# @param organism
# @param description
# @param data_contributors
#######################################################################
sub startSampleTag
{
    my %args = @_;

    my $sample_accession = $args{sample_accession} or die "need sample_accession";

    my $sample_tag = $args{sample_tag} or die "need sample_tag";

    my $organism = $args{organism} or die "need organism";

    my $description = $args{description} or die "need description";

    my $data_contributors; 
    if ($TEST)
    {
        $data_contributors = $args{data_contributors}; ## dev database isn't annotated
    } else
    {
       $data_contributors = $args{data_contributors}; # zhi or die "need data_contributors";
    }


    ## write opening sample tag information to xml:
    ## open xml file and writer:
    
    $buffer .= qq~
     <tr><td class="rep">$sample_accession</td>
     <td class="rep">$sample_tag</td>
     <td class="rep">$organism</td>
     <td class="rep">
    ~;
    $rowbuffer = qq~
     <td class="rep">$description</td>
     <td class="rep">$data_contributors</td>
    ~;
}

#######################################################################
# endSampleTag - write end sample tag  to xml file
#######################################################################
sub endSampleTag
{
    ## open xml file and writer:
    $buffer.= "</tr>";

}

#######################################################################
#  get_mzXML_url -- get mzXML url, check properties of database with
#      timestamp properties file and pack up new files if the archive
#      doesn't already exist to create the archive file
# @param sample_id
# @param sample_accession
# @param spectra_data_dir
# @return url for gzipped mzXML archive
#######################################################################
sub get_mzXML_url
{
    my %args = @_;

    my $sample_id = $args{sample_id} or die "need sample_id";

    my $sample_accession = $args{sample_accession} or die "need sample_accession";

    my $spectra_data_dir = $args{spectra_data_dir} or die "need spectra_data_dir";

    my $organism = $args{organism} or die "need organism name";

    ## Get hash of spectra info with keys: conversion_software_name, conversion_software_version,
    ## and mzXML_schema
    my %spectra_properties = get_spectra_properties_info_from_db( sample_id => $sample_id);
    ## Look for latest mzXML file in the archive (it will need to have 
    ## timestamp already in it, no compatibility with old unversioned 
    ## files, as want to create structure anew, while preserving old
    ## files in the archive for people to find if they are looking)
    ##    if latest mzXML is found, get the timestamp txt file and 
    ##        compare it to database properties
    ##        if properties file is lagging behind database,
    ##            create new properties file and new gzipped archive
    ##            return that url
    ##        else return the url for the already up to date mzXML gzipped archive
    ##    else, there's no versioned mzXML file yet, so create it and create the timestamped
    ##    properties file
    ## This functionality is generalized in get_data_url so that other operations can use it...
    my $mzXML_url = get_data_url(
        sample_accession => $sample_accession,
        organism => $organism,
        data_dir => $spectra_data_dir,
        file_suffix => "mzXML",
        file_pattern => "mzXML",
        properties_ref => \%spectra_properties,
        );

    #return $mzXML_url;
   # $file_url = convertAbsolutePathToURL( file_path => $file_path );
    $mzXML_url =~ s/\+/\%2B/g;
    my $file_url = "http://www.proteomecommons.org/data-downloader.jsp?fileName=".$mzXML_url;
    return $file_url;

}


#######################################################################
#  initializePhp -- write xml declaration and root node start tag
#######################################################################
sub initializePhp
{
  my %args = @_;
  my $public = $args{public};;
  if($public){
    $buffer = `cat /net/dblocal/wwwspecial/peptideatlas/repository/Header.php`;
  }else{
    $notpublic_buffer= `cat /net/dblocal/wwwspecial/peptideatlas/repository/Header_unrelease.php`; 
  }
 
}

#######################################################################
#  finalizePhp -- write root node end tag, and check well-formedness
#######################################################################
sub finalizePhp
{
  my %args = @_;
  my $public = $args{public};;
  if($public){
  $buffer .= qq~
    </tbody></table>
		</form>

		<br/><br/><br/><br/>

		<script language="javascript" type="text/javascript">
		//<![CDATA[	
			var table_Props =		{					
							col_2: "select",
							display_all_text: " [ Show all ] ",
							sort_select: true,
							col_width: ["250px","200px"],//prevents column width variations
							alternate_rows: true,
																						rows_counter: true,
							rows_counter_text: "Matched rows: ",
							btn_reset: true,
							bnt_reset_text: "Clear all"
						};
			setFilterGrid( "table1",table_Props );
		//]]>

		</script>


		</body></html>

		<!-- ------------------------ End of main content ------------------------ -->
		<!--footer-->

				</td></tr>
				</table>

				<td height="600" width="1"></td>
				<tr>

					<td colspan="2" bgcolor="#827975" height="3">
						<center><span class="copyright">© 2009, Institute for Systems Biology, All Rights Reserved</span>
						<br></center>
					</td>
					<td height="1" width="1">
						<img src="/images/clear.gif" border="0" height="1" width="1">
					</td>
				</tr>

			</tr>

			<tr height="5">
				<td colspan="2" bgcolor="#294a93" height="5">
					<img src="/images/clear.gif" border="0" height="5" width="1">
				</td>
				<td height="5" width="1">
					<img src="/images/clear.gif" border="0" height="1" width="1">
				</td>

			</tr>

			</table>
			<!-- End Main page table -->
				
						<script type="text/javascript">
		var gaJsHost = (("https:" == document.location.protocol) ? "https://ssl." : "http://www.");
		document.write(unescape("%3Cscript src='" + gaJsHost + "google-analytics.com/ga.js' type='text/javascript'%3E%3C/script%3E"));
		</script>
		<script type="text/javascript">
		var pageTracker = _gat._getTracker("UA-2217548-2");
		pageTracker._setDomainName("none");
		pageTracker._setAllowLinker(true);
		pageTracker._initData();
		pageTracker._trackPageview();
		</script>


		</body>
    </html>
   ~;
  }else{
     $notpublic_buffer .= qq~
       </tbody></table>
       <br/><br/><br/><br/></body></html>
     ~;
  }

}

#######################################################################
# get_data_url -- given sample_accession, search dir, and data_type, 
# gets the url of the gzipped tar file.  
#
# Looks for latest gzipped archive file_pattern file in $repository_path
#     If the file is found, get it's complementary properties timstamp file
#         and compare contents to database properties
#         If the properties timstamp file is lagging behind database properties
#             create new properties file and new gzipped archive
#             return that url
#         Else return the url for the existing (already up-to-date) gzipped archive
#     Else there's no versioned gzipped archive file_pattern file yet, so create
#         and create the complementary properties file
# Else file pattern doesn't exist, so return null.  This can happen, for example
# when the orginal vendor specific spectra are missing.
#
# @param sample_accession
# @param data_dir
# @param properties_ref -- reference to hash of properties from database
# @param file_suffix  to use as archive file suffix (for example "searched")
# @param file_pattern to use for inclusion in archive file 
#    (for example "mzXML")
#    (for example "inter ASAP tgz html sequest")
# @return data_url of compressed archive file; returns nothing if
#    if files with file_pattern don't exist.  (for example, happens
#    when original vendor specific spectra are missing)
#######################################################################
sub get_data_url
{
    my %args = @_;

    my $sample_accession = $args{sample_accession} || die "need sample_accession";

    my $organism  = $args{organism} || die "need organism";

    my $data_dir = $args{data_dir} || die "need data directory for $sample_accession";

    my $properties_ref = $args{properties_ref} or die "need properties_ref";
    
    my %properties = %{$properties_ref};

    my $file_suffix = $args{file_suffix} || 
        error_message ( 
            message => "need file_suffix for $sample_accession, looking in $data_dir ($!)");

    my $file_pattern = $args{file_pattern} || die "need file_pattern for list($!)";

    my $data_url;
    #### make a file containing files with pattern: ####
    my $fileWithFileNames = "tt.txt"; 

    my $pat = $sample_accession . ".*" . $file_pattern;

    ## files are in $repository_path, but be careful not to include $repository_path/TESTFILES
   # my $cmd = "find $repository_path/ -maxdepth 1 -name \"$pat\"  -print > $fileWithFileNames";
    
    ## where each file in $fileWithFileNames is given as the absolute path to the file
    #print "$cmd\n" if ($VERBOSE);
    #system $cmd;
    `rm tt.txt`;
    if ( -e "$repository_path\/$sample_accession".'_tranche.hash')
    {
       `grep \'$pat\' "$repository_path\/$sample_accession\_tranche.hash" > $fileWithFileNames`; 
       print "grep \'$pat\' \"$repository_path\/$sample_accession\_tranche.hash\" > $fileWithFileNames\n"        if ($VERBOSE);  
    } 

    my $latestFile = "";
    ## if filelist is not empty
    if (-s $fileWithFileNames)
    {
        ## [case: files matching pattern exist (could be versioned and un-versioned)]
        $latestFile = getLatestFileName( fileWithFileNames => $fileWithFileNames ); 
        ## this is absolute path
    }
    if ($latestFile) {
        ## [case: versioned files exist, and we found the latest]
        ## compare properties timestamp file to database properties
        ## and return true if it is current, or false if it is not
        my $fileIsCurrent = isFileCurrent( 
                              file => $latestFile, 
                              properties_ref => $properties_ref);
        if ($fileIsCurrent){
            ## [case: versioned file exists and is in sync with database info]
        } else{
            ## [case: versioned file is lagging behind database info]

            ## create new properties file and new gzipped archive, 
            ## return absolute path (= $repository_path/file)
            ## for newly created gzipped archive
            ## AND update the database information
	          ## Ning_added, remove all other versions of mzXML.tar.gz
	          #my $rm_pat = "$repository_path/$pat";
	          #system "rm -f $rm_pat";

            $latestFile = makeNewArchiveAndProperties(
                sample_accession => $sample_accession,
                organism => $organism,
                data_dir => $data_dir,
                file_suffix => $file_suffix,
                file_pattern => $file_pattern,
                );

            
        }

    } else{
        ## [case: no versioned file exists yet]
           
        ## create new properties file and new gzipped archive
        ## return url for newly created gzipped archive
        ## AND update the database information
        ## create new properties file and new gzipped archive,
        ## return absolute path (= $repository_path/file)
        ## for newly created gzipped archive
        ## AND update the database information
      $latestFile = makeNewArchiveAndProperties(
            sample_accession => $sample_accession,
            organism => $organism,
            data_dir => $data_dir,
            file_suffix => $file_suffix,
            file_pattern => $file_pattern,
            );

    }


    #$data_url = convertAbsolutePathToURL( file_path => $latestFile );

#   ## [case: files matching pattern do not exist.  this is expected behavior
#   ##        for missing orginal data files, for example]
#   error_message ( 
#       message => "could not find $file_pattern files in $data_dir",
#   );
#   $data_url = "";

    #$data_url = `grep \'$pat\' "$repository_path\/$sample_accession\_tranche.hash" | cut -f2`; 
    $latestFile =~ /.*\s+?(.*)/;
    $latestFile = $1;
    return $latestFile;
}

#######################################################################
# error_message
#######################################################################
sub error_message
{
    my %args = @_;

    my $message = $args{message} || die "need message ($!)";

    open(OUTFILE,">>$errorfile") or die "cannot write to $errorfile ($!)";

    print OUTFILE "$message\n";

    close(OUTFILE) or die "cannot close $errorfile ($!)";
}

#######################################################################
# get_orig_data_type -- given data_dir, gets orig data type
# @param data_dir - absolute path to data
# @return data_type (e.g. .RAW, .raw, or dtapack)
#######################################################################
sub get_orig_data_type
{
    my %args = @_;

    my $data_dir = $args{data_dir} ||
        die "need data directory ($!)";

    my $orig_data_type="";

    

    ## check for .RAW files:
    unless ($orig_data_type)
    {
        my @files = `find $data_dir -maxdepth 1 -name \"*.RAW\"  -print`;

        if ( $#files > -1)
        {
            $orig_data_type = "RAW";
        }
    }


    ## check for .raw files:
    unless ($orig_data_type)
    {
        my @files = `find $data_dir -maxdepth 1 -name \'*.raw\' -print`;

        if ( $#files > -1)
        {
            $orig_data_type = "raw";
        }
    }


    ## check for dta.tar files:
    unless ($orig_data_type)
    {
        my @files = `find $data_dir -maxdepth 1 -name \'*_dta.tar\' -print`;

        if ( $#files > -1)
        {
            $orig_data_type = "dtapack";
        }
    }

    return $orig_data_type;
}


#######################################################################
# get_spectra_location -- gets the data directory holding spectra for
# the sample
# @param sample_id
# @return absolute path to data holding the spectra
#######################################################################
sub get_spectra_location
{
    my %args = @_;

    my $sample_id = $args{sample_id} or die "need sample_id";

    my $sql = qq~
        SELECT distinct ASB.data_location 
        FROM $TBAT_ATLAS_SEARCH_BATCH ASB
        JOIN $TBAT_ATLAS_BUILD_SEARCH_BATCH ABSB 
        ON (ABSB.atlas_search_batch_id = ASB.atlas_search_batch_id)
        WHERE ABSB.sample_id = '$sample_id'
        AND ABSB.record_status != 'D'
        AND ASB.record_status != 'D'
    ~;

    my ($data_path) = $sbeams->selectOneColumn($sql) or 
        die "Could not find atlas_search_batch for sample_id = $sample_id";

    ## if $data_path has /data3/sbeams/archive/, remove that
    $data_path =~ s/^(\/data3\/sbeams\/archive\/)(.+)$/$2/gi;
        
    ## if $data_path starts with a /, remove that
    $data_path =~ s/^(\/)(.+)$/$2/gi;

    $data_path = "$sbeams_data_path/$data_path";

    ## make sure it exists:
    unless (-d $data_path)
    {
       die "$data_path doesn't exist";

    }

    return $data_path;
}


#######################################################################
# get_spectra_properties_info_from_db -- get spectra info
# @param sample_id
# @return complex hash of format:
#     $spectra_info{$sample_id}->{conversion_software_name}
#     $spectra_info{$sample_id}->{conversion_software_version}
#     $spectra_info{$sample_id}->{mzXML_schema}
#######################################################################
sub get_spectra_properties_info_from_db
{
    my %args = @_;

    my $sample_id = $args{sample_id} or die "need sample_id";

    my %spectra_info;

    my $sql = qq~
        SELECT conversion_software_name, conversion_software_version,
        mzXML_schema, spectra_description_set_id
        FROM $TBAT_SPECTRA_DESCRIPTION_SET
        WHERE sample_id = '$sample_id'
        AND record_status != 'D'
    ~;

    my @rows = $sbeams->selectSeveralColumns($sql) or 
        die "Couldn't find spectra_description_set for sample_id = $sample_id";

    ## store query results in $sample_info
    foreach my $row (@rows) 
    {
        my ($c_s_n, $c_s_v, $m_s, $s_d_s_i) = @{$row};

        $spectra_info{conversion_software_name} = $c_s_n;

        $spectra_info{conversion_software_version} = $c_s_v;

        $spectra_info{mzXML_schema} = $m_s;
     
        $spectra_info{spectra_description_set_id} = $m_s;
    }

    return %spectra_info;
}


#######################################################################
# get_notpublic_sample_info -- get ExpTag, CellType, and DataContributors
#    for the "not public" datasets
#######################################################################
sub get_notpublic_sample_info
{
    my %sample_info;

    ## get sample info:
    my $sql = qq~
        SELECT S.sample_tag, S.cell_type_term, O.organism_name,
            S.data_contributors
        FROM $TBAT_SAMPLE S
        JOIN $TBPR_SEARCH_BATCH SB 
            ON (SB.search_batch_id = S.search_batch_id)
        JOIN $TBPR_BIOSEQUENCE_SET BS 
            ON (BS.biosequence_set_id = SB.biosequence_set_id)
        JOIN $TB_ORGANISM O ON (BS.organism_id = O.organism_id)
        WHERE is_public = 'N'
    ~;


    my @rows = $sbeams->selectSeveralColumns($sql) or 
        die "Couldn't find sample records ($!)";

    ## store query results in $sample_info
    foreach my $row (@rows) 
    {

        my ($sample_tag, $cell_type, $organism, $data_contributors) = @{$row};

        $data_contributors =~ s/\r/ /g;

        $data_contributors =~ s/\n/ /g;

        $sample_info{$sample_tag}->{cell_type} = $cell_type;

        $sample_info{$sample_tag}->{organism} = $organism;

        $sample_info{$sample_tag}->{data_contributors} = $data_contributors;

    }


    ## assert data structure contents:
    if ($TEST)
    {
        foreach my $row (@rows)
        {
            my ($sample_tag, $cell_type, $organism, $data_contributors) = @{$row};

            if ($sample_info{$sample_tag}->{cell_type} ne $cell_type)
            {
                warn "TEST fails for " .
                    "$sample_info{$sample_tag}->{cell_type} ($!)".
                    " ($sample_info{$sample_tag}->{cell_type} != " .
                    " $cell_type)\n";
            }

            if ($sample_info{$sample_tag}->{organism} ne $organism)
            {
                warn "TEST fails for " .
                    "$sample_info{$sample_tag}->{organism} ($!)".
                    " ($sample_info{$sample_tag}->{organism} != " .
                    " $organism)\n";
            }
        }

    } ## end TEST


    return %sample_info;

}
   
#######################################################################
# get_public_sample_info -- get relevant attributes from all public
# sample records and store it into complex hash with key=sample_accession
#######################################################################
sub get_public_sample_info
{
    my %sample_info;

    ## get sample info:
    my $sql = qq~
        SELECT S.sample_accession, S.sample_tag, S.sample_id, 
            O.organism_name, S.sample_description, S.data_contributors, 
            S.is_public, S.sample_publication_ids
        FROM $TBAT_SAMPLE S
        JOIN $TBAT_BIOSEQUENCE_SET BS ON (BS.project_id = S.project_id)
        JOIN $TB_ORGANISM O ON (BS.organism_id = O.organism_id)
        WHERE S.is_public = 'Y'
    ~;

    my @rows = $sbeams->selectSeveralColumns($sql) or 
        die "Couldn't find sample records ($!)";

    ## store query results in $sample_info
    foreach my $row (@rows) 
    {
        my ($sample_accession, $sample_tag, $sample_id, $organism, 
            $sample_description,
            $data_contributors, $is_public, $sample_publication_ids) 
            = @{$row};

        ## replace dos end of line markers (\r) and (\n) with space
        $sample_description =~ s/\r/ /g;

        $sample_description =~ s/\n/ /g;

        $data_contributors =~ s/\r/ /g;

        $data_contributors =~ s/\n/ /g;

        $sample_info{$sample_accession}->{sample_id} = $sample_id;

        $sample_info{$sample_accession}->{sample_tag} = $sample_tag;

        $sample_info{$sample_accession}->{organism} = $organism;

        $sample_info{$sample_accession}->{description} = $sample_description;

        $sample_info{$sample_accession}->{data_contributors} = $data_contributors;

        $sample_info{$sample_accession}->{is_public} = $is_public;

        $sample_info{$sample_accession}->{publication_ids} = $sample_publication_ids;

    }

    return %sample_info;
}
   
#######################################################################
# write_private_file -- writes repository_notpublic.xml file.  
#
#######################################################################
sub write_private_file
{

    ## Get sample information. Structure is: 
    ##  $samples{$sample_tag}->{cell_type} = $cell_type;
    ##  $samples{$sample_tag}->{organism} = $cell_type;
    ##  $samples{$sample_tag}->{data_contributors} = $data_contributors;
    my %samples = get_notpublic_sample_info();
    my $sample_count = scalar keys %samples;
    my $date = `date`;
   $notpublic_buffer .= qq~
        There are
        $sample_count experimental datasets not released ($date)</p><br/><table class="rep2">
        <tbody>
        <tr><th class="rep">Name </th><th class="rep">
            Organism
        </th><th class="rep">
            Data Contributors
        </th></tr>
    ~;


    ## iterate over sample_tags, writing formatted info to file:
    foreach my $sample_tag ( sort keys %samples)
    {
        my $cell_type = $samples{$sample_tag}->{cell_type};

        my $organism = $samples{$sample_tag}->{organism};

        my $data_contributors = $samples{$sample_tag}->{data_contributors};

        write_to_notpublic_file(
            sample_tag => $sample_tag,
            organism => $organism,
            data_contributors => $data_contributors,
            cell_type => $cell_type
        );

    }

}

#######################################################################
# write_to_notpublic_file -- write info to "not public" repository file
#######################################################################
sub write_to_notpublic_file
{
    my %args = @_;

    my $sample_tag = $args{'sample_tag'} || die "need sample_tag";

    my $organism = $args{'organism'} || die "need organism for $sample_tag";

    my $data_contributors; 
    if ($TEST)
    {
        $data_contributors = $args{data_contributors}; ## dev database isn't annotated
    } else
    {
        $data_contributors = $args{data_contributors};# or 
        #    die "need data_contributors for sample_tag $sample_tag";#zhi
    }

    $data_contributors =~ s/\r/ /g;

    $data_contributors =~ s/\n/ /g;


    my $cell_type = $args{'cell_type'} || "[]"; ## might not be in record

   ######## write to xml file: ########
    writeNotPublicPhpSample(
        sample_tag => $sample_tag,
        organism => $organism,
        cell_type => $cell_type,
        data_contributors => $data_contributors,
    );

}


#######################################################################
# writeNotPublicPhpSample -- write not public sample info to xml file.  
#
# Format is:
# <sample>
#   <sample_tag>A8_IP</sample_tag>
#   <organism>Human</organism>
#   <cell_type>Human Erythroleukemia K562 cell line</cell_type>
# </sample>
#
#######################################################################
sub writeNotPublicPhpSample
{
    my %args = @_;

    ## read arguments:
    my $sample_tag = $args{'sample_tag'} || die "need sample tag ($!)";

    my $cell_type = $args{'cell_type'} || die "need cell_type ($!)";

    my $organism = $args{'organism'} || die "need organism ($!)";

    my $data_contributors; 
    if ($TEST)
    {
        $data_contributors = $args{data_contributors}; ## dev database isn't annotated
    } else
    {
       $data_contributors = $args{data_contributors} #zhi or die "need data_contributors";
    }
    $notpublic_buffer .= qq~
         <tr><td class="rep">$sample_tag</td>
         <td class="rep">$organism</td>
         <td class="rep">$data_contributors</td>
         </tr>
    ~;

}

#######################################################################
# getLatestFileName - get the filename with the most recent timestamp
# (where filenames are in in file).  It will return null if it didn't
# find a versioned file in the list.
# @param fileWithFileNames
# @return latestFile - file with most recent timestamp, or null if
# no versioned files were in list
#######################################################################
sub getLatestFileName
{
    my %args = @_;

    my $infile = $args{fileWithFileNames} or die "need fileWithFileNames";

    my $latestFile;

    ##$timestamp_pattern = "%Y%m%d%m%M";
    ## example: 200605050544
    my $latestTimeStamp = 0;

    open(INFILE, "<$infile") or die "cannot open $infile for reading ($!)";

    while (my $fileName = <INFILE>)
    {
        chomp($fileName);

        if ( $fileName =~ /^(.+)(\d{12})(.+)$/ )
        {
            my $timestamp = $2;
            if ($timestamp > $latestTimeStamp)
            {
                $latestTimeStamp = $timestamp;
                $latestFile = $fileName;
            }
        }
        elsif( $fileName =~ /sequest\.params/ || $fileName =~ /README/ )
        {
          $latestFile = $fileName;
        }

    }

    close(INFILE) or die "Cannot close $infile";

    return $latestFile;
}
#######################################################################
# getFileSize -- get file size in units of MB
#
# @param file
#######################################################################
sub getFileSize
{
    my %args = @_;

    my $path = $args{file};
    my $accession = $args{accession};
    my $url   = $args{url};
    my $file;
    my $file_size;

    #get file size from README
    if(! $url) {
    my $readme = $accession;
    $readme =~ s/\_.*//;
    $readme .= "_README";
    $file_size = `grep $accession $repository_path/$readme`;
    if($file_size){
      if($file_size =~/.*\s+(\d+)\s+.*/){
        $file_size = $1;
        if($file_size >= 1000000000){
          $file_size = sprintf("%.3f", $file_size/1000000000);
          $file_size .= " GB";
        }elsif($file_size < 1000000000 and $file_size >= 1000000){
          $file_size = sprintf("%.3f", $file_size/1000000);
          $file_size .= " MB";
        }elsif ($file_size < 1000000 and $file_size >= 1000){
          $file_size = sprintf("%.3f", $file_size/1000);
          $file_size .= " KB";
        }

      }else{
        $file_size = '';
      }
     }
    }else{

       if($url =~ /data-downloader/){
          $url =~ s/data-downloader.jsp\?fileName/dataset.jsp\?i/;
          $url =~ s/http/https/;
       }else{
          $url =~ s/\+/%2B/g;
          $url = "https://proteomecommons.org/dataset.jsp?i=$url";
       }
       my $request = new HTTP::Request('GET', $url);
       my $response = $ua->request($request);
       my $content = $response->content();
       $content =~ /\D+([\d\.]+\s+(MB|GB|bytes|KB)).*/;
       print "$url\n";
       $file_size = $1;
    }
    return $file_size;
}


#######################################################################
# isFileCurrent -- determine if file is current from information
#     in database properties and information in timestamp text file.
#     Note: the file version is the version present in the repository 
#     archive flat file area, while the database version is the version 
#     present in the sbeams archive flatfile area
# @param file - fileName of latest versioned file
# @param properties_ref - reference to hash map holding 
#  properties stored in database to be compared with properties
#  of the versioned file
# @return true for is current, and false for lagging behind database
#######################################################################
sub isFileCurrent
{
    my %args = @_;

    my $file = $args{file} or die "need file";

    my $properties_ref = $args{properties_ref} or die "need properties_ref";

    my %propertiesInDatabase = %{$properties_ref};

    ## if file is as current as database, this becomes true:
    my $fileIsCurrent = 0; ## false

    my $propertiesFileName = getPropertiesFileName(
        archiveFileName => $file
    );

    my %propertiesInFile = getPropertiesInFile( 
        propertiesFileName => $propertiesFileName 
    );
    ## comparator for mzXML
    if ( $propertiesInDatabase{mzXML_schema})
    {
        $fileIsCurrent = mzXML_comparator( 
            propertiesInDatabase_ref => \%propertiesInDatabase,
            propertiesInFile_ref => \%propertiesInFile
        );
    }else{
      $fileIsCurrent =1;
    }
    return $fileIsCurrent;
}

#######################################################################
# getPropertiesFileName
# @param archiveFileName
# @return propertiesFileName
#######################################################################
sub getPropertiesFileName
{
    my %args = @_;

    my $archiveFileName = $args{archiveFileName} or die "need archiveFileName";

    my $propertiesFileName;

    if ($archiveFileName =~ /^(.+)(\d{12})(.+)$/ )
    {
        $propertiesFileName = "$1$2.properties";
    }
    if($propertiesFileName =~/$repository_path/)
    {
      return $propertiesFileName;
    }
    else
    {
      return "$repository_path\/$propertiesFileName";
    }
}


#######################################################################
# getPropertiesInFile -- get properties in file
# @param propertiesFileName
# @return hash of properties
#######################################################################
sub getPropertiesInFile
{
    my %args = @_;

    my $infile = $args{propertiesFileName} or die 
        "need propertiesFileName";

    my %propertiesHash;

    open(INFILE, "<$infile") or die "cannot open $infile for reading ($!)";

    while (my $line = <INFILE>)
    {
        chomp($line);

        if ($line=~ /^(.+)(=)(.+)$/ )
        {
            $propertiesHash{$1} = $3;
        }
       
    }

    close(INFILE) or die "Cannot close $infile";

    return %propertiesHash;
}


#######################################################################
# writePropertiesFile -- write properties to file
# @param versioned_properties_filename
# @param properties_hash_ref - reference to  hash of properties
#######################################################################
sub writePropertiesFile
{
    my %args = @_;

    my $outfile = $args{versioned_properties_filename} or die 
        "need versioned_properties_filename";

    my $properties_hash_ref = $args{properties_hash_ref} or die
        "need properties_hash_ref";

    my %properties_hash = %{$properties_hash_ref};

    open(OUTFILE, ">$outfile") or die "cannot open $outfile for writing";

    foreach my $key ( keys %properties_hash )
    {
        my $value = $properties_hash{$key};

        print OUTFILE "$key=$value\n";
    }

    close(OUTFILE) or die "Cannot close $outfile";
}


#######################################################################
# mzXML_comparator
# @param $propertiesInDatabase_ref
# @param $propertiesInFile_ref 
# @return 1 if file is current with database, 0 if file is lagging database
#######################################################################
sub mzXML_comparator
{
    my %args = @_;

    my $propertiesInDatabase_ref = $args{propertiesInDatabase_ref} or
        die "need propertiesInDatabase_ref";

    my $propertiesInFile_ref = $args{propertiesInFile_ref} or
        die "need propertiesInFile_ref";

    my %propertiesInDatabase = %{$propertiesInDatabase_ref};

    my %propertiesInFile = %{$propertiesInFile_ref};

    my $fileIsCurrent = 0; ## false

    my $fileIsCurrent_software = 0; ## false

    my $fileIsCurrent_schema = 0; ## false

    my $check_software_version="no";

    my $check_mzXML_schema_version="yes";


    ## spectra if the properties hash holds: mzXML_schema, 
    ## conversion_software_version, or conversion_software_name
        
    if ($check_software_version eq "yes")
    {
        ## compare conversion_software_version for conversion_software_name
        ## ( for now, give up if the conversion_software_name is different,
        ## someday, will need a list of preference when more than one exists)

        if ($propertiesInFile{conversion_software_name} eq 
        $propertiesInDatabase{conversion_software_name})
        {
            my $file_version = $propertiesInFile{conversion_software_version};

            my $db_version = $propertiesInDatabase{conversion_software_version};

            my ($f1, $f2, $f3, $d1, $d2, $d3);

            my $two_decimal_pattern = '^(\d+)\.(\d+)\.(\d+)$';
            my $one_decimal_pattern = '^(\d+)\.(\d+)$';

            if ($file_version =~ /$one_decimal_pattern/)
            {
                $f1 = $1;
                $f2 = $2;
                $db_version =~ /$one_decimal_pattern/;
                $d1 = $1;
                $d2 = $2;
            } elsif ($file_version =~ /$two_decimal_pattern/)
            {
                $f1 = $1;
                $f2 = $2;
                $f3 = $3;
                $db_version =~ /$two_decimal_pattern/;
                $d1 = $1;
                $d2 = $2;
                $d3 = $3;
                if ( ($f1 >= $d1) && ($f2 >= $d2) && ($f3 >= $d3) )
                {
                    $fileIsCurrent_software = 1; ## true
                }
            }
        }
    } ##end check software version


    ## check schema version
    if ($check_mzXML_schema_version eq "yes" )
    {
        ## examples: MsXML, mzXML_2.0, mzXML_2.1, mzXML_1.1.1

        my $schema_pattern = '^(.+)_(.+)$';

        my $file_version = $propertiesInFile{mzXML_schema};

        my $db_version = $propertiesInDatabase{mzXML_schema};
        
        if ($file_version =~ /$schema_pattern/)
        {
            $file_version = $2;
        } else
        {
            $file_version = -1;
        }

        if ($db_version =~ /$schema_pattern/)
        {
            $db_version = $2;
        } else
        {
            $db_version = -1;
        }

        ## becomes true when file_version is >= db_version.   
        ## file_version should never be > than db_version though, I think...
        $fileIsCurrent_schema = ($file_version >= $db_version) ? 1 : 0;

    } ## end check schema version

    $fileIsCurrent = ($fileIsCurrent_software || $fileIsCurrent_schema) ? 1 : 0;

    return $fileIsCurrent;
}

#######################################################################
# convertURLToAbsolutePath  -- convert url to absolute file path 
# @url - URL for file
# @return path  - absolute path to file
#######################################################################
sub convertURLToAbsolutePath
{
    my %args = @_;

    my $url = $args{url} or die "need url";

    my $file_path;

    my $file_name = "";

    if ($url =~ /^(http:)(.*)\/(.+\.tar\.gz)$/ )
    {
        $file_name = $3;
        $file_path = $repository_path . "/" . $file_name;
    }

    ## if this is not a gzipped tar file:
    if ($file_name eq "")
    {
        if ($url =~ /^(http:)(.*)\/(.*)$/ )
        {
            $file_name = $3;
            $file_path = $repository_path . "/" . $file_name;
        }
    }

    return $file_path;
} 

#######################################################################
# convertURLToFileName  -- convert url to file name
# @url - URL for file
# @return filename  - filename within url
#######################################################################
sub convertURLToFileName
{
    my %args = @_;

    my $url = $args{url} or die "need url";

    my $file_name = "";

    if ($url =~ /^(http:)(.*)\/(.+\.tar\.gz)$/ )
    {
        $file_name = $3;
    }

    return $file_name;
} 

#######################################################################
# deriveFileContentFromName -- derive the file content from the file
# name.  this is used to fill out an item in the README file
# @param filename
# @param brief summary of file content
#######################################################################
sub deriveFileContentFromName
{
    my %args = @_;

    my $content;

    my $filename = $args{filename} or die "need filename";

    if ($filename =~ /^(.*)mzXML(.*)/ )
    {
        $content = "spectra in .mzXML format";
    }

    unless ($content)
    {
        if ( ($filename =~ /^(.*)(\.RAW)(.*)/ ) ||
        ($filename =~ /^(.*)(\.raw)(.*)/ ) ) 
        {
            $content = "spectra in " . $2 . " format";
        }
    }

    unless ($content)
    {
        if ( ($filename =~ /^(.*)searched(.*)/ ) )
        {
            $content = "search/analysis results";
        }
    }

    unless ($content)
    {
        if ( ($filename =~ /^(.*)prot(.*)/ ) )
        {
            $content = "ProteinProphet files";
        }
    }

    unless ($content)
    {
        if ( ($filename =~ /^(.*)qualscore(.*)/ ) )
        {
            $content = "Qualscore list";
        }
    }
 
    return $content;
}

#######################################################################
#makeNewArchiveAndProperties -- create new versioned gzipped archive 
# and properties file; move it to $repository_path; update the database;
# and return the absolute path of the versioned gzipped archive file
# NOTE: some specialization for handling mzXML, or search_results
# happens here.  If adding a new versioned file resource, can add
# code here to handle it...
#
# @param sample_accession
# @param data_dir -- absolute path to relevant data in SBEAMS flatfile area
# @param file_suffix -- suffix in the to be created file name.
# [final file name: $sample_accession_$file_suffix_timestamp.tar.gz]
# @param file_pattern -- files of this/these patterns will be included
#     in new versioned gzipped archive
# @param prefix -- a prefix used only for sequest.params name
# @return absolute path of new versioned gzipped archive file
#######################################################################
sub makeNewArchiveAndProperties
{
    my %args = @_;

    my $sample_accession = $args{sample_accession} or die 
        "need sample_accession";
    my $organism  = $args{organism} or die "need organism";

    my $data_dir = $args{data_dir} or die "need data_dir";

    my $file_suffix = $args{file_suffix} or die "need file_suffix";
  
    my $file_pattern = $args{file_pattern} or die "need file_pattern";

    my $prefix = $args{prefix};

    my $versioned_compressed_archive_file_path;

    #######  create new versioned gzipped archive and properties file  #######

    ## get a local (relative) filename to use for the .tar file: 
    my $versioned_compressed_archive_filename = 
        get_versioned_compressed_archive_filename(
        sample_accession => $sample_accession,
        file_suffix => $file_suffix,
    );

    ## derive a local (relative) properties file name from that file name
    my $versioned_properties_filename = $versioned_compressed_archive_filename;

    $versioned_properties_filename =~ s/\.tar\.gz/\.properties/;

    print "making $versioned_compressed_archive_filename may take awhile, patience...\n";

    ## get pwd, chdir to orig_data_dir, tar up files, gzip 'em, move 'em
    my $progwd = `pwd`;

    chdir $data_dir || die "cannot chdir to $data_dir ($!)";
    print "chdir $data_dir\n" if ($VERBOSE);
  
    #### make a file containing files with pattern: ####
    my $filelist = "$repository_path/tt.txt";
    my $cmd = "rm -f $filelist";
    print "$cmd\n" if ($VERBOSE);
    system $cmd;
    my $pat = "*$file_pattern";

    ## if file_pattern is 'inter* *ASAP* *.tgz *.html sequest.params', we'll
    ## need separate finds
    my @pats = split(" ", $pat);
    $cmd = "find . -maxdepth 1 -name \'$pats[0]\' -print > $filelist";
    print "$cmd\n" if ($VERBOSE);
    system $cmd;
    for (my $i=1; $i <= $#pats; $i++)
    {
        $cmd = "find . -maxdepth 1 -name \'$pats[$i]\' -print >> $filelist";
        print "$cmd\n" if ($VERBOSE);
        system $cmd;
    }
    ## if filelist is empty, report error message, and set final file to null: 
    if (-z $filelist)
    {
        error_message ( 
            message => "could not find $file_pattern files in $data_dir",
        );

        $versioned_compressed_archive_file_path = "";

    } else{
        my %properties_hash;

        ## if this is an mzXML file, get it's properties
        if ( $file_suffix eq "mzXML" )
        {
            ## write a poperties file with the mzXML characteristics
            my $mzXMLFile = getAFileInFile( fileWithFileNames => $filelist);

            my $spectrum_parser = new SpectraDescriptionSetParametersParser();

            $spectrum_parser->setSpectrumXML_file($mzXMLFile);

            $spectrum_parser->parse();

            my $mzXML_schema = $spectrum_parser->getSpectrumXML_schema();
        
            my $conversion_software_name = $spectrum_parser->getConversion_software_name();

            my $conversion_software_version = $spectrum_parser->getConversion_software_version();

            %properties_hash = ( mzXML_schema => $mzXML_schema,
                conversion_software_name => $conversion_software_name,
                conversion_software_version => $conversion_software_version);

        } elsif ( ($file_suffix =~ /^Search(.*)/) || ($file_suffix =~ /^prot_(.*)/) )
        {
            my $results_parser = new SearchResultsParametersParser();

            $results_parser->setSearch_batch_directory($data_dir);

            $results_parser->parse();

            my $TPP_version = $results_parser->getTPP_version();

            %properties_hash = ( TPP_version => $TPP_version );
        }
        writePropertiesFile(
            versioned_properties_filename => "$repository_path/$versioned_properties_filename",
            properties_hash_ref => \%properties_hash);

        ## get archive filename from $versioned_compressed_archive_filename
        my $versioned_archive_filename = $versioned_compressed_archive_filename;
        $versioned_archive_filename =~ s/\.gz//;

        ## make tar file
        #my $cmd = "tar -cf $versioned_archive_filename --files-from=$filelist";
        #print "$cmd\n" if ($VERBOSE);
        #system $cmd;
    
        ## compress the tar file:
        #my $cmd = "gzip $versioned_archive_filename";
        #print "$cmd\n" if ($VERBOSE);
        #system $cmd;

        ## move them to $repository_path/  
        #$cmd = "mv $versioned_compressed_archive_filename $repository_path/";
        my $versioned_compressed_archive_filepath = $versioned_compressed_archive_filename;
         $versioned_compressed_archive_filepath  =~ s/.tar.gz//;
        `mkdir $repository_path/$versioned_compressed_archive_filepath`; 
        $cmd = "cp \`cat $filelist\` $repository_path/$versioned_compressed_archive_filepath";
        print "$cmd\n";
        system $cmd;

        #$cmd = "mv $versioned_properties_filename $repository_path/";
        #print "$cmd\n" if ($VERBOSE);

        my $check_path1 = $repository_path . "/" . $versioned_compressed_archive_filepath;

        my $check_path2 = $repository_path . "/" . $versioned_properties_filename;

        ## update the database, but make sure the move completed first:
        if ( (-d $check_path1 ) && ( -e $check_path2 ) )
        {
            if (exists $properties_hash{mzXML_schema})
            {
                updateDatabaseSpectrumProperties ( 
                    properties_hash_ref => \%properties_hash );

            } elsif (exists $properties_hash{TPP_version})
            {
                ## don't update database.  we don't offer any search results
                ## that haven't already been loaded
                
                ## make a copy of sequest.params file though.
                my $timestamp;
                if ($versioned_properties_filename =~ /^(.*)\_(.*)(\.tar\.gz)$/ )
                {
                    $timestamp = $2;
                }

                if ( $prefix )
                {
                    ## if sequest.params exists, copy it over
                    if (-e "sequest.params")
                    {
                        my $new_file_name = "$repository_path/$prefix" . "_sequest.params";
                        $cmd = "cp sequest.params $new_file_name";
                        print "$cmd\n" if ($VERBOSE);
                        system $cmd;
                    }
                    ## if qualscore file exists, copy it over
                    if (-e "qualscore_results")
                    {
                        my $new_file_name = "$repository_path/$prefix" . "_qualscore_results";
                        $cmd = "cp qualscore_results $new_file_name";
                        print "$cmd\n" if ($VERBOSE);
                        system $cmd;
                    }
                }
            }
        }

        ####  return the absolute path of the versioned gzipped archive file  ####
        $versioned_compressed_archive_file_path = 
            "$repository_path/$versioned_compressed_archive_filename";

    }
    my $title;
    if(scalar @pats ==1)
    {
      $title =  "PeptideAtlas repository $sample_accession $file_pattern";
    }
    else
    {
      if($pat =~ /inter\*prot\.x\?\?/)
      {
        $title =  "PeptideAtlas repository $sample_accession ProteinProphet_file";
      }
      else
      {
        $title =  "PeptideAtlas repository $sample_accession Search_Results";
      }
    }

    if($versioned_compressed_archive_filename =~/\.tar\.gz/)
    {
       my $samplelocation = "$repository_path/$versioned_compressed_archive_filename";
       my $hash = upload2tranche(sample_location => "$samplelocation",
                                  organism => $organism,
                                 );

       chdir $progwd;
       return $hash;
   } 
   else
   {
      chdir $progwd;
      return  $versioned_compressed_archive_file_path;
   }
}
#######################################################################
# getAFileInFile - open given file which has a list of files, and
# return the name of the first file in it
# @param fileWithFileNames
# @return aFile - a file in the file which contains a list of files
#######################################################################
sub getAFileInFile
{
    my %args = @_;

    my $infile = $args{fileWithFileNames} or die "need fileWithFileNames";

    my $latestFile;

    open(INFILE, "<$infile") or die "cannot open $infile for reading ($!)";
    my $fileName='';
    foreach my $f (<INFILE>){
     chomp $f;
     if( ! -z $f){
      $fileName = $f;
      last;
     }
    }
    close(INFILE) or die "Cannot close $infile";

    return $fileName;
}



#######################################################################
# get_versioned_compressed_archive_filename --  given sample_accession and file_suffix
#    returns versioned name of compressed file archive 
# @param $sample_accession 
# @param $file_suffix (for example: mzXML)
# @return formatted versioned name for the archive file 
# (for example: PAe0000001_mzXML_200612060133.tar.gz)
#######################################################################
sub get_versioned_compressed_archive_filename
{
    my %args = @_;

    my $sample_accession = $args{sample_accession} || 
        die "need sample_accession ($!)";

    my $file_suffix = $args{file_suffix} || die "need file suffix ($!)";


    my $file = get_versioned_archive_filename(
        sample_accession => $sample_accession,
        file_suffix => $file_suffix,
    );


    my $file = $file.".gz";

    return $file;

}


#######################################################################
# get_versioned_archive_filename --  given sample_accession and file_suffix,
#    returns a versioned name of file archive
# @param $sample_accession 
# @param $file_suffix (for example: mzXML)
# @return versioned name of the file archive 
#  (e.g. PAe0000001_mzXML_200612060133.tar)
#######################################################################
sub get_versioned_archive_filename
{
    my %args = @_;

    my $sample_accession = $args{sample_accession} || 
        die "need sample_accession ($!)";

    my $file_suffix = $args{file_suffix} || die "need file suffix ($!)";

    ## special treatement for the dta tars
    if ($file_suffix eq "dta.tar")
    {
        $file_suffix = "dtapack";
    }

    my $timestamp = `date $timestamp_pattern`;

    chomp($timestamp);

    my $file = $sample_accession . "_" . $file_suffix . "_" . $timestamp . ".tar";

    return $file;

}


#######################################################################
# updateDatabaseSpectrumProperties - updates database properties with
#  info in the properties file
# @param properties_hash_ref - reference to properties hash
#######################################################################
sub updateDatabaseSpectrumProperties
{
    my %args = @_;

    my $properties_hash_ref = $args{properties_hash_ref} ||
        die "need properties_hash_ref ($!)";

    my %properties_hash;

    ## one last check that properties exist before updating:
    if ( ( exists $properties_hash{mzXML_schema} ) &&
    (exists $properties_hash{conversion_software_name} ) &&
    (exists $properties_hash{conversion_software_version} ))
    {
        ## UPDATE spectra_description_set
        my %rowdata = (   ##   peptide_instance    table attributes
            mzXML_schema => $properties_hash{mzXML_schema},
            conversion_software_name => $properties_hash{conversion_software_name},
            conversion_software_version => $properties_hash{conversion_software_version},
        );

        my $success = $sbeams->updateOrInsertRow(
            update=>1,
            table_name=>$TBAT_SPECTRA_DESCRIPTION_SET,
            rowdata_ref=>\%rowdata,
            PK => 'spectra_description_set_id',
            PK_value => $properties_hash{spectra_description_set_id},
            verbose=>$VERBOSE,
            testonly=>$TEST,
        );

    }
}


#######################################################################
# addResourceTag  add a resource element to public xml file, include attribute
# @param attr_name
# @param attr_value
#######################################################################
sub addResourceTag
{
    my %args = @_;

    my $attr_name = $args{attr_name} or die "need attr_name";

    my $attr_value = $args{attr_value} or die "need attr_value with $attr_name";

    my $file_size = $args{file_size} || 0;

    my $asbid = $args{asbid} || "";

    ## write opening sample tag information to xml:
    ## open xml file and writer:
    $file_size = "($file_size)<nobr>" if $file_size;
    if($attr_name eq 'README'){
      $buffer .= qq~ <a onmousedown="whichButton=event.button;Mousedown(this)" href="$attr_value">README</a>~;
   }elsif($attr_name eq 'README_TRANCHE'){
       $buffer .= qq~
                <input value="$attr_value" type="hidden"/>
                </td> 
                ~;
    }else{
      $buffer .= qq~
                <a onmousedown="whichButton=event.button;Mousedown(this)" href="$attr_value">
                $attr_name</a>$file_size<br/>
                ~;
    }

}

#######################################################################
# addPublicationTag -- add a publication tag to the xml file
# @param short name for the publication
# @param url for publication
#######################################################################
sub addPublicationTag 
{
    my %args = @_;

    my $citation = $args{citation} or die "need citation";

    my $url = $args{url} or die "need url for citation: $citation";

    ## write opening sample tag information to xml:
    $rowbuffer .= qq~ <a href="$url">$citation</a><br/>~;
}


#######################################################################
# get_orig_data_url  -- get original data URL from public repository, 
#  or if doesn't exist, packs up files and moves them there, and then
#  returns url
# @param sample_id -
# @param sample_accession -
# @param spectra_data_dir -
# @param orig_data_type -
# @return URL to the archive data file
#######################################################################
sub get_orig_data_url
{
    my %args =@_;

    my $sample_id = $args{sample_id} or die "need sample_id";

    my  $organism = $args{organism} or die "need organism name";

    my $sample_accession = $args{sample_accession} or die
        "need sample_accession";

    my $data_dir = $args{spectra_data_dir} or die
        "need spectra_data_dir";

    my $orig_data_type = $args{orig_data_type} or die
        "orig_data_type";

    my $hash;
    ## does an archive file already exist in the repository?
    my $filelist = "$repository_path/tt.txt";
    `rm -f $filelist`;
    `touch $filelist`;
     my $pat = "$sample_accession.*$orig_data_type.*";
#    my $cmd = "find $repository_path/ -maxdepth 1 -name \'$pat\' -print > $filelist";
#    print "$cmd\n" if ($VERBOSE);
#    system $cmd;
    if ( -e "$repository_path\/$sample_accession".'_tranche.hash')
    {
       `grep \'$pat\' "$repository_path\/$sample_accession\_tranche.hash" > $filelist`; 
    } 

    my $versioned_compressed_archive_file_path;

    if (-s $filelist)
    { ## [case: file list is not empty]
        $versioned_compressed_archive_file_path = 
           getLatestFileName( fileWithFileNames => $filelist ); 
        $hash = $versioned_compressed_archive_file_path;
        $hash =~ /.*\s+(.*)/;
        $hash = $1;
        print "Found archive file: $versioned_compressed_archive_file_path\n"
            if ($VERBOSE);
    }

    if (-z $filelist)
    {   ## [case: file list is empty]
        ## get a local (relative) filename to use for the .tar file:
        my $versioned_compressed_archive_filename =
            get_versioned_compressed_archive_filename(
            sample_accession => $sample_accession,
            file_suffix => $orig_data_type,
        );

        ## get archive filename from $versioned_compressed_archive_filename
        my $versioned_archive_filename = $versioned_compressed_archive_filename;
        $versioned_archive_filename =~ s/\.tar\.gz//;

        ####  return the absolute path of the versioned gzipped archive file  ####
        $versioned_compressed_archive_file_path =
        "$repository_path/$versioned_archive_filename";
        my $progwd = `pwd`;
        unless (-d $versioned_compressed_archive_file_path)
        {
            ## [case: no file exists yet in repository]
        
            ## create gzipped archive
            ## AND update the database information

            ## get pwd, chdir to orig_data_dir, tar up files, gzip 'em, move 'em

            chdir $data_dir || die "cannot chdir to $data_dir ($!)";
            print "chdir $data_dir\n" if ($VERBOSE);

            #### make a file containing files with pattern: ####
            $filelist = "$repository_path/tt.txt";
            my $cmd = "rm -f $filelist";
            print "$cmd\n" if ($VERBOSE);
            system $cmd;
            my $pat = "*$orig_data_type";
            $pat = "*_dta.tar" if ($orig_data_type eq "dtapack");
            $cmd = "find . -maxdepth 1 -name \'$pat\' -print  > $filelist";
            print "$cmd\n" if ($VERBOSE);
            system $cmd;

            ## if filelist is empty, report error message, and set final file to null: 
            ## this shouldn't happen though, as only reach this point with a defined
            ## orig data type
            if (-z $filelist){
                error_message ( 
                    message => "could not find $orig_data_type files in $data_dir",
                );

                $versioned_compressed_archive_filename = "";

            } else{
                #my $tar_file_name = $versioned_archive_filename;
                ## make tar file
                #my $cmd = "tar -cf $tar_file_name --files-from=$filelist";
                #print "$cmd\n" if ($VERBOSE);
                #system $cmd;
    
                ## compress the tar file:
                #my $cmd = "gzip $tar_file_name";
                #print "$cmd\n" if ($VERBOSE);
                #system $cmd;

                ####  move them to $repository_path/  ####
                #$cmd = "mv $versioned_compressed_archive_filename $versioned_compressed_archive_file_path";
                `mkdir $versioned_compressed_archive_file_path`;
                $cmd = "cp \`cat $filelist\` $versioned_compressed_archive_file_path";
                print "$cmd\n" if ($VERBOSE);
                system $cmd;
                $hash = upload2tranche(
                    sample_location => "$versioned_compressed_archive_file_path",
                    organism => $organism);

            }
       }
       chdir $progwd;
   }
       print "$hash\n";
       #return $versioned_compressed_archive_file_path;
       return $hash;

}


#######################################################################
# get_an_sb_file_url - looks for file in public archive, and
# if not there, generates it and puts it there.
# (this is written to handle sequest.params and qualscore_results)
# @param file_name - the public archive file name to look for
# @param sb_file_name - the file name in the search batch directory
# @param search_results_dir
# @return URL for gzipped file of sequest.params file
#######################################################################
sub get_an_sb_file_url
{
    my %args =@_;

    my $file_name = $args{file_name} or die "need file_name";

    my $sb_file_name = $args{sb_file_name} or die "need sb_file_name";

    my $data_dir = $args{search_results_dir} or die
        "need search_results_dir";
    my $organism = $args{organism} or die "need organism name";
    
         
    ## does a search_batch for this atlas_search_batch_id already exist in
    ## the archive?  if not, make one:
    my $filelist = "$repository_path/tt.txt";
    `rm -f $filelist`;
    my $pat = "$file_name";
    $pat =~ /(.*)\_.*\_.*/;
    my $sample_accession = $1;
    my $progwd = `pwd`;
    if ( -e "$repository_path\/$sample_accession".'_tranche.hash')
    {
       #`rm -f $filelist`;
       `grep \'$pat\' "$repository_path\/$sample_accession\_tranche.hash" > $filelist`;
    }
    my $file_path;
    my $hash ="";
    if (-s $filelist)
    { ## [case: file list is not empty]
        my $versioned_compressed_archive_file_path =
           getLatestFileName( fileWithFileNames => $filelist );
        $hash = $versioned_compressed_archive_file_path;
        $hash =~ /.*\s+(.*)/;
        $hash = $1;
        print "Found archive file: $versioned_compressed_archive_file_path\n"
    }

    ## if filelist is empty
    if (-z $filelist)
    {
        my $file_pattern = $sb_file_name;

        ## get pwd, chdir to search_batch_dir, gzip file and move it to public archive
        my $progwd = `pwd`;
        chdir $data_dir || die "cannot chdir to $data_dir ($!)";
        
        print "chdir $data_dir\n" if ($VERBOSE);

        #### make a file containing files with pattern: ####
        my $filelist = "tt.txt";
        my $cmd = "rm -f $filelist";
        print "$cmd\n" if ($VERBOSE);
        system $cmd;
        my $pat = "$sb_file_name";
        $cmd = "find . -maxdepth 1 -name \'$pat\' -print  > $filelist";
        print "$cmd\n" if ($VERBOSE);
        system $cmd;
        ## if filelist is not empty
        unless (-z $filelist)
        {
            my $cmd = "cp $sb_file_name $repository_path/$file_name";
            print "$cmd\n" if ($VERBOSE);
            system $cmd;
            ## move it to $repository_path/
            #$cmd = "mv $file_name $repository_path/";
            #print "$cmd\n" if ($VERBOSE);
            #system $cmd;
            $hash = upload2tranche(sample_location => "$repository_path/$file_name",
                                   organism => $organism);
       }
       chdir $progwd;
    }
    my $file_url = '';
    if($hash){
      $hash =~ s/\+/\%2B/g;
      $file_url ="http://www.proteomecommons.org/data-downloader.jsp?fileName=".$hash;   
    }
    return $file_url;
 
}
#######################################################################
# upload file to tranche and return tranche key
#######################################################################
sub upload2tranche
{
    my %args =@_;


    my $organism = $args{organism} or die
        "need organism";
    my $samplelocation = $args{sample_location} or die
        "need samplelocation";

    my ($file_name,$sample_accession, $desc);
    my $file_path = $samplelocation;

    $desc = "peptideAtlas data\n";
    $desc .= "Organism: $organism\n";

    if($TrancheDescription{data_contributors}){
       $desc .="data contributors: $TrancheDescription{data_contributors}\n";
    }
    if($TrancheDescription{sample_description}){
       $desc .="sample description: $TrancheDescription{sample_description}\n";
    }
    print "$desc\n"; #zhi

    $samplelocation =~ /.*\/(.*)/;
    $file_name = $1;
    $file_name =~ /(PAe\d+)/;
    $sample_accession = $1;
    $samplelocation =~ s/\..*//;
   
    chdir $repository_path;
    mkdir "$samplelocation";
    `mv $file_path $samplelocation`;
    my $cmd = qq~
    $tranche_path/TrancheUploader.pl \\
             --user zsun \\
             --pass cscf0616 \\
             --email zsun\@systemsbiology.org \\
             --title \"PeptideAtlas repository $file_name\" \\
             --desc "$desc" \\
             --data_loc $samplelocation \\
             --organism $organism;
             ~;
    print "$cmd\n";
    system($cmd);
    my $hash = `tail -1 tranche_*.hashes`;

    if($hash)
    {
      if($hash =~ /Tearing/){
        print  "ERROR Tranche uploading fail\n";
      }else{
       `touch $sample_accession\_tranche.hash`;
       `echo "$file_name\t$hash" >> $sample_accession\_tranche.hash`;
      }
    }
    `mv tranche* log`;
	  `rm -r $samplelocation`;
    return $hash;

}
#######################################################################
# get_search_results_url - get repository URL for gzipped tar file
# of search results, check properties of database with
# timestamp properties file and pack up new files if the archive
# doesn't already exist to create the archive file;  ALSO, need to
# pack up the sequest.params file as a seperate file for each
# search result
# @param TPP_version
# @param atlas_search_batch_id
# @param sample_accession
# @param search_results_dir
# @return URL for gzipped tar file of search results
#######################################################################
sub get_search_results_url
{
    my %args =@_;

    ## search results file name will be:
    ## PAe0000001_Search_Results_<atlas_search_batch_id>_<timestamp>.properties

    my $sample_accession = $args{sample_accession} or die
        "need sample_accession";

    my $organism  = $args{organism} or die
        "need organism";

    my $data_dir = $args{search_results_dir} or die
        "need search_results_dir";

    my $TPP_version = $args{TPP_version}; ## some pepXML files don't contain TPP version

    my $atlas_search_batch_id = $args{atlas_search_batch_id} or
        die "need atlas_search_batch_id";

    my $suffix = "Search_Results_" . $atlas_search_batch_id;

    my $file_url;
        
    ## does a search_batch for this atlas_search_batch_id already exist in
    ## the archive?  if not, make one:
    my $filelist = "tt.txt";
    my $pat = "Search_Results";
    #my $cmd = "find $repository_path/ -maxdepth 1 -name \'$pat\' -print > $filelist";

    if ( -e "$repository_path\/$sample_accession".'_tranche.hash')
    {
       `grep \'$pat\' "$repository_path\/$sample_accession\_tranche.hash" > $filelist`; 
    } 
    my $file_path;

    if (-s $filelist)
    { ## [case: file list is not empty]
        $file_path = getLatestFileName( fileWithFileNames => $filelist ); 

        print "Found archive file: $file_path\n" if ($VERBOSE);
    }

    ## if filelist is empty
    if (-z $filelist)
    {
        my $file_pattern = "inter* *ASAP* *.tgz *.html sequest.params";

        my $prefix = $sample_accession . "_" . $atlas_search_batch_id;

        $file_path = makeNewArchiveAndProperties(
            sample_accession => $sample_accession,
            organism  => $organism,
            data_dir => $data_dir,
            file_suffix => $suffix,
            file_pattern => $file_pattern,
            prefix => $prefix
        );

    }
    
    $file_path =~ /.*\s+?(.*)/;
    $file_path =$1;
    $file_path =~ s/\+/\%2B/g;
    #$file_url = convertAbsolutePathToURL( file_path => $file_path );
    $file_url = "http://www.proteomecommons.org/data-downloader.jsp?fileName=".$file_path;
    return $file_url;
}


#######################################################################
# get_protein_prophet_url - get repository URL for gzipped tar file
# of search results, check properties of database with
# timestamp properties file and pack up new files if the archive
# doesn't already exist to create the archive file;  ALSO, need to
# pack up the sequest.params file as a seperate file for each
# search result
# @param TPP_version
# @param atlas_search_batch_id
# @param sample_accession
# @param search_results_dir
# @return URL for gzipped tar file of search results
#######################################################################
sub get_protein_prophet_url
{
    my %args =@_;

    ## protein_prophet file name will be:
    ## PAe0000001_prot_<atlas_search_batch_id>_<timestamp>.properties

    my $sample_accession = $args{sample_accession} or die
        "need sample_accession";

    my $organism  =$args{organism} or die "need organism";

    my $data_dir = $args{search_results_dir} or die
        "need spectra_data_dir";

    my $TPP_version = $args{TPP_version};

    my $atlas_search_batch_id = $args{atlas_search_batch_id} or
        die "need atlas_search_batch_id";

    my $suffix = "prot_" . $atlas_search_batch_id;

    my $file_url;
        
    ## does a protein prophet archive for this atlas_search_batch_id already exist in
    ## the archive?  if not, make one:
    my $filelist = "tt.txt";

    my $pat = "$sample_accession.*$suffix";
    #  my $cmd = "find $repository_path/ -maxdepth 1 -name \"$pat\">$filelist";
    if ( -e "$repository_path\/$sample_accession".'_tranche.hash')
    {
       `grep \'$pat\' "$repository_path\/$sample_accession\_tranche.hash" > $filelist`; 
    } 

    my $file_path;
    if (-s $filelist)
    { ## [case: file list is not empty]
        $file_path = getLatestFileName( fileWithFileNames => $filelist );
       print "Found archive file: $file_path\n" if ($VERBOSE);
    }

    ## if filelist is empty
    if (-z $filelist)
    {
        my $file_pattern = "inter*prot.x?? inter*prot.shtml";
        $file_path = makeNewArchiveAndProperties(
            sample_accession => $sample_accession,
            organism  => $organism,
            data_dir => $data_dir,
            file_suffix => $suffix,
            file_pattern => $file_pattern
        );

    }
#    $file_url = convertAbsolutePathToURL( file_path => $file_path );
#    return $file_url;
    $file_path =~ /.*\s+?(.*)/;
    $file_path =$1;

    $file_path =~ s/\+/\%2B/g;
   # $file_url = convertAbsolutePathToURL( file_path => $file_path );
    $file_url = "http://www.proteomecommons.org/data-downloader.jsp?fileName=".$file_path;
    return $file_url;

}


#######################################################################
# write_readme_and_get_readme_url
# @param sample_accession
# @param sample_tag
# @param organism
# @param description
# @param data_contributors
# @param array_of_file_urls_ref -- reference to array of file URLs
# @param array_of_pub_url_ref
# @param array_of_pub_cit_ref
# @param array_of_pubmed_id_ref
# @param array_of_pubmed_ids_ref 
# @return readme_url
#######################################################################
sub write_readme_and_get_readme_url
{
    my %args = @_;

    my $sample_accession = $args{sample_accession} or die
        "need sample_accession";

    my $sample_tag = $args{sample_tag} or die "need sample_tag";

    my $organism = $args{organism} or die "need organism";

    my $description = $args{description} or die "need description";

    my $data_contributors; 
    if ($TEST)
    {
        $data_contributors = $args{data_contributors}; ## dev database isn't annotated
    } else
    {
       $data_contributors = $args{data_contributors}; #zhi or die "need data_contributors";
    }

    my $array_of_file_urls_ref = $args{array_of_file_urls_ref} or
        die "need array_of_file_urls_ref";
    my @array_of_file_urls = @{$array_of_file_urls_ref};

    my $array_of_pub_url_ref = $args{array_of_pub_url_ref};
    my $array_of_pub_cit_ref = $args{array_of_pub_cit_ref};
    my $array_of_pubmed_ids_ref = $args{array_of_pubmed_ids_ref};
    my @array_of_pub_urls;
    my @array_of_pub_cits;
    my @array_of_pubmed_ids;
    if ($array_of_pub_url_ref)
    {
        @array_of_pub_urls = @{$array_of_pub_url_ref};
        @array_of_pub_cits = @{$array_of_pub_cit_ref};
        @array_of_pubmed_ids = @{$array_of_pubmed_ids_ref};
    }


    my $outfile = "$repository_path/$sample_accession" . "_README";

    my $file_name = $sample_accession . "_README";
    #my $readme_url = convertFileNameToURL( file_name => $file_name );
    my $readme_url  = "http://www.peptideatlas.org/repository/pa_public_archive/".$file_name;
    ## write to README file
    open(OUTFILE,">$outfile") or die "cannot open $outfile for writing";

    ## i:0tem 1
    my $str = "#1. Data Contributors:\n" .  "    $data_contributors\n";
    print OUTFILE "$str\n";

    ## item 2
    $str = "#2. URL link to a www resource\n";
    print OUTFILE "$str\n";

    ## item 3
    $str = "#3. Literature references and PubMed identifications:\n";
    for (my $i = 0; $i <= $#array_of_pub_urls; $i++)
    {
        $str = $str."    $array_of_pub_cits[$i]\n    PubMed ID: $array_of_pubmed_ids[$i]\n";
    }
    print OUTFILE "$str\n";

    ## item 4
    $str = sprintf("%-27s\n    %-68s\n",
        "#4. Experiment Description:",  $description);
    print OUTFILE "$str\n";

    ## item 5
    $str = "#5. Treatment Description:\n";
    print OUTFILE "$str\n";

    ## item 6
    $str = "#6. Instrument Type:\n";
    print OUTFILE "$str\n";

    ## item 7
    $str = "#7. Organism NCBI_TaxID (9606 for human):\n";
    print OUTFILE "$str\n";

    ## item 8
    $str = "#8. Bio source description (eVOC) anatomical site:\n";
    print OUTFILE "$str\n";

    ## item 9
    $str = "#9. Pathology (eVOC):\n";
    print OUTFILE "$str\n";

    ## item 10
    $str = "#10. Cell-type:\n";
    print OUTFILE "$str\n\n";
    ## File sizes:
    my $fmt = "%-40s %-10s %-32s\n";
    $str = sprintf("$fmt", "#File", "size [bytes]", "hashkey:");
    print OUTFILE "$str";
    for ( my $i = 0; $i <= $#array_of_file_urls ; $i++){
        my $size = $array_of_file_urls[$i];
        $size =~ /(.*)\_(\d*)/;
        my $file_type = $1;
        my $file_size = $2;
        my $tranche_hashfile = "$repository_path/$sample_accession"."_tranche.hash";
        if (!-e $tranche_hashfile){
            error_message( message => "file does not exist: $tranche_hashfile");
        } else{
         print "grep $file_type $tranche_hashfile\n";
            my $tmp = `grep $file_type $tranche_hashfile`;
            my ($file_name,$hash) = split(/\s+/, $tmp);
            #$str = sprintf("$fmt", $file_name, $file_size, $hash);
            if($file_size){
              print OUTFILE "$file_name\t$file_size\t$hash\n";
            }
            else{
              print OUTFILE "$file_name\t\t$hash\n";
            }
        }
    }
    close(OUTFILE) or print "cannot close $outfile ($!)";
    return $readme_url;

}

#######################################################################
#  print_hash
#
# @param hash_ref to hash to print
#######################################################################
sub print_hash
{
    my %args = @_;

    my $hr = $args{hash_ref};

    my %h = %{$hr};

    foreach my $k (keys %h)
    {
        print "key: $k   value:$h{$k}\n";
    }
}


#######################################################################
# formatSampleIDs -- format test_samples string to be usable as an
#  IN clause in an SQL statement
#
# @param sample_ids
#######################################################################
sub formatSampleIDs
{
    my %args = @_;

    my $sample_ids = $args{sample_ids};

    $sample_ids =~ s/"//g; 

    $sample_ids =~ s/'//g; 

    $sample_ids =~ s/\s+//g;

    my @t = split(",",$sample_ids);

    $sample_ids = join("','", @t);

    $sample_ids = "'" . $sample_ids . "'";

    return $sample_ids;
}


#######################################################################
# getFileSize -- get file size in units of MB
# 
# @param file
#######################################################################
sub getFileSize
{
    my %args = @_;

    my $path = $args{file};
    my $accession = $args{accession};
    my $url   = $args{url};
    my $file;
    my $file_size;
   
    #get file size from README
    my $readme = $accession;
    $readme =~ s/\_.*//;
    $readme .= "_README";
    $file_size = `grep $accession $repository_path/$readme`;
    if($file_size){
      if($file_size =~/.*\s+(\d+)\s+.*/){
        $file_size = $1;
      }else{
        $file_size = '';
      }
    }
    if(! $file_size and $url){
        
       if($url =~ /data-downloader/){
          $url =~ s/data-downloader.jsp\?fileName/dataset.jsp\?i/;
          $url =~ s/http/https/;
       }else{
          $url =~ s/\+/%2B/g;
          $url = "https://proteomecommons.org/dataset.jsp?i=$url";
       }
       my $request = new HTTP::Request('GET', $url);
       my $response = $ua->request($request);
       my $content = $response->content();
       $content =~ /\D+([\d\.]+)\s+((MB|GB|bytes|KB)).*/;
       
       $file_size = $1;
       my $unit = $2;
       if($unit =~ /MB/){
         $file_size *= 1000000;
       }elsif($unit =~ /KB/){
         $file_size *= 1000;
       }elsif($unit =~ /GB/){
         $file_size *= 1000000000;
       } 
       chomp $file_size;
    }
    return $file_size;
}
