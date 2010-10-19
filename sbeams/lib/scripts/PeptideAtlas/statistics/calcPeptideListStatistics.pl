#!/usr/local/bin/perl -w

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

#### Set up SBEAMS modules
use lib "/net/dblocal/www/html/devTF/sbeams/lib/perl";
use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;

use SBEAMS::PeptideAtlas;
use SBEAMS::PeptideAtlas::Settings;
use SBEAMS::PeptideAtlas::Tables;

use SBEAMS::Proteomics;
use SBEAMS::Proteomics::Settings;
use SBEAMS::Proteomics::Tables;

## Globals
my $sbeams = new SBEAMS::Connection;
my $atlas = new SBEAMS::PeptideAtlas;
$atlas->setSBEAMS($sbeams);

use vars qw (
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG $TESTONLY
             $peptide_hash $probcol $protcol $seqcol
            );


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
  --prot_file         Input PAprotIdentlist tsv file; needed for prot plot
  --pepmap_file       Input peptide_mapping.tsv file; needed for prot plot
  --P_threshold       Use this threshold for processing instead of
                      using all peptides in the input file
  --search_batch_id   If set, only process this search_batch_id and
                      ignore others

 e.g.:  $PROG_NAME --verbose 2 --source YeastInputExperiments.tsv

EOU


#### If no parameters are given, print usage information
unless ($ARGV[0]){
  print "$USAGE";
  exit;
}


#### Process options
unless (GetOptions(\%OPTIONS,"verbose:s","quiet","debug:s","testonly",
  "source_file:s","prot_file:s","pepmap_file:s",
  "P_threshold:f","search_batch_id:i",
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

  my $prot_file = $OPTIONS{prot_file};
  my $pepmap_file = $OPTIONS{pepmap_file};
  unless (($prot_file && open(PROTFILE, $prot_file)) &&
          ($pepmap_file && open(PEPMAPFILE, $pepmap_file)))
    print "WARNING: --prot_file or --pepmap_file missing or unopenable; protein stats won't be compiled and cumulative protein plot won't be drawn.\n\n";
    undef $prot_file;
  }

  my $P_threshold = $OPTIONS{P_threshold} || 0;
  my $process_search_batch_id = $OPTIONS{search_batch_id} || 0;

  my $this_search_batch_id;
  my $n_experiments = 0;

  my @peptides;
  my @search_batch_pepseqs;
  my @correct_peptides;
  my @search_batch_peptides;
  my @stats_table;


  #### Array of search_batch_ids and a hash of all peptides by search_batch_id
  my @all_search_batch_ids;
  my %all_peptides;
  my %sample_tags;

  #### Hashes containing canonical protein info
  my %canonical_hash;
  my %pepmap_hash;
  my %n_canonical_prots;
  my %n_cumulative_canonical_prots;

  ### First, read prot info if provided
  if ($prot_file) {
    # read header and get index of biosequence_name from it
#protein_group_number,biosequence_name,probability,confidence,n_observations,n_distinct_peptides,level_name,represented_by_biosequence_name,subsumed_by_biosequence_name,estimated_ng_per_ml,abundance_uncertainty,is_covering,group_size
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
      if ($fields[$level_name_idx] eq 'canonical') {
	$canonical_hash{$fields[$biosequence_name_idx]} = 1;
      }
    }
    my $n_canonicals = scalar keys %canonical_hash;
    print "$n_canonicals total distinct canonical protein identifiers found\n";

    #### Make a hash of peptide -> canonical proteins
    my $n_pep_mappings = 0;
    # for line in peptide_mapping.tsv (lacks header)
    while ($line = <PEPMAPFILE>) {
      chomp $line;
      # get peptide, protein
      my ($pep_acc, $unmod_pep_seq, $prot_acc) = split("\t", $line);
      # if protein is canonical
      if (defined $canonical_hash{$prot_acc}) {
	# add protein to list hashed to by peptide
        if (! defined $pepmap_hash{$unmod_pep_seq}) {
          my @a = ( $prot_acc );
          $pepmap_hash{$unmod_pep_seq} = \@a;
        } else {
          push (@{$pepmap_hash{$unmod_pep_seq}}, $prot_acc);
        }
        $n_pep_mappings++;
      }
    }
    print "$n_pep_mappings total peptide->canonical mappings\n";
    my $n_mapped_peps = keys %pepmap_hash;
    print "$n_mapped_peps distinct unmodified peptides mapped\n";
  }

  ##### Skip header
  my $line = <INFILE>;
  my @header_columns = split(/\t/,$line);
  #$probcol = 2;
  #$probcol = 4 if ($header_columns[4] eq 'probability');
  $seqcol = 0;
  my $origseqcol = 3;   #unmodified peptide sequence
  $probcol = 1;
  my $origprobcol = 8;   #PeptideProphet peptide probability
  $protcol = 2;
  my $origprotcol = 10;  #accession of a protein mapped to

  #### Read in all the peptides for the first experiment and get the
  #### prot info
  my @columns;
  my $n_spectra = 0;
  my %canonical_protids;
  my $not_done = 1;
  while ($not_done) {

    #### Try to read in the next line;
    if ($line = <INFILE>) {
      chomp($line);
      @columns = split(/\t/,$line);
      next if ($columns[$origprobcol] < $P_threshold);
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
      $all_peptides{$this_search_batch_id} = \@tmp;

      #### Remove some peptides according to their probabilities
      my $result = removePeptides(
        peptide_list => \@search_batch_peptides,
      );
      push(@correct_peptides,@{$result->{peptide_list}});

      #### Get the canonical proteins mapped to by all peptides in this
      #### search batch.
      my %canonical_protids_batch = ();
      for my $pep (@search_batch_pepseqs) {
        for my $canonical_protid (@{$pepmap_hash{$pep}}) {
          $canonical_protids_batch{$canonical_protid} = 1;
          $canonical_protids{$canonical_protid} = 1;
        }
      }

      $n_canonical_prots{$this_search_batch_id} =
            scalar keys %canonical_protids_batch;
      $n_cumulative_canonical_prots{$this_search_batch_id} =
	    scalar keys %canonical_protids;
      $sample_tags{$this_search_batch_id} = 'xx';

      #### Update the summary table of incorrect values with data from
      #### this search_batch
      my $irow = 0;
      foreach my $stat_row ( @{$result->{stats_table}} ) {
	for (my $col=0; $col<2; $col++) {
	  $stats_table[$irow]->[$col] = $stat_row->[$col];
	}
	for (my $col=2; $col<5; $col++) {
	  $stats_table[$irow]->[$col] += $stat_row->[$col];
	}
	$irow++;
      }


      #### Prepare for next search_batch_id
      $this_search_batch_id = $columns[0];
      @search_batch_peptides = ();
      @search_batch_pepseqs = ();
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
      my @tmp = ($unmodified_pepseq, $prob, $one_mapped_protid);
      push(@search_batch_peptides,\@tmp);
      push(@peptides,\@tmp);
      push(@search_batch_pepseqs,$unmodified_pepseq);
    }
  }

  close(INFILE);
  print "Done reading.\n";

  #### Now build a hash out of all peptides and count the distinct ones
  my %distinct_peptides;
  foreach my $peptide (@peptides) {
    $distinct_peptides{$peptide->[$seqcol]}->{count}++;
    if (! $distinct_peptides{$peptide->[$seqcol]}->{best_probability}) {
      $distinct_peptides{$peptide->[$seqcol]}->{best_probability} = $peptide->[$probcol];
    } elsif ($peptide->[$probcol] >
               $distinct_peptides{$peptide->[$seqcol]}->{best_probability}) {
      $distinct_peptides{$peptide->[$seqcol]}->{best_probability} = $peptide->[$probcol];
    }
  }


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



  #### Now build a hash out of all peptides and count the distinct ones
  my %correct_distinct_peptides;
  foreach my $peptide (@correct_peptides) {
    $correct_distinct_peptides{$peptide->[1]}++;
  }


  #### Count how many dupe DECOY peptides there are
  my %DECOYcount;
  foreach my $peptide ( keys(%{$peptide_hash}) ) {
    if ($peptide_hash->{$peptide}->{DECOYcount}) {
      $DECOYcount{$peptide_hash->{$peptide}->{DECOYcount}}++;
    }
  }


  my $n_assignments = scalar(@peptides);
  my $n_correct_assignments = scalar(@correct_peptides);
  my $n_incorrect_assignments = $n_assignments - $n_correct_assignments;

  my $n_distinct_peptides = scalar(keys(%distinct_peptides));
  my $n_correct_distinct_peptides = scalar(keys(%correct_distinct_peptides));
  my $n_incorrect_distinct_peptides = $n_distinct_peptides -
    $n_correct_distinct_peptides;

  my $assignments_FDR = round($n_incorrect_assignments/$n_assignments,3);
  my $distinct_peptide_FDR =
    round($n_incorrect_distinct_peptides/$n_distinct_peptides,3);

  my $most_pessimistic_distinct_peptide_FDR =
    round($n_incorrect_assignments/$n_distinct_peptides,3);
  my $most_pessimistic_distinct_peptides =
    $n_distinct_peptides*(1-($n_incorrect_assignments/$n_distinct_peptides));


  print "Total experiments: $n_experiments\n";
  print "Total assignments above threshold: $n_assignments\n";
  print "Total correct assignments: $n_correct_assignments\n";
  print "Total incorrect assignments: $n_incorrect_assignments\n";
  print "Peptide FDR: $assignments_FDR\n\n";

  print "Total distinct peptides: $n_distinct_peptides\n";
  print "Total singleton distinct peptides: $n_singleton_distinct_peptides\n";
  print "Total P=1 singleton distinct peptides: $n_P1_singleton_distinct_peptides\n";
  print "Most pessimistic distinct peptide FDR: $most_pessimistic_distinct_peptide_FDR\n";
  print "Most pessimistic distinct peptides: $most_pessimistic_distinct_peptides\n\n";

  my $num_incorr_mult_hit_percent = 6;
  if ($P_threshold < .75) {
    $num_incorr_mult_hit_percent = 10;
  }


  print "Discard all singletons and assume that $num_incorr_mult_hit_percent% of incorrect are 2+tons\n";
  my $n_nonsingleton_distinct_peptides = $n_distinct_peptides-$n_singleton_distinct_peptides;
  print "Non-singleton distinct peptides: $n_nonsingleton_distinct_peptides\n";
  my $n_nonsingleton_incorrect_assignments = int($n_incorrect_assignments*$num_incorr_mult_hit_percent/100);
  print "$num_incorr_mult_hit_percent% of incorrect peptides: $n_nonsingleton_incorrect_assignments\n";
  my $better_distinct_peptide_FDR = round($n_nonsingleton_incorrect_assignments/
    $n_nonsingleton_distinct_peptides,3);
  print "Estimated non-singleton distinct peptide FDR: $better_distinct_peptide_FDR\n\n";


  my $totDECOY = 0;
  my $totDistinctDECOY = 0;
  my $buffer = '';
  foreach my $count ( sort numerically (keys(%DECOYcount)) ) {
    $buffer .= "  $count\t$DECOYcount{$count}\n";
    $totDECOY += $DECOYcount{$count} * $count;
    $totDistinctDECOY += $DECOYcount{$count};
  }
  print "\nTotal number of DECOY hits: $totDECOY\n";
  print "Frequency/count of duplicate DECOY peptides:\n$buffer\n";


  #### Print out the table of final stats
  open(OUTFILE,">PPvsDECOY.dat");
  print "\nFinal stats by P bin:\n";
  print " P_floor P_ceiling  PP_incorr  n_DECOY  N_assignments\n";
  print OUTFILE " P_floor P_ceiling  PP_incorr  n_DECOY  N_assignments\n";
  foreach my $stat_row ( @stats_table ) {
    printf("%8.2f %8.2f %8d %8d %8d\n",@{$stat_row});
    printf OUTFILE ("%8.2f %8.2f %8d %8d %8d\n",@{$stat_row});
  }
  close(OUTFILE);


  print "\nFDR rates based on decoy numbers (after discarding decoy hits)\n";
  printf("Spectrum FDR = %d / %d = %.4f\n",$totDECOY,$n_assignments,$totDECOY/$n_assignments);
  printf("Peptide FDR = %d / %d = %.4f\n",$totDistinctDECOY,$n_distinct_peptides,$totDistinctDECOY/$n_distinct_peptides);



    #my $outfile2="experiment_contribution_summary_w_singletons.out";
    my $outfile2="experiment_contribution_summary.out";
    open (OUTFILE2, ">", $outfile2) or die "can't open $outfile2 ($!)";
    print OUTFILE2 "          sample_tag sbid ngoodspec      npep n_new_pep cum_nspec cum_n_new is_pub nprot cum_nprot\n";
    print OUTFILE2 "-------------------- ---- --------- --------- --------- --------- --------- ------ ----- ---------\n";


  #### Calculate the number of distinct peptides as a function of exp.
  #### 08/28/09 TMF: count total and multiply observed.
  ####   Display total (before today, displayed multiply observed)
  ####   consistent with new build pipeline where FDR threshold
  ####   lets through only trustable, high prob singletons.
  my $niter = 1;

  for (my $iter=0; $iter<$niter; $iter++) {

    my @shuffled_search_batch_ids = @all_search_batch_ids;
    if ($iter > 0) {
      my $result = shuffleArray(array_ref=>\@all_search_batch_ids);
      @shuffled_search_batch_ids = @{$result};
    }

    my %total_distinct_peptides_multobs;
    my %total_distinct_peptides_all;
    my $p_cum_n_new_multobs = 0;
    my $p_cum_n_new_all = 0;
    my $cum_nspec = 0;

    foreach my $search_batch_id ( @shuffled_search_batch_ids ) {
      my $peptide_list = $all_peptides{$search_batch_id};
      my %batch_distinct_peptides_multobs;
      my %batch_distinct_peptides_all;
      foreach my $peptide ( @{$peptide_list} ) {
	$batch_distinct_peptides_all{$peptide->[$seqcol]}++;
	$total_distinct_peptides_all{$peptide->[$seqcol]}++;
	if ($distinct_peptides{$peptide->[$seqcol]}->{count} > 1) {
	  $batch_distinct_peptides_multobs{$peptide->[$seqcol]}++;
	  $total_distinct_peptides_multobs{$peptide->[$seqcol]}++;
	}
      }
      my $n_goodspec = scalar(@{$peptide_list});
      $cum_nspec += $n_goodspec;
      my $n_peptides_multobs = scalar(keys(%batch_distinct_peptides_multobs));
      my $cum_n_new_multobs = scalar(keys(%total_distinct_peptides_multobs));
      my $n_new_pep_multobs = $cum_n_new_multobs - $p_cum_n_new_multobs;
      my $n_peptides_all = scalar(keys(%batch_distinct_peptides_all));
      my $cum_n_new_all = scalar(keys(%total_distinct_peptides_all));
      my $n_new_pep_all = $cum_n_new_all - $p_cum_n_new_all;
      my $n_prots = $n_canonical_prots{$search_batch_id};
      my $n_cum_prots = $n_cumulative_canonical_prots{$search_batch_id};
      my $sample_tag = $sample_tags{$search_batch_id};

      printf OUTFILE2 "%20.20s %4.0f %9.0f %9.0f %9.0f %9.0f %9.0f %6s %5d %5d\n",
	      $sample_tag, $search_batch_id,$n_goodspec ,
	      $n_peptides_all, $n_new_pep_all,
	      $cum_nspec, $cum_n_new_all, 'N',
              $n_prots, $n_cum_prots
	     ;

      $p_cum_n_new_multobs = $cum_n_new_multobs;
      $p_cum_n_new_all = $cum_n_new_all;
    }
  }
  print "$outfile2 written.\n" if $VERBOSE;


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
# removePeptides
###############################################################################
sub removePeptides {
  my $METHOD = 'removePeptides';
  my %args = @_;
  my $peptide_list = $args{'peptide_list'} || die("No peptide_list provided");

  my @peptides = @{$peptide_list};
  my $n_peptides = scalar(@peptides);

  my @sorted_peptides = sort by_Probability @peptides;
  my @filtered_peptides;

  my @stats_table;

  my ($floor,$ceiling) = ( 1.0, 1.0 );
  #my ($increment,$minimum) = ( 0.01, 0.90 );
  my ($increment,$minimum) = ( 0.05, 0.50 );

  my @buffer;
  my $remainder = 0.0;
  my $n_DECOY = 0;

  foreach my $peptide ( @sorted_peptides ) {
    #print "$peptide->[0]\t$peptide->[1]\t$peptide->[$probcol]\n";
    my $probability = $peptide->[$probcol];

    #### If this peptide hits the floor, remove peptides in this window
    unless ($probability >= $floor) {

      my $result = removePeptidesWithinWindow2(
        peptide_list => \@buffer,
        floor => $floor,
        ceiling => $ceiling,
        remainder => $remainder,
      );

      push(@filtered_peptides,@{$result->{peptide_list}});
      push(@stats_table,[$floor,$ceiling,$result->{n_wrong},$n_DECOY,
			 $result->{n_peptides}]);
      print "    n_DECOY=$n_DECOY\n" if ($VERBOSE > 1);

      $remainder = $result->{remainder};


      @buffer = ();
      $ceiling = $floor;
      $floor = $ceiling - $increment;
      $n_DECOY=0;

    }

    #### Save the peptide in the buffer
    push(@buffer,$peptide);
    $peptide_hash->{$peptide->[$seqcol]}->{count}++;
    if (defined($peptide->[$protcol]) && $peptide->[$protcol] =~ /^DECOY/) {
      #print "  decoy $peptide->[$protcol]  $peptide->[$seqcol]\n";
      $n_DECOY++;
      $peptide_hash->{$peptide->[$seqcol]}->{DECOYcount}++;
    }


  }

  my $result = removePeptidesWithinWindow2(
    peptide_list => \@buffer,
    floor => $floor,
    ceiling => $ceiling,
    remainder => $remainder,
  );

  push(@filtered_peptides,@{$result->{peptide_list}});
  push(@stats_table,[$floor,$ceiling,$result->{n_wrong},$n_DECOY,$result->{n_peptides}]);
  print "    n_DECOY=$n_DECOY\n" if ($VERBOSE > 1);



  my $n_filtered_peptides = scalar(@filtered_peptides);

  if ($VERBOSE) {
    print "  Initial number of peptides: $n_peptides\n";
    print "  Filtered number of peptides: $n_filtered_peptides\n";
  }

  my %result = (
    remainder => $remainder,
    peptide_list => \@filtered_peptides,
    stats_table => \@stats_table,
  );

  return(\%result);


} # end removePeptides



###############################################################################
# removePeptidesWithinWindow1
#
# Removes the number of peptides from the peptide_list based on probabilities
# by calculating the total number of wrong ones and randomly picking some
# to throw out.  This will yield a different result every time.
###############################################################################
sub removePeptidesWithinWindow1 {
  my $METHOD = 'removePeptidesWithinWindow2';
  my %args = @_;
  my $peptide_list = $args{'peptide_list'} || die("No peptide_list provided");
  my $floor = $args{'floor'} || die("No floor provided");
  my $ceiling = $args{'ceiling'} || die("No ceiling provided");
  my $remainder = $args{'remainder'};

  my $n_peptides = scalar(@{$peptide_list});

  #### Calculate the total number of wrong ones based on the sum of P's
  my $sum = 0;
  foreach my $peptide ( @{$peptide_list} ) {
    $sum += $peptide->[$probcol];
  }
  my $n_wrong = $n_peptides - $sum;


  if ($VERBOSE > 1) {
    print "  [$METHOD]: floor=$floor; ceiling=$ceiling\n";
    print "    n_peptides=$n_peptides; n_wrong=$n_wrong\n";
    print "    remainder=$remainder\n";
  }

  my $n_to_remove = int($n_wrong);
  $remainder = $n_wrong - $n_to_remove;

  for (my $i=0; $i<$n_to_remove; $i++) {
    my $success = 0;
    while (! $success) {
      my $index = rand(@{$peptide_list});
      if ($peptide_list->[$index]) {
	$peptide_list->[$index] = undef;
	$success = 1;
      }
    }
  }

  my @new_peptide_list;
  foreach my $entry ( @{$peptide_list}) {
    push(@new_peptide_list,$entry) if ($entry);
  }

  my $n_surviving_peptides = scalar(@new_peptide_list);
  print "    n_surviving_peptides=$n_surviving_peptides\n" if ($VERBOSE > 1);


  my %result = (
    remainder => $remainder,
    peptide_list => \@new_peptide_list,
    n_peptides => $n_peptides,
    n_wrong => $n_wrong,
  );

  return(\%result);

} # end removePeptidesWithinWindow1



###############################################################################
# removePeptidesWithinWindow2
#
# Removes the number of peptides from the peptide_list based on probabilities
# by iterating through a sorted list of peptides and throwing one out when the
# 1-P sum exceeds 1.  This is the same every time it's run and most
# accurate.
###############################################################################
sub removePeptidesWithinWindow2 {
  my $METHOD = 'removePeptidesWithinWindow2';
  my %args = @_;
  my $peptide_list = $args{'peptide_list'} || die("No peptide_list provided");
  my $floor = $args{'floor'} || die("No floor provided");
  my $ceiling = $args{'ceiling'} || die("No ceiling provided");
  my $remainder = $args{'remainder'};

  my $n_peptides = scalar(@{$peptide_list});

  my @sorted_peptides = sort by_Probability(@{$peptide_list});
  my @new_peptide_list;
  my $n_wrong = 0;

  #### Iterate through sorted list and throw out whenever we exceed 1
  my $sum = 0;
  foreach my $peptide ( @sorted_peptides ) {
    $sum += 1 - $peptide->[$probcol];
    if ($sum >= 1.0) {
      $sum -= 1;
      $n_wrong++;
    } else {
      push(@new_peptide_list,$peptide);
    }
  }

  $remainder = $sum;

  if ($VERBOSE > 1) {
    print "  [$METHOD]: floor=$floor; ceiling=$ceiling\n";
    print "    n_peptides=$n_peptides; n_wrong=$n_wrong\n";
    print "    remainder=$remainder\n";
  }


  my $n_surviving_peptides = scalar(@new_peptide_list);
  print "    n_surviving_peptides=$n_surviving_peptides\n" if ($VERBOSE > 1);


  my %result = (
    remainder => $remainder,
    peptide_list => \@new_peptide_list,
    n_peptides => $n_peptides,
    n_wrong => $n_wrong,
  );

  return(\%result);

} # end removePeptidesWithinWindow2



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

__DATA__

      #### Get the canonical proteins mapped to by all peptides in this
      #### search batch.
      my $sql =<<"      SMPL";
	SELECT BS.biosequence_name, S.sample_tag
	FROM $TBAT_ATLAS_SEARCH_BATCH ASB
	JOIN $TBAT_ATLAS_BUILD_SEARCH_BATCH ABSB ON ( ABSB.atlas_search_batch_id = ASB.atlas_search_batch_id )
        JOIN $TBPR_SEARCH_BATCH PSB ON
               PSB.search_batch_id = ASB.proteomics_search_batch_id
	JOIN $TBAT_SAMPLE S ON S.sample_id = ABSB.sample_id
	JOIN $TBAT_PEPTIDE_INSTANCE_SEARCH_BATCH PIS ON PIS.atlas_search_batch_id = ASB.atlas_search_batch_id
	JOIN $TBAT_PEPTIDE_INSTANCE PI ON ( PIS.peptide_instance_id = PI.peptide_instance_id AND PI.atlas_build_id = ABSB.atlas_build_id )
	JOIN $TBAT_PEPTIDE_MAPPING PM ON PI.peptide_instance_id = PM.peptide_instance_id
	JOIN $TBAT_BIOSEQUENCE BS ON PM.matched_biosequence_id = BS.biosequence_id
	JOIN $TBAT_PROTEIN_IDENTIFICATION PID on (BS.biosequence_id = PID.biosequence_id AND PID.atlas_build_id = ABSB.atlas_build_id)
	JOIN $TBAT_PROTEIN_PRESENCE_LEVEL PPL ON PID.presence_level_id = PPL.protein_presence_level_id
        JOIN $TBAT_ATLAS_BUILD AB ON AB.atlas_build_id = PI.atlas_build_id
	WHERE AB.data_path = '$atlas_data_dir'
	AND PPL.level_name = 'canonical'
	AND BS.biosequence_name NOT LIKE 'DECOY%'
	AND PSB.search_batch_id = $this_search_batch_id
        GROUP BY BS.biosequence_name, S.sample_tag
      SMPL

      my @rows = $sbeams->selectSeveralColumns($sql);
      my $sample_tag = $rows[0]->[1];
      my $n_canonical_proteins_batch = scalar @rows;
      for (my $i=0;  $i < $n_canonical_proteins_batch; $i++) {
        # use of uninitialized value in hash element
        $canonical_protids{$rows[$i]->[0]} = 1;
      }
      my $n_cum_canonicals_batch = scalar keys %canonical_protids;
      $n_canonical_prots{$this_search_batch_id} = $n_canonical_proteins_batch;
      $n_cumulative_canonical_prots{$this_search_batch_id} = $n_cum_canonicals_batch;
      $sample_tag = 'xx' if (! $sample_tag );
      $sample_tags{$this_search_batch_id} = $sample_tag;

