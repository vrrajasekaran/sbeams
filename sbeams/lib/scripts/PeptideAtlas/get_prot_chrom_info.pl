#!/usr/local/bin/perl 

###############################################################################
# Program     : get_prot_chrom_info.pl
# Author      : Terry Farrah <tfarrah@systemsbiology.org>
# $Id: load_atlas_build.pl 6309 2009-11-24 18:35:39Z zsun $
#
# Description : Fetches chromosomal info on proteins in a
#               biosequence set using the Ensembl perl API and stores it
#               in a tsv file.
#
###############################################################################

use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin";
use lib "/net/db/projects/PeptideAtlas/pipeline/lib/ensembl-52/modules";
use lib "/net/db/projects/PeptideAtlas/pipeline/bin";

use PeptideFilesGenerator;

use vars qw (%OPTIONS $VERBOSE $QUIET $DEBUG $TESTONLY $PROG_NAME $USAGE);

#### Do not buffer STDOUT
$|++;

use DBI;
use Storable;
use Data::Dumper;
#use Bio::SeqIO;
use Bio::SearchIO;

### use the Ensembl perl API to access our (now local copy of) the
### Ensembl SQL database. NOTE: as of April 2010, version of API used
### in this script is obsolete.  TODO: port to latest version of API.
use Bio::EnsEMBL::DBSQL::TranscriptAdaptor;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::TopLevelAssemblyMapper;
use Bio::EnsEMBL::DBSQL::CoordSystemAdaptor;
use Bio::EnsEMBL::DBSQL::KaryotypeBandAdaptor;
use Bio::EnsEMBL::AssemblyMapper;
use Bio::EnsEMBL::Mapper;
use Bio::EnsEMBL::Mapper::Coordinate;
use ProtFeatures;

###############################################################################
# Set program name and usage banner for command line use
###############################################################################
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
Usage: $PROG_NAME [OPTIONS] key=value key=value ...
Options:
  --verbose n            Set verbosity level.  default is 0
  --quiet                Set flag to print nothing at all except errors
  --debug n              Set debug flag

  These two options are always required:
  --bss_fasta_file       Path to fasta (input) file
  --prot_coords_file     Path to protein coordinates (output) file

  One or both of these two options is required:
  --getEnsemblChromInfo  get protein chromosomal info from Ensembl
  --getSwissChromInfo    get protein chromosomal info from Swiss-Prot
  --urlSwiss             base URL for Swiss-Prot info
                           (default http://www.uniprot.org/docs)

  All of the options below are required with getEnsemblChromInfo:
  --organism_name        Name of organism like Homo_sapiens
  --organism_abbrev      Abbreviation of organism like Hs
  --mysqldbhost          Hostname of MySQL database of Ensembl tables
  --mysqldbname          Ensembl MySQL database name
  --mysqldbuser          User name to login to Ensembl MySQL host
  --mysqldbpsswd         Password for username to Ensembl MySQL host
EOU


#### Process options
unless (GetOptions(\%OPTIONS,"verbose:s","quiet","debug:s",
"organism_name:s","organism_abbrev:s","organism_id:s",
"biosequence_set_id:s", "getEnsemblChromInfo", "getSwissChromInfo",
"mysqldbpsswd:s","mysqldbuser:s","mysqldbhost:s","mysqldbname:s",
"bss_fasta_file:s", "prot_coords_file:s","urlSwiss:s",
))
{
    print "\n$USAGE\n";
    exit;
}

$VERBOSE = $OPTIONS{"verbose"} || 0;
$QUIET = $OPTIONS{"quiet"} || 0;
$DEBUG = $OPTIONS{"debug"} || 0;


main();
exit;


###############################################################################
# main
###############################################################################
sub main
{
  #### If no command to do anything, print usage
  unless ( ( $OPTIONS{'getEnsemblChromInfo'}  || $OPTIONS{'getSwissChromInfo'})
           && $OPTIONS{'prot_coords_file'} && $OPTIONS{'bss_fasta_file'})
  {
    print "\n$USAGE\n";
    return;
  }

  my $protids_href = {};
  my $prot_coords_href = {};
  my $prot_coords_file = $OPTIONS{'prot_coords_file'};
  my $urlSwiss = $OPTIONS{'urlSwiss'} || "http://www.uniprot.org/docs";

  #### Read fasta file to get protein identifiers for this BSS
  getProtIDs (
    bss_fasta_file => $OPTIONS{bss_fasta_file},
    protids_href => $protids_href,
  );

  #### If the getEnsemblChromInfo step is requested
  if ($OPTIONS{'getEnsemblChromInfo'}) {
    unless ($OPTIONS{'mysqldbname'} 
    && $OPTIONS{'mysqldbhost'} && $OPTIONS{'mysqldbuser'}
    && $OPTIONS{'mysqldbpsswd'} 
    ) {
      print "\n$USAGE\n";
      print "ERROR: Must supply mysqldbname, ".
             "mysqldbhost, mysqldbuser, and mysqldbpsswd.\n ";
      return;
    }

    my $host = $OPTIONS{'mysqldbhost'};
    my $user = $OPTIONS{'mysqldbuser'};
    my $password = $OPTIONS{'mysqldbpsswd'};
    my $dbname = $OPTIONS{'mysqldbname'};
    my $refcode = 'ensembl';

    my ($db,$transcript_adaptor);
    my ($kary_adaptor,$slice_adaptor);

    ### connect to the Ensembl database
    $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
      -host => $host,
      -user => $user,
      -pass => $password,
      -dbname => $dbname,
    );
    ### create "adaptors" to retreive various objects
    ### such as exons, transcripts, and genes.
    $transcript_adaptor = $db->get_TranscriptAdaptor();
    $kary_adaptor = $db->get_KaryotypeBandAdaptor();
    $slice_adaptor = $db->get_SliceAdaptor();

    getEnsemblChromInfo(
      db => $db, 
      transcript_adaptor => $transcript_adaptor,
      kary_adaptor => $kary_adaptor,
      slice_adaptor => $slice_adaptor,
      refcode => $refcode,
      protids_href => $protids_href,
      prot_coords_href => $prot_coords_href,
    );
  }

  #### If the getSwissChromInfo step is requested
  if ($OPTIONS{'getSwissChromInfo'}) {

    getSwissChromInfo(
      protids_href => $protids_href,
      prot_coords_href => $prot_coords_href,
      base_url =>  $urlSwiss,
    );
  }
  
  #### Write out all the protein coordinate info collected into a file.
  print "\nWriting chromosomal info to $prot_coords_file.\n";
  writeProtCoords(
    prot_coords_href => $prot_coords_href,
    prot_coords_file => $prot_coords_file,
  )
}


###############################################################################
# getProtIDs -- read protein identifiers from a fasta file into a hash
###############################################################################
sub getProtIDs
{
    my %args = @_;

    my $bss_fasta_file = $args{bss_fasta_file} || die "need bss_fasta_file";

    my $protids_href = $args{protids_href} || die "need protids_href";

    print "Reading biosequence set fasta file $bss_fasta_file\n";
    open(INFILE,"$bss_fasta_file") ||
        die("ERROR: Unable to open '$bss_fasta_file'");

    my $prot_count = 0;

    while( my $line = <INFILE> ) {
      chomp($line);
      next if ( $line !~ /^>/ );
      $line =~ /^>(\w*)\s*(.*)$/;
      my $prot_id = $1;
      my $prot_desc = $2;

      if ($prot_id) {
        $protids_href->{$prot_id} = 1;
      }
   }
}

###############################################################################
# getEnsemblChromInfo - 
###############################################################################
sub getEnsemblChromInfo
{
   my %args = @_;

   my $db = $args{db} || "";

   my $kary_adaptor = $args{kary_adaptor} || "";

   my $slice_adaptor = $args{slice_adaptor} || "";

   my $transcript_adaptor = $args{transcript_adaptor} || "";

   my $refcode = $args{refcode} || "";

   my $protids_href = $args{protids_href} || die "need protids_href";

   my $prot_coords_href = $args{prot_coords_href} ||
        die "need prot_coords_href";

   print "Getting coordinates from Ensembl.\n";

   my $prot_count = 0;

   for my $protid (keys %{$protids_href}) {
        $prot_count++;
        print "." if (($prot_count % 100) == 0);
        print "$prot_count" if (($prot_count % 1000) == 0);

	getEnsemblCoords(
  	             $protid,
                     $db,
                     $kary_adaptor,
                     $slice_adaptor,
                     $transcript_adaptor,
                     $prot_coords_href);
   }
   print "\n";
}

###############################################################################
# getSwissChromInfo - 
###############################################################################
sub getSwissChromInfo
{
    my %args = @_;

    my $protids_href = $args{protids_href} || die "need protids_href";
    my %protids = %{$protids_href};

    my $prot_coords_href = $args{prot_coords_href} ||
        die "need prot_coords_href";

    my $base_url = $args{base_url} || die "need base_url";

    print "Getting coordinates from Swiss-Prot.\nChromosome ";

    #### For each chromosome
    for my $chrom ('01','02','03','04','05','06','07','08','09','10','11',
             '12','13','14','15','16','17','18','19','20','21','22',
             'x','y',) {
      print "$chrom...";
      my $file = "humchr$chrom.txt";
      my $url = "$base_url/$file";
      my $outfile = "/tmp/$file";
      my $status = system("wget $url -O $outfile");

      open (INFILE, $outfile) || die "Can't open $outfile";
      # Throw away junk
      my $count = 0;
      while ( my $line = <INFILE>) {
        chomp;
        my ($gene, $locus, $protid ) = split(/\s+/, $line);
        my $chromosome="";
        #print "$gene $locus $protid\n";
        if ( ( defined $protid ) && ( defined $protids_href->{$protid}) ) {
          if ( defined $locus ) {
            $locus =~ /^(\w{1,2})[pqc]/;
            $chromosome = $1;
            if (! defined $chromosome) {
              $locus =~ /^(\w{1,2})$/;
	      $chromosome = $1;
            }
	    $prot_coords_href->{$protid}->{chromosome} = $chromosome;
	    $prot_coords_href->{$protid}->{locus} = $locus;
          }
          $count++;
        }
      }
      close (INFILE);
      my $status = `rm -f $outfile`;
   }
   print "\n";
}


###############################################################################
# getEnsemblCoords -- use bioperl with Ensembl database and blast results
# to map the peptide CDS coordinates to chromosomal coordinates
#
# @param $stableId
# @param $db
# @param $kary_adaptor
# @param $slice_adaptor
# @param $transcript_adaptor
# @param $prot_coords_href
###############################################################################
sub getEnsemblCoords
{
    my ($stableId, $db,
        $kary_adaptor, $slice_adaptor,
        $transcript_adaptor, $prot_coords_href)
       = @_;

    if ($stableId =~ /^ENS/ ||
            ($OPTIONS{'organism_name'} eq 'Saccharomyces_cerevisiae' && $stableId =~ /^Y/) ||
            ($OPTIONS{'organism_name'} eq 'Drosophila_melanogaster' && $stableId =~ /^FB/)) {

        #### Get the genomic coordinates for this match
        #### Given the Ensembl ID for this protein, get a transcript object.
        my $transcript =
          $transcript_adaptor->fetch_by_translation_stable_id($stableId);
        if ( !defined $transcript ) {
          print STDERR "Unable to create transcript object $stableId\n";
        } else {
	  my $transcript_stable_id = $transcript->stable_id();
	  my $tr_seq_region = $transcript->slice->seq_region_name();
	  my $tr_start = $transcript->start() || "";
	  my $tr_end   = $transcript->end() || "";
	  my $tr_strand = $transcript->strand() || "";
	  my $chr_name = $transcript->slice()->seq_region_name || "";

	  # Get chromosomal band info
	  my $transcript_slice =
	    $slice_adaptor->fetch_by_transcript_stable_id($transcript_stable_id);
	  my @band_objects =
	     $kary_adaptor->fetch_all_by_Slice ( $transcript_slice );
	  my $band_object = $band_objects[0];
	  my @bands = @{$band_object};   # all bands for this slice
	  my $band_name = "";
	  $band_name = $bands[0]->name() if (scalar @bands > 0);
	  my $locus = "$chr_name$band_name";

          if ($tr_strand == -1) { $tr_strand = '-'; }
          else { $tr_strand = '+'; }
	  
	  ### Store chromosomal info for protein.
	  $prot_coords_href->{$stableId}->{start} = $tr_start;
	  $prot_coords_href->{$stableId}->{end} = $tr_end;
	  $prot_coords_href->{$stableId}->{strand} = $tr_strand;
	  $prot_coords_href->{$stableId}->{chromosome} = $chr_name;
	  $prot_coords_href->{$stableId}->{locus} = $locus;
        }
    }
}

###############################################################################
# writeProtCoords -- store chromosomal coordinate/locus info for proteins
###############################################################################
sub writeProtCoords {
    my %args = @_;

    my $prot_coords_file = $args{prot_coords_file} ||
       die "need prot_coords_file";
    my $prot_coords_href = $args{prot_coords_href} ||
       die "need prot_coords_href";

    open(PROTCOORD,">$prot_coords_file");
    for my $stableId (sort keys %{$prot_coords_href}) {
      print PROTCOORD 
        "$stableId\t".
        "$prot_coords_href->{$stableId}->{start}\t".
        "$prot_coords_href->{$stableId}->{end}\t".
        "$prot_coords_href->{$stableId}->{strand}\t".
        "$prot_coords_href->{$stableId}->{chromosome}\t".
        "$prot_coords_href->{$stableId}->{locus}\t".
        "\n";
    }
    close(PROTCOORD);
}
