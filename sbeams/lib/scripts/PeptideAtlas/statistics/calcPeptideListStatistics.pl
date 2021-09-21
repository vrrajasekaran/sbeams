#!/usr/bin/perl

###############################################################################
# Program     : calcPeptideListStatistics.pl
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This script reads a peptide list created by
#               createPipelineInput.pl and calculates false positive rates
#               and a bunch of other stuff.
#
# SBEAMS is Copyright (C) 2000-2005 Institute for Systems Biology
# This program is governed by the terms of the GNU General Public License (GPL)
# version 2 as published by the Free Software Foundation.  It is provided
# WITHOUT ANY WARRANTY.  See the full description of GPL terms in the
# LICENSE file distributed with this software.
#
###############################################################################
use strict;
$| = 1;  #disable output buffering
use Getopt::Long;
use FindBin;
use vars qw (
             $q $sbeams $sbeamsMOD $dbh $current_contact_id $current_username
             $current_work_group_id $current_work_group_name
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG $TESTONLY
             $peptide_hash $probcol $protcol $seqcol
            );
use DB_File ;
#### Set up SBEAMS modules
use lib "$ENV{SBEAMS}/lib/perl";
use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;
use SBEAMS::PeptideAtlas;
use SBEAMS::PeptideAtlas::Settings;
use SBEAMS::PeptideAtlas::Tables;
use SBEAMS::Proteomics::Tables;
use SBEAMS::BioLink;
use SBEAMS::BioLink::Tables;
my $biolink = SBEAMS::BioLink->new();
$biolink->setSBEAMS($sbeams);
use lib( "/regis/sbeams/lib");
use FAlite;


## Globals
my $sbeams = new SBEAMS::Connection;
my $atlas = new SBEAMS::PeptideAtlas;
$atlas->setSBEAMS($sbeams);
my %OPTIONS;



###############################################################################
# Read and validate command line args
###############################################################################
my $VERSION = q[$Id$ ];
$PROG_NAME = $FindBin::Script;

my $USAGE = <<EOU;
USAGE: $PROG_NAME [OPTIONS] source_file
Options:
  --verbose n         Set verbosity level.  default is 0
  --quiet             Set flag to print nothing at all except errors
                      This masks the printing of progress information
  --debug n           Set debug level.  default is 0
  --testonly          If set, nothing is actually inserted into the database,
                      but we just go through all the motions.  Use --verbose
                      to see all the SQL statements that would occur
  --source_file       Input PAidentlist tsv file with at least 11 columns.
  --prot_file         Input PAprotIdentlist file
  --prot_summary_exp  protein identificaiton summary file 
  --prot_summary_cum  cumulative protein identificaiton summary file
  --pepmap_file       Input peptide_mapping.tsv file; needed for prot plot
  --ex_tag_list tag list separated by comma (CONTAM, DECOY and UNMAPPED excluded already) 


  --P_threshold       Use this threshold for processing instead of
                      using all peptides in the input file
  --search_batch_id   If set, only process this search_batch_id and
                      ignore others
  --fasta             fasta file to get theoretical peptide length distribution (7-50) 
 e.g.:  $PROG_NAME --verbose 2 --source YeastInputExperiments.tsv

EOU


#### If no parameters are given, print usage information
unless ($ARGV[0]){
  print "$USAGE";
  exit;
}


#### Process options
unless (GetOptions(\%OPTIONS,"verbose:s","quiet","debug:s","testonly",
  "source_file:s","pepmap_file:s",
  "P_threshold:f","search_batch_id:i","ex_tag_list:s",
  "fasta:s", "prot_summary_exp:s", "prot_summary_cum:s", "prot_file:s"
  )) {
  print "$USAGE";
  exit;
}

$VERBOSE = $OPTIONS{"verbose"} || 0;
$QUIET = $OPTIONS{"quiet"} || 0;
$DEBUG = $OPTIONS{"debug"} || 0;
$TESTONLY = $OPTIONS{"testonly"} || 0;
if ($DEBUG) {
  print "Options settings:\n";
  print "  VERBOSE = $VERBOSE\n";
  print "  QUIET = $QUIET\n";
  print "  DEBUG = $DEBUG\n";
  print "  TESTONLY = $TESTONLY\n";
}

main();
exit;


###############################################################################
# Main part of the script
###############################################################################
sub main {
  my $source_file = $OPTIONS{source_file};
  my $fasta_file = $OPTIONS{fasta};
  unless ($source_file) {
    print "$USAGE\n";
    print "ERROR: Must supply --source_file\n\n";
    return(0);
  }
  unless (-e $source_file) {
    print "ERROR: Source file '$source_file' not found\n\n";
    return(0);
  }

  unless (open(INFILE,$source_file)) {
    print "ERROR: Unable to open source file '$source_file'\n\n";
    return(0);
  }

  unless (-e $fasta_file){
    print "$USAGE\n";
    print "ERROR: Must supply --fasta\n\n";
    return(0);
  }
  my $prot_file  = $OPTIONS{prot_file} || die "need prot_file\n\n$USAGE\n";
  my $prot_summary_exp_file = $OPTIONS{prot_summary_exp} or die "need prot_summary_exp input\n\n$USAGE\n";
  my $prot_summary_cum_file = $OPTIONS{prot_summary_cum}  or die "need prot_summary_cum input\n\n$USAGE\n";
  my $pepmap_file = $OPTIONS{pepmap_file};
  my $ex_tag_list = $OPTIONS{ex_tag_list} || '';
  $ex_tag_list =~ s/,/|/g;

  my $P_threshold = $OPTIONS{P_threshold} || 0;
  my $process_search_batch_id = $OPTIONS{search_batch_id} || 0;

  my %stat =();
  my $this_search_batch_id;
  my $n_experiments = 0;
  

  my @peptides;
  my @correct_peptides;
  my @search_batch_peptides;

  my %distinct_peptides;
  my %distinct_peptides_tryptic;

  my $n_assignments;
  #### Array of search_batch_ids and a hash of all peptides by search_batch_id
  my @all_search_batch_ids;
  my %all_peptides;
  my %sample_tags;
  my %peptide_mapping;

  unlink "psbi";
  unlink "peptidehash";

  tie %all_peptides, "DB_File", "peptidehash";

  #### Hashes containing canonical protein info
  ### First, read prot info if provided
  my %canonical_hash;
  open (PROTEXP , "<$prot_summary_exp_file")  or die "cannot open $prot_summary_exp_file\n";
  while (my $line =<PROTEXP>){
    next if($line =~ /canonical/);
    my ($id, $n_canonical, $s) =split(/\t/, $line);
    $canonical_hash{$id}{exp} = $n_canonical;
  }
  open (PROTCUM , "<$prot_summary_cum_file") or die "cannot open $prot_summary_cum_file\n";
  my $pre_n_canonical =0;
  while (my $line =<PROTCUM>){
    next if($line =~ /canonical/);
    my ($id, $n_canonical, $s) =split(/\t/, $line);
    ## make sure the count is increasing or has no change 
    if ($n_canonical <= $pre_n_canonical){
      $n_canonical = $pre_n_canonical;
    }elsif( $n_canonical > $pre_n_canonical && $canonical_hash{$id}{exp} < ($n_canonical - $pre_n_canonical)){
      print "WARNING: id=$id n_canonical=$canonical_hash{$id}{exp}  n_cum_canonical=$n_canonical pre_n_cum_canonical=$pre_n_canonical\n";
      $n_canonical = $pre_n_canonical + $canonical_hash{$id}{exp};
    }
    $canonical_hash{$id}{cum} = $n_canonical;
    $pre_n_canonical = $n_canonical;
  }
    # read header and get index of biosequence_name from it
#protein_group_number,biosequence_name,probability,confidence,n_observations,n_distinct_peptides,level_name,represented_by_biosequence_name,subsumed_by_biosequence_name,estimated_ng_per_ml,abundance_uncertainty,is_covering,group_size
    open (PROTFILE, "<$prot_file"); 
    my $line = <PROTFILE>;
    chomp $line;
    my @fields = split(",", $line);
    my $search_for = 'biosequence_name';
    my ( $biosequence_name_idx ) =
        grep { $fields[$_] eq $search_for } 0..$#fields;
    if (! defined $biosequence_name_idx) {
      print STDERR "ERROR in $0: $search_for not found in header of $prot_file\n";
      return(0);
    }
    $search_for = 'level_name';
    my ( $level_name_idx ) =
        grep { $fields[$_] eq $search_for } 0..$#fields;
    if (! defined $level_name_idx) {
      print STDERR "ERROR in $0: $search_for not found in header of $prot_file\n";
      return(0);
    }

    while ($line = <PROTFILE>) {
      chomp $line;
      @fields = split(",", $line);
      if ( ($fields[$level_name_idx] eq 'canonical') &&
           ($fields[$biosequence_name_idx] !~ /UNMAPPED/i) &&
           ($fields[$biosequence_name_idx] !~ /^DECOY_/i) &&
           ($fields[$biosequence_name_idx] !~ /^CONTAM_/i)
        ) {
         if ($ex_tag_list){
            if ($fields[$biosequence_name_idx] !~ /($ex_tag_list)/){
                $stat{peptidePerProtein}{$fields[$biosequence_name_idx]} = 0;
            }
         }else{
           $stat{peptidePerProtein}{$fields[$biosequence_name_idx]} = 0;
         }
      }
    }
    close PROTFILE;


  my %included_peptides;
	# for line in peptide_mapping.tsv (lacks header)
  open(PEPMAPFILE, $pepmap_file)  or die "--pepmap_file missing or unopenable;\n";
	while (my $line = <PEPMAPFILE>) {
		chomp $line;
		# get peptide, protein
		my ($pep_acc,$unmod_pep_seq, $prot_acc,$start,$end,$pre,$fol) = split("\t", $line);
		next if (! $prot_acc);
		next if ($prot_acc =~ /(^CONTAM|^DECOY)/i);
		if ($ex_tag_list){
			 next if ($prot_acc =~ /($ex_tag_list)/);
		}
		$included_peptides{$pep_acc} = length($unmod_pep_seq);
    if (exists $stat{peptidePerProtein}{$prot_acc}){
        $stat{peptidePerProtein}{$prot_acc}++;
    }
  }
	close PEPMAPFILE;

  print "included_peptides=".  scalar keys %included_peptides ;
  print "\n";

  my $line = '';
  $seqcol = 0;
  my $origseqcol = 3;   #unmodified peptide sequence
  $probcol = 1;
  my $origprobcol = 8;   #PeptideProphet peptide probability
  $protcol = 2;
  my $origprotcol = 10;  #accession of a protein mapped to
  my $origacccol = 2;


  #### Read in all the peptides for the first experiment and get the
  #### prot info
  my @columns;
  my $n_spectra = 0;
  my $not_done = 1;
  my $cnt = 0;
  my $pep_acc='';
  my %charge_cnt = ();
  my %length_cnt = ();
  my ($pre, $fol);
  while ($not_done) {
    #### Try to read in the next line;
    if ($line = <INFILE>) {
      chomp($line);
      @columns = split(/\t/,$line);
      if(not defined $included_peptides{$columns[2]}){ 
        next;
      }
      next if ($columns[$origprobcol] < $P_threshold);

      $charge_cnt{$columns[7]}++;
      $length_cnt{length($columns[3])}++;
      $pep_acc = $columns[2];
      $pre = $columns[4];
      $fol = $columns[6];
      my  $unmodified_pepseq = $columns[$origseqcol];
      if ($pre =~ /[KR\-]/ && ($unmodified_pepseq =~ /[KR]$/ || $fol =~ /\-/) ){
        if ($unmodified_pepseq =~ /[KR]\w/){
           my $tmp = $unmodified_pepseq;
           $tmp =~ s/[KR]P//g;
           $stat{distinct_peptides_tryptic}{$unmodified_pepseq}++ if ($tmp !~ /[KR]/);
        }else{
           $stat{distinct_peptides_tryptic}{$unmodified_pepseq} =1;
        }
      } 
 
      if ($process_search_batch_id) {
				next unless ($columns[0] == $process_search_batch_id);
      }
    #### If it fails, we're done, but still process the last batch
    } else {
      $not_done = 0;
      @columns = (-998899,'xx',-1,'zz');
    }

    #### If the this search_batch_id is not known, learn from first record
    $n_spectra++;
    unless ($this_search_batch_id) {
      $this_search_batch_id = $columns[0];
      print "Processing search_batch_id=$this_search_batch_id  ";
      $n_experiments++;
    }
    #### If the search_batch_id of this peptide is not the same as the last
    #### then finish processing the last peptides of previous search_batch_id
    if ($this_search_batch_id != $columns[0]) {
      #### Store all the peptides in a hash
      my @tmp = @search_batch_peptides;
      push(@all_search_batch_ids,$this_search_batch_id);
      $all_peptides{$this_search_batch_id} = join("\n", @tmp); 
      $sample_tags{$this_search_batch_id} = 'xx';
      #### Update the summary table of incorrect values with data from
      #### this search_batch
      #### Prepare for next search_batch_id
      $this_search_batch_id = $columns[0];
      @search_batch_peptides = ();
      print "n_spectra=$n_spectra\n";
      #print "$sample_tag n_spectra=$n_spectra n_prots = $n_canonical_proteins_batch ($n_cum_canonicals_batch cumul.)\n";
      unless ($this_search_batch_id == -998899) {
      	print "Processing search_batch_id=$this_search_batch_id  ";
      	$n_experiments++;
      }
    }

    #### Put this peptide entry to the arrays
    #### To save memory, only save what we need later
    if ($not_done) {
      my $unmodified_pepseq = $columns[$origseqcol];
      my $prob = $columns[$origprobcol];
      my $one_mapped_protid = $columns[$origprotcol];
      my $pep_acc = $columns[$origacccol];
      my $tmp = "$pep_acc,$prob,$one_mapped_protid";

      push(@search_batch_peptides,$tmp);
      $n_assignments++;
      $distinct_peptides{$unmodified_pepseq}->{count}++;
      if (! $distinct_peptides{$unmodified_pepseq}->{best_probability}) {
        $distinct_peptides{$unmodified_pepseq}->{best_probability} = $prob;
      } elsif ($prob > $distinct_peptides{$unmodified_pepseq}->{best_probability}) {
        $distinct_peptides{$unmodified_pepseq}->{best_probability} = $prob; 
      }
    }
  }

  close(INFILE);
  print "Done reading.\n";
	print scalar keys %distinct_peptides;
	print " distinct\n";


  #### If we want to write a revised 2+ton peptide list
  my $write_filtered_peptide_list = 1;
  if ($write_filtered_peptide_list) {
    open(OUTFILT,">out.2tonsequences");
  }

  #### Count how many singleton peptides there are
  my $n_singleton_distinct_peptides = 0;
  my $n_P1_singleton_distinct_peptides = 0;
  foreach my $peptide (keys(%distinct_peptides)) {
    $n_singleton_distinct_peptides++
      if ($distinct_peptides{$peptide}->{count} == 1);
    $n_P1_singleton_distinct_peptides++
      if ($distinct_peptides{$peptide}->{count} == 1 &&
	  $distinct_peptides{$peptide}->{best_probability} == 1);
    if ($write_filtered_peptide_list &&
	$distinct_peptides{$peptide}->{count} > 1) {
      print OUTFILT "$peptide\n";
    }
  }

  if ($write_filtered_peptide_list) {
    close(OUTFILT);
  }

  my $n_distinct_peptides = scalar(keys(%distinct_peptides));

  print "Total experiments: $n_experiments\n";
  print "Total assignments above threshold: $n_assignments\n";

  print "Total distinct peptides: $n_distinct_peptides\n";
  print "Total singleton distinct peptides: $n_singleton_distinct_peptides\n";
  print "Total P=1 singleton distinct peptides: $n_P1_singleton_distinct_peptides\n";


  my $n_nonsingleton_distinct_peptides = $n_distinct_peptides-$n_singleton_distinct_peptides;
  print "Non-singleton distinct peptides: $n_nonsingleton_distinct_peptides\n";

  my $outfile = "../analysis/peptide_length-charge_dist.tsv";
  open (OUT , ">$outfile\n");
  print "peptide charge cnt:\n";
  foreach my $c (sort {$a <=> $b} keys %charge_cnt){
    next if ($c eq '');
    print OUT "charge\t$c\t$charge_cnt{$c}\n";
    print "\t$c\t$charge_cnt{$c}\n";
  }
  print "peptide length cnt:\n";
  foreach my $c (sort {$a <=> $b} keys %length_cnt){
    last if ($c > 50);
    print OUT "length\t$c\t$length_cnt{$c}\n";
    print "\t$c\t$length_cnt{$c}\n";
  }
  %length_cnt = (); 
	open(FA, "$fasta_file") || die "Couldn't open file $fasta_file\n";
	my $fasta = new FAlite(\*FA);

	while( my $entry = $fasta->nextEntry() ){
		my $seq = uc( $entry->seq() );
    my $def = $entry->def();
    next if ($def =~ />DECOY/);
	  my $tryptics = $biolink->do_tryptic_digestion( aa_seq => $seq, min_len => 7, max_len => 50 );	
	  for my $tryp ( @$tryptics ) {	
		  $stat{tryptic_peptide_sequences}{$tryp} =1;
    }
	}
  %length_cnt = ();
  foreach my $pep (keys %{$stat{tryptic_peptide_sequences}}){
    $length_cnt{length($pep)}++;
  }
  foreach my $c (sort {$a <=> $b} keys %length_cnt){
    last if ($c > 50);
    print OUT "tlength\t$c\t$length_cnt{$c}\n";
  }
  %length_cnt = ();
  foreach my $pep (keys %distinct_peptides){
    $length_cnt{length($pep)}++;
  } 
  foreach my $c (sort {$a <=> $b} keys %length_cnt){
    last if ($c > 50);
    print OUT "distinctPlength\t$c\t$length_cnt{$c}\n";
  }
  %length_cnt = ();
  foreach my $pep (keys %{$stat{distinct_peptides_tryptic}}){
    $length_cnt{length($pep)}++;
  }
  foreach my $c (sort {$a <=> $b} keys %length_cnt){
    last if ($c > 50);
    print OUT "trypPlength\t$c\t$length_cnt{$c}\n";
  }

  %length_cnt=(); 
  foreach my $c (sort {$a <=> $b} keys %{$stat{peptidePerProtein}}){
    if ($stat{peptidePerProtein}{$c} == 0){
       print "$c 0 peptide\n";
       next;
    }
    $stat{peptidePerProtein}{$c} = '>=50' if ($stat{peptidePerProtein}{$c}>=50);
    $length_cnt{$stat{peptidePerProtein}{$c}}++; 
  }
  foreach my $c (sort {$a <=> $b} keys %length_cnt){
   next if($c eq '>=50');
    print OUT "peptidePerProtein\t$c\t$length_cnt{$c}\n";
  }
  print OUT "peptidePerProtein\t>=50\t$length_cnt{'>=50'}\n" if ($length_cnt{'>=50'});

  close OUT;


	#my $outfile2="experiment_contribution_summary_w_singletons.out";
	my $outfile2="experiment_contribution_summary.out";
	open (OUTFILE2, ">", $outfile2) or die "can't open $outfile2 ($!)";
	print OUTFILE2 "          sample_tag sbid ngoodspec      npep n_new_pep cum_nspec cum_n_new is_pub nprot cum_nprot\n";
	print OUTFILE2 "-------------------- ---- --------- --------- --------- --------- --------- ------ ----- ---------\n";

  #### Calculate the number of distinct peptides as a function of exp.
  my $niter = 1;
  for (my $iter=0; $iter<$niter; $iter++) {
    my @shuffled_search_batch_ids = @all_search_batch_ids;
    if ($iter > 0) {
      my $result = shuffleArray(array_ref=>\@all_search_batch_ids);
      @shuffled_search_batch_ids = @{$result};
    }
    my %total_distinct_peptides_all;
    my $p_cum_n_new_all = 0;
    my $cum_nspec = 0;

    print "number of sbid " , scalar  @shuffled_search_batch_ids ,"\n";
    foreach my $search_batch_id ( @shuffled_search_batch_ids ) {
      my %batch_distinct_peptides_all;
      my @lines;
      tie @lines, "DB_File", "psbi", O_RDWR|O_CREAT, 0666, $DB_RECNO or die "Cannot open file 'text': $!\n" ;
      @lines =  split("\n", $all_peptides{$search_batch_id});
      foreach my $line ( @lines ) {
        my @tmp = split(",", $line);
        my $peptide = \@tmp;
        if ( $included_peptides{$peptide->[$seqcol]}){
					$batch_distinct_peptides_all{$peptide->[$seqcol]}++;
					$total_distinct_peptides_all{$peptide->[$seqcol]}++;
        }
      }
      my $n_goodspec = scalar @lines;
      $cum_nspec += $n_goodspec;
      my $n_peptides_all = scalar(keys(%batch_distinct_peptides_all));
      my $cum_n_new_all = scalar(keys(%total_distinct_peptides_all));
      my $n_new_pep_all = $cum_n_new_all - $p_cum_n_new_all;
      my $sample_tag = $sample_tags{$search_batch_id};
      
      my $n_canonical_prots = 0; 
      my $n_cum_canonical_prots = 0; 
      if (! $canonical_hash{$search_batch_id}{exp} ){
        print "WARNING: search_batch_id=$search_batch_id n_canonical_prots=$n_canonical_prots\n";
      }else{
        $n_canonical_prots = $canonical_hash{$search_batch_id}{exp};
      }
      if (! $canonical_hash{$search_batch_id}{cum} ){
        print "WARNING: search_batch_id=$search_batch_id n_cum_canonical_prots=$n_cum_canonical_prots\n";
      }else{
        $n_cum_canonical_prots = $canonical_hash{$search_batch_id}{cum};
      }

   
      printf OUTFILE2 "%20.20s %4.0f %9.0f %9.0f %9.0f %9.0f %9.0f %6s %5d %5d\n",
	      $sample_tag, $search_batch_id,$n_goodspec ,
	      $n_peptides_all, $n_new_pep_all,
	      $cum_nspec, $cum_n_new_all, 'N', $n_canonical_prots, $n_cum_canonical_prots;

      $p_cum_n_new_all = $cum_n_new_all;
      untie @lines;
    }
  }
  print "$outfile2 written.\n" if $VERBOSE;
  unlink "peptidehash";
  unlink "psbi";
  return(1);
}



###############################################################################
# by_Probability
###############################################################################
sub by_Probability {

  return $b->[$probcol] <=> $a->[$probcol];

} # end by_Probability



###############################################################################
# numerically
###############################################################################
sub numerically {

  return $a <=> $b;

} # end numerically



###############################################################################
# round
###############################################################################
sub round {

  my $value = shift;
  my $digits = shift;
  return sprintf("%.${digits}f",$value);

} # end round

###############################################################################
# shuffleArray
###############################################################################
sub shuffleArray {
  my $METHOD = 'shuffleArray';
  my %args = @_;
  my $array_ref = $args{'array_ref'} || die("No array_ref provided");

  my $n_elements = scalar(@{$array_ref});

  my @new_array;

  my %hash;
  foreach my $element ( @{$array_ref} ) {
    $hash{$element} = 1;
  }

  my $n_left = $n_elements;
  for (my $i=0; $i<$n_elements; $i++) {
    my $index = rand($n_left);
    my @tmp_array = keys(%hash);
    my $id = $tmp_array[$index];
    push(@new_array,$id);
    delete($hash{$id});
    #print "$n_left\t$index\t$tmp_array[$index]\n";
    $n_left--;
  }

  return(\@new_array);

}

