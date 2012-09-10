package SBEAMS::PeptideAtlas::KeySearch;

###############################################################################
# Class       : SBEAMS::PeptideAtlas::KeySearch
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
#
=head1 SBEAMS::PeptideAtlas::KeySearch

=head2 SYNOPSIS

  SBEAMS::PeptideAtlas::KeySearch

=head2 DESCRIPTION

This is part of the SBEAMS::PeptideAtlas module which handles
smart searching the database by keywords.

=cut
#
###############################################################################

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
@ISA = qw();
$VERSION = q[$Id$];
@EXPORT_OK = qw();

use SBEAMS::Connection;
use SBEAMS::Connection::Tables;
use SBEAMS::PeptideAtlas;
use SBEAMS::PeptideAtlas::Tables;
use SBEAMS::BioLink::Tables;

use vars qw($VERBOSE $TESTONLY $sbeams);

###############################################################################
# Constructor
###############################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;
    return($self);
} # end new


###############################################################################
# setSBEAMS: Receive the main SBEAMS object
###############################################################################
sub setSBEAMS {
    my $self = shift;
    $sbeams = shift;
    return($sbeams);
} # end setSBEAMS



###############################################################################
# getSBEAMS: Provide the main SBEAMS object
###############################################################################
sub getSBEAMS {
    my $self = shift;
    return $sbeams || SBEAMS::Connection->new();
} # end getSBEAMS


sub rebuildKeyIndex {
  my $METHOD = 'rebuildKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  my $verbose = $args{verbose};
  if ($verbose) {
    $VERBOSE = $verbose;
  } elsif ($VERBOSE) {
  } else {
    $VERBOSE = 0;
  }

  #### Set testonly flag if provided or not yet set
  my $testonly = $args{testonly};
  if ($testonly) {
    $TESTONLY = $testonly;
  } elsif ($TESTONLY) {
  } else {
    $TESTONLY = 0;
  }

  #### Retreive parameters
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $organism_name = $args{organism_name}
    or die("ERROR[$METHOD]: Parameter organism_name not passed");

  my $organism_id = $sbeams->get_organism_id( organism => $organism_name )
    or die( "ERROR[$METHOD] Unable to find organism ID for $organism_name" );

  $self->dropKeyIndex(
      atlas_build_id => $atlas_build_id,
  );

  #### Get the list of proteins that have a peptide in this atlas build
  my $matched_proteins = $self->getNProteinHits(
    organism_id => $organism_id,
    atlas_build_id => $atlas_build_id,
  );


  my $counter = 0;

  print "Inserting SearchKeyLink ...\n";
  foreach my $protein (keys %{$matched_proteins}){
    my $resource_n_matches = $matched_proteins->{$protein};
    my %rowdata =(
            organism_id => $organism_id,
         atlas_build_id => $atlas_build_id,
          resource_name => $protein,
     resource_n_matches => $resource_n_matches, 
           resource_url => "GetProtein?atlas_build_id=$atlas_build_id&protein_name=$protein&action=QUERY",
    );
    $sbeams->updateOrInsertRow(
      insert => 1,
      table_name => "$TBAT_SEARCH_KEY_LINK",
      rowdata_ref => \%rowdata,
      verbose=>$VERBOSE,
      testonly=>$TESTONLY,
    );

    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

  }

  print "Loading peptides keys...\n";
  $self->buildPeptideKeyIndex(
      organism_id=>$organism_id,
      atlas_build_id=>$atlas_build_id,
  );
    
}


###############################################################################
# rebuildKeyIndex
###############################################################################
sub InsertSearchKeyEntity {
  my $METHOD = 'InsertSearchKeyEntity';
  my $self = shift || die ("self not passed");
  my %args = @_;
  my $verbose = $args{verbose};
  if ($verbose) {
    $VERBOSE = $verbose;
  } elsif ($VERBOSE) {
  } else {
    $VERBOSE = 0;
  }

  #### Set testonly flag if provided or not yet set
  my $testonly = $args{testonly};
  if ($testonly) {
    $TESTONLY = $testonly;
  } elsif ($TESTONLY) {
  } else {
    $TESTONLY = 0;
  }


  #### Set verbosity level if provided or not yet set
  print "INFO[$METHOD]: Rebuilding key index..." if ($VERBOSE);

  #### Retreive parameters
  my $biosequence_set_id = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $organism_name = $self->get_organism_name( biosequence_set_id => $biosequence_set_id )
    or die( "ERROR[$METHOD] Unable to find organism ID for $biosequence_set_id" );

  my $reference_directory;

  if ($organism_name =~ /^Human$|^Mouse$|^COW$/i ) {
    #my $GOA_directory = $args{GOA_directory}
    my $uc_organism_name = uc($organism_name);
    my $GOA_directory = `ls -dlrt /net/db/src/GOA/* | grep '^d' | tail -1`;
    chomp $GOA_directory;
    $GOA_directory  =~ s/.*\/net/\/net/;

    #  or die("ERROR[$METHOD]: Parameter GOA_directory not passed");
    print "Loading protein keys from GOA...\n";
		$self->buildGoaKeyIndex(
			GOA_directory =>  $GOA_directory,
				organism_name => lc($organism_name), 
				biosequence_set_id => $biosequence_set_id,
			);
  }else{
    $reference_directory = $args{reference_directory} 
      or die("ERROR[$METHOD]: Parameter reference_directory  not passed");
  }

  
  if ($organism_name eq 'Yeast') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SGD_features.tab...\n";
    $self->buildSGDKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }
  

  if ($organism_name =~ /candida/i) {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from C_albicans feature...\n";
    $self->buildCANALKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

  if ($organism_name eq 'Halobacterium') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildHalobacteriumKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

  if ($organism_name eq 'Streptococcus') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildStreptococcusKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }
  if ($organism_name =~ /falciparum/){
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildPfalciparumKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }
  if ($organism_name eq 'Leptospira interrogans') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildLeptospiraKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

  if ($organism_name eq 'Drosophila') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    
    $self->buildDrosophilaKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

  if ($organism_name eq 'Mtuberculosis') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildMTBKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

  if ($organism_name =~ /Dog/i) {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildDogKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

  if ($organism_name eq 'Pig') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildPigKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

 if ($organism_name eq 'Honeybee') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildHoneyBeeKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

 if ($organism_name eq 'Ecoli') {
    my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
    print "Loading protein keys from SBEAMS and reference files...\n";
    $self->buildEcoliKeyIndex(
      reference_directory => $reference_directory,
      biosequence_set_id => $biosequence_set_id,
    );
  }

  if ($organism_name eq 'C Elegans') {
      my $reference_directory = $args{reference_directory}
      or die("ERROR[$METHOD]: Parameter reference_directory not passed");
      print "Loading protein keys from SBEAMS and reference files...\n";
      $self->buildCelegansKeyIndex(
				   reference_directory => $reference_directory,
           biosequence_set_id => $biosequence_set_id,
				   );
  }

  return(1);
} # end rebuildKeyIndex



###############################################################################
# dropKeyIndex: Drop all existing search keys in the search_key table
###############################################################################
sub dropKeyIndex {
  my $METHOD = 'dropKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;
  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  print "INFO[$METHOD] Dropping key index for atlas_build_id=$atlas_build_id...\n"
    if ($VERBOSE);

  unless ($sbeams) {
    die("ERROR[$METHOD]: sbeams object is not defined. Use setSBEAMS() method");
  }
  #my $sql = "DROP INDEX $TBAT_SEARCH_KEY.idx_search_key_name";
  #$sbeams->executeSQL($sql);

  my $sql = "DELETE FROM $TBAT_SEARCH_KEY_LINK WHERE atlas_build_id = '$atlas_build_id'";
  $sbeams->executeSQL($sql);

  return(1);

} # end dropKeyIndex


###############################################################################
# buildGoaKeyIndex
###############################################################################
sub buildGoaKeyIndex {
  my $METHOD = 'buildGoaKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building GOA key index...\n" if ($VERBOSE);

  my $GOA_directory = $args{GOA_directory}
    or die("ERROR[$METHOD]: Parameter GOA_directory not passed");

  unless (-d $GOA_directory) {
    die("ERROR[$METHOD]: '$GOA_directory' is not a directory");
  }

  my $biosequence_set_id = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter biosequence_set_id not passed");

  my $organism_name = $args{organism_name}
    or die("ERROR[$METHOD]: Parameter organism_name not passed");

  #### Open the provided GOA xrefs file
  #my $GOA_file = "$GOA_directory/${organism_name}.xrefs";
  my $GOA_file = "$GOA_directory/ipi.".uc($organism_name).".xrefs";
  
  open(INFILE,$GOA_file)
    or die("ERROR[$METHOD]: Unable to open file '$GOA_file'");

  #### Read the GOA gene_associations file
  my $associations = $self->readGOAAssociations(
    assocations_file => "$GOA_directory/gene_association.goa_${organism_name}",
  );

  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );
    

  #### Read all the GOA xrefs
  my $line;
  my $counter = 0;

  while ($line=<INFILE>) {
    chomp($line);
    my ($Database,$Accession,$IPI,$UniProtSP,$UniProtTR,$Ensembl,$RefSeqNP,
        $RefSeqXP,$Hinv,$proteins,$HGNCgenew,$EntrezGene,$UNIPARC,
      	$UniGene) = split(/\t/,$line);
    my $UniProtKB;
    my $protein_alias_master;
    my $protein_alias_master_source; 
    if (0) {
      print "-------------------------------------------------\n";
      print "Database=$Database\n";
      print "Accession=$Accession\n";
      print "IPI=$IPI\n";
      print "UniProtSP=$UniProtSP\n";
      print "UniProtTR=$UniProtTR\n";
      print "Ensembl=$Ensembl\n";
      print "RefSeqNP=$RefSeqNP\n";
      print "RefSeqXP=$RefSeqXP\n";
      print "Hinv=$Hinv\n";
      print "proteins=$proteins\n";
      print "HGNCgenew=$HGNCgenew\n";
      print "EntrezGene=$EntrezGene\n";
      print "UNIPARC=$UNIPARC\n";
      print "UniGene=$UniGene\n";
    }

    #### Map Ensembl and RefSeqNP accessions to themselves
    if ($Database && $Accession) {
      if ($Database =~ /ENSEMBL/) {
    	$Ensembl = $Accession;
      } elsif ($Database =~ /REFSEQ/) {
    	$RefSeqNP = $Accession;
      } elsif ($Database eq 'SP') {
        $UniProtKB = $Accession;     
      }
    }


    #### Skip if we don't have an ENSP number
    unless ($Ensembl) {
      #print "WARNING[$METHOD]: No ENSP for $Database:$Accession. Ignoring..\n";
      #next;
      $Ensembl = '';
    }

    #### Build a list of protein links
    my @links;

    if ($Database and $Accession) {
      $Database = 'UniProt' if ($Database eq 'SP');
      $Database = 'TrEMBL' if ($Database eq 'TR');
      my @tmp = ($Database,$Accession,40);
      push(@links,\@tmp) unless ($Database =~ /ENSEMBL/);
    }

    # added UniProtSP 07/06/09 TMF.
    if ($UniProtSP) {
      my @list = splitEntities(list=>$UniProtSP);
      $protein_alias_master = $list[0];
      $protein_alias_master_source = 'UniProt/Swiss-Prot';
      foreach my $item ( @list ) {
        my @tmp = ('UniProt/Swiss-Prot',$item,1);
        push(@links,\@tmp);
      }
    }

    if ($UniProtKB) {
      my @list = splitEntities(list=>$UniProtKB);
    }

    #### Split the Ensembl ID's
    my @Ensembl_IDS = splitEntities(list=>$Ensembl,delimiter=>';');

    if(! $protein_alias_master and @Ensembl_IDS > 0 ){
      $Ensembl_IDS[0] =~ s/HAVANA://;
      $protein_alias_master = $Ensembl_IDS[0];
      $protein_alias_master_source = 'Ensembl Protein';
    }
     
    if ($IPI) {
      my @list = splitEntities(list=>$IPI,delimiter=>';');
      if(! $protein_alias_master ){
        $protein_alias_master = $list[0];
        $protein_alias_master_source = 'IPI';
      }

      foreach my $item ( @list ) {
        my @tmp = ('IPI',$item,9);
        push(@links,\@tmp);
      }
    }


    if ($UniProtTR) {
      my @list = splitEntities(list=>$UniProtTR);
      foreach my $item ( @list ) {
        my @tmp = ('UniProt/TrEMBL',$item,35);
        push(@links,\@tmp);
      }
    }


    if ($RefSeqNP) {
      my @list = splitEntities(list=>$RefSeqNP,delimiter=>';');
      if(! $protein_alias_master ){
        $protein_alias_master = $list[0];
        $protein_alias_master_source = 'RefSeq';
      }
      foreach my $item ( @list ) {
    	$item =~ s/^\w+://;
        my @tmp = ('RefSeq',$item,39);
        push(@links,\@tmp);
      }
    }

    if ($RefSeqXP) {
      my @list = splitEntities(list=>$RefSeqXP,delimiter=>';');
      foreach my $item ( @list ) {
    	$item =~ s/^\w+://;
        my @tmp = ('RefSeq',$item,39);
        push(@links,\@tmp);
      }
    }

    if ($EntrezGene) {
      my @list = splitEntities(list=>$EntrezGene,delimiter=>';');
      foreach my $item ( @list ) {
        my @pair = split(/,/,$item);
        my @tmp = ('Entrez GeneID',$pair[0],37);
        push(@links,\@tmp);
        my @tmp2 = ('Entrez Gene Symbol',$pair[1],38);
        push(@links,\@tmp2);
      }
    }

    if ($UniGene) {
      my @list = splitEntities(list=>$UniGene,delimiter=>';');
      foreach my $item ( @list ) {
        my @tmp = ('UniGene',$item);
        push(@links,\@tmp);
      }
    }


    my $handle = "$Database:$Accession";
    if ($associations->{$handle}) {
      if ($associations->{$handle}->{Symbol} &&
        $associations->{$handle}->{Symbol} ne $Accession) {
        my @tmp = ('UniProt Symbol',$associations->{$handle}->{Symbol},35);
        push(@links,\@tmp);
      }
      if ($associations->{$handle}->{DB_Object_Name}) {
        my @tmp = ('Full Name',$associations->{$handle}->{DB_Object_Name});
        push(@links,\@tmp);
      }
    }


    #### Write the links for each Ensembl ID
    ### find protein_alias_master (go through the Ensembl, IPI and UniProt combined 
    ### list and find the first one that is in the biosequence set

    foreach my $Ensembl_ID (@Ensembl_IDS) {
      #### Strip HAVANA prefix
      $Ensembl_ID =~ s/HAVANA://;
      if(defined $proteinList->{$Ensembl_ID}){
        $proteinList->{$Ensembl_ID} = 1;
      }

      #### Insert an entry for the Ensembl ID itself
      my %rowdata = (
        search_key_name => $Ensembl_ID,
        search_key_type => 'Ensembl Protein',
        search_key_dbxref_id => 20,
        resource_name => $Ensembl_ID,
        resource_type => 'Ensembl Protein',
        protein_alias_master => $protein_alias_master,
      );

      $self->insertSearchKeyEntity( rowdata => \%rowdata);
    }  
    foreach my $link (@links) {
      my $resource_name = $link->[1];
      my $resource_type = $link->[0];
      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }else {
        $resource_name = $protein_alias_master;
        $resource_type = $protein_alias_master_source;
      }
      my %rowdata = (
          search_key_name => $link->[1],
    	    search_key_type => $link->[0],
    	    search_key_dbxref_id => $link->[2],
	        resource_name => $resource_name,
    	    resource_type => $resource_type,
          protein_alias_master => $protein_alias_master,
        );
      $self->insertSearchKeyEntity( rowdata => \%rowdata);
    }

    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    #my $xx=<STDIN>;

  } # endwhile ($line=<INFILE>)
  close(INFILE);
  # check if there is any protein in the proteinList have not been entered into the entity table
  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter); 

} # end buildGoaKeyIndex
sub checkCompleteness{
  my $SUB =  'checkCompleteness';
  my $self = shift;

  my %args = @_;
  my $proteinList = $args{proteinList} ;
  my $counter = $args{count};

  foreach my $prot (keys %{$proteinList}){
    if(! $proteinList->{$prot}){

     my %rowdata = (
        search_key_name => $prot,
        search_key_type => 'Protein Accession',
        resource_name => $prot,
        resource_type => 'Protein Accession',
        protein_alias_master => $prot,
     );
     $self->insertSearchKeyEntity( rowdata => \%rowdata);
     $counter++;
     print "$counter... " if ($counter/100 eq int($counter/100));
    }

  }

}

sub insertSearchKeyEntity {

  my $SUB = 'insertSearchKeyEntity';
  my $self = shift || die ("self not passed");
  my %args = @_;
  my $rowdata = $args{rowdata};

  my $search_key_name = $rowdata->{search_key_name};
  my $search_key_type = $rowdata->{search_key_type};
  my $search_key_dbxref_id = $rowdata->{search_key_dbxref_id};
  my $resource_name = $rowdata->{resource_name};
  my $resource_type = $rowdata->{resource_type};
  my $protein_alias_master = $rowdata->{protein_alias_master} || $resource_name;
  my $sbeams = $self->getSBEAMS();

  $search_key_name =~ s/'/''/g;
 
  
  my $sql = qq~
     SELECT SEARCH_KEY_ID
     FROM $TBAT_SEARCH_KEY_ENTITY
     WHERE RESOURCE_NAME = '$resource_name'
       AND SEARCH_KEY_NAME = '$search_key_name'
  ~;
  #print "$sql\n";
  my @rows = $sbeams->selectOneColumn($sql);
  my %rowdata=();

  if(! @rows){
      %rowdata = (
      search_key_name => $search_key_name,
      search_key_type => $search_key_type,
      search_key_dbxref_id => $search_key_dbxref_id,
      resource_name => $resource_name,
      resource_type => $resource_type,
      protein_alias_master => $protein_alias_master,
    );
    print "insert: $search_key_name $search_key_type $resource_name\n" if $VERBOSE;
    $sbeams->updateOrInsertRow(
      insert => 1,
      table_name => "$TBAT_SEARCH_KEY_ENTITY",
      rowdata_ref => \%rowdata,
      verbose=>$VERBOSE,
      testonly=>$TESTONLY,
    );
  }else{
    print "already in table: $search_key_name $resource_name\n" if $VERBOSE;
  }
}

###############################################################################
# readGOAAssociations
###############################################################################
sub readGOAAssociations {
  my $METHOD = 'readGOAAssociations';
  my $self = shift || die ("self not passed");
  my %args = @_;


  my $assocations_file = $args{assocations_file}
    or die("ERROR[$METHOD]: Parameter assocations_file not passed");
  print "INFO[$METHOD]: Reading GOA assocations file...$assocations_file \n" if ($VERBOSE);

  #### Open the provided GOA xrefs file
  open(ASSOCINFILE,$assocations_file)
    or die("ERROR[$METHOD]: Unable to open file 'assocations_file'");

  #### Read all the data
  my $line;
  my %associations;

  while ($line=<ASSOCINFILE>) {
    chomp($line);
    my ($Database,$Accession,$Symbol,$Qualifier,$GOid,$Reference,$Evidence,
        $With,$Aspect,$DB_Object_Name,$Synonym,$DB_Object_Type,
        ) = split(/\t/,$line);

    if (0) {
      print "-------------------------------------------------\n";
      print "Database=$Database\n";
      print "Accession=$Accession\n";
      print "Symbol=$Symbol\n";
      print "Qualifier=$Qualifier\n";
      print "GOid=$GOid\n";
      print "Reference=$Reference\n";
      print "Evidence=$Evidence\n";
      print "With=$With\n";
      print "Aspect=$Aspect\n";
      print "Synonym=$Synonym\n";
      print "DB_Object_Name=$DB_Object_Name\n";
    }
    if($Database eq 'UniProtKB'){
       $Database = 'UniProt';
    }
    $associations{"$Database:$Accession"}->{Symbol} = $Symbol;
    $associations{"$Database:$Accession"}->{DB_Object_Name} = $DB_Object_Name;

  } # endwhile ($line=<ASSOCINFILE>)

  close(ASSOCINFILE);
  return(\%associations);

} # end readGOAAssociations

###############################################################################
# buildCANALKeyIndex
###############################################################################
sub buildCANALKeyIndex {
  my $METHOD = 'buildCANALKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building SGD key index...\n" if ($VERBOSE);

  my $biosequence_set_id = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );


  #### Open the provided SGD_features.tab file
  my $feature_file = "$reference_directory/CANAL_feature.tab";
  open(INFILE,$feature_file)
    or die("ERROR[$METHOD]: Unable to open file '$feature_file'");

  #### Read all the data
  my $line;
  my $counter = 0;

  while ($line=<INFILE>) {
    chomp($line);
    my ($feature_name,$gene_name,
        $aliases,$feature_type,$chromosome,
      	$chr_start,$chr_end,$strand,
        $CGID,$sec_CGIDs,$description,$others
       ) = split(/\t/,$line);

    #### Skip if this isn't an ORF
    my @protein_synonyms = ();
    unless ($feature_type =~  /ORF/i) {
      next;
    }

    if (0) {
      print "-------------------------------------------------\n";
      print "orf19_name=$feature_name\n";
      print "feature_type=$feature_type\n";
      print "feature_name=$feature_name\n";
      print "gene_name=$gene_name\n";
      print "chromosome=$chromosome\n";
      print "chr_start=$chr_start\n";
      print "chr_end=$chr_end\n";
      print "strand=$strand\n";
      print "description=$description\n";
    }

    #### Build a list of protein links
    my @links;

    if ($feature_name) {
      my @tmp = ('ORF name',$feature_name);
      push(@links,\@tmp);
    }

    if ($gene_name) {
      my @tmp = ('Gene name',$gene_name);
      push(@links,\@tmp);
    }

    if ($aliases) {
      my @list = splitEntities(list=>$aliases,delimiter=>'\|');
      push @protein_synonyms,@list;
      foreach my $item ( @list ) {
        my @tmp = ('Alias',$item);
        push(@links,\@tmp);
      }
    }
    my @CGIDS;
    if($CGID){
      push(@CGIDS, $CGID);
    }
    if($sec_CGIDs){
      my @list = splitEntities(list=>$sec_CGIDs,delimiter=>'\|');
      push @CGIDS, @list;
    }
    foreach my $item ( @CGIDS ) {
        my @tmp = ('CGID',$item);
        push(@links,\@tmp);
    }
     
 

    if ($description) {
      my @tmp = ('Description',$description);
      push(@links,\@tmp);
    }

    my $protein_alias_master = $protein_synonyms[0];
    foreach my $link (@links) {
      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }

      my %rowdata = (
        search_key_name => $link->[1],
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $feature_name,
        resource_type => 'ORF Name',
      );
       $self -> insertSearchKeyEntity( rowdata => \%rowdata);
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    my $xx=<STDIN> if (0);

  } # endwhile ($line=<INFILE>)

  print "\n";
  close(INFILE);

  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);


} # end buildCANALKeyIndex




###############################################################################
# buildSGDKeyIndex
###############################################################################
sub buildSGDKeyIndex {
  my $METHOD = 'buildSGDKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building SGD key index...\n" if ($VERBOSE);

  my $biosequence_set_id = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }


  #### Read the contents of the UniProtKB mapping file
  #my $UP_file = "$reference_directory/UniProtKB_identifiers_from_AlainGateau.txt";
  my $UP_file = "$reference_directory/uniprot_SGD_mapping.txt";
  my %UniProtAccessions;
  open(INFILE,$UP_file)
    or die("ERROR[$METHOD]: Unable to open file '$UP_file'");
  while (my $line = <INFILE>) {
    chomp($line);
    next if ($line =~ /^\s*$/);
    #if ($line =~ /^(\S+)\sDR\s+PeptideAtlas;\s([\w\d\-]+);/) {
    if ($line =~ /^(\S+)\s+(\S+)$/){
      $UniProtAccessions{$2} = $1;
    } else {
      print "ERROR: Unable to parse line '$line'\n";
    }
  }
  close(INFILE);

  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );


  #### Open the provided SGD_features.tab file
  my $SGD_file = "$reference_directory/SGD_features.tab";
  open(INFILE,$SGD_file)
    or die("ERROR[$METHOD]: Unable to open file '$SGD_file'");

  #### Read all the data
  my $line;
  my $counter = 0;

  while ($line=<INFILE>) {
    chomp($line);
    my ($SGDID,$feature_type,$feature_qualifier,$feature_name,$gene_name,
        $aliases,$chromosome_string,$chr_junk,$chromosome,
      	$chr_start,$chr_end,$strand,
        $gene_pos,$seq_version,$unknown_version,$description,
       ) = split(/\t/,$line);

    #### Skip if this isn't an ORF
    my @protein_synonyms = ();
    unless ($feature_type eq 'ORF') {
      next;
    }

    if (0) {
      print "-------------------------------------------------\n";
      print "SGDID=$SGDID\n";
      print "feature_type=$feature_type\n";
      print "feature_qualifier=$feature_qualifier\n";
      print "feature_name=$feature_name\n";
      print "gene_name=$gene_name\n";
      print "chromosome_string=$chromosome_string\n";
      print "chr_junk=$chr_junk\n";
      print "chromosome=$chromosome\n";
      print "chr_start=$chr_start\n";
      print "chr_end=$chr_end\n";
      print "strand=$strand\n";
      print "gene_pos=$gene_pos\n";
      print "seq_version=$seq_version\n";
      print "unknown_version=$unknown_version\n";
      print "description=$description\n";
    }


    #### Skip if we don't have a feature_name
    unless ($feature_name) {
      print "WARNING: No feature_name for SGDID $SGDID. Skipping...\n";
      next;
    }

    #### Build a list of protein links
    my @links;

    if ($SGDID) {
      my @tmp = ('SGD ID',$SGDID);
      push(@links,\@tmp);
    }

    if ($feature_qualifier) {
      my @tmp = ('ORF qualifier',$feature_qualifier);
      push(@links,\@tmp);
    }

    if ($feature_name) {
      my @tmp = ('ORF name',$feature_name);
      push(@links,\@tmp);
    }

    if ($gene_name) {
      my @tmp = ('Gene name',$gene_name);
      push(@links,\@tmp);
    }

    if ($aliases) {
      my @list = splitEntities(list=>$aliases,delimiter=>'\|');
      push @protein_synonyms,@list;
      foreach my $item ( @list ) {
        my @tmp = ('Alias',$item);
        push(@links,\@tmp);
      }
    }

    if ($description) {
      my @tmp = ('Description',$description);
      push(@links,\@tmp);
    }

    if ($UniProtAccessions{$feature_name}) {
      my @tmp = ('UniProtKB',$UniProtAccessions{$feature_name});
      push(@links,\@tmp);
      print "UniProtKB: $feature_name=$UniProtAccessions{$feature_name}\n";
    } else {
      print "UniProtKB: $feature_name not found\n";
    }

    my $protein_alias_master = $protein_synonyms[0];
    foreach my $link (@links) {
      #print "    ".join("=",@{$link})."\n";
      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }

      my %rowdata = (
        search_key_name => $link->[1],
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $feature_name,
        resource_type => 'Yeast ORF Name',
      );
       $self -> insertSearchKeyEntity( rowdata => \%rowdata);
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    my $xx=<STDIN> if (0);

  } # endwhile ($line=<INFILE>)

  print "\n";
  close(INFILE);

  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);


} # end buildGoaKeyIndex



###############################################################################
# buildHalobacteriumKeyIndex
###############################################################################
sub buildHalobacteriumKeyIndex {
  my $METHOD = 'buildHalobacteriumKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Halobacterium key index...\n" if ($VERBOSE);

  my $biosequence_set_id = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }


  #### Load the ancient ORF names and create a lookup table
  my $reference_file = "$reference_directory/ORFmatches-edited.txt";
  my %oldORFnames;
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");
  while (my $line = <INFILE>) {
    $line =~ s/[\r\n]//g;
    my ($ORFname,$VNGname) = split("\t",$line);
    if ($VNGname) {
      $oldORFnames{$VNGname} = $ORFname;
    }
  }
  close(INFILE);

  #### Fetch the latest data from SBEAMS
  use SBEAMS::Client;
  my $remote_sbeams = new SBEAMS::Client;
  my $server_uri = "https://db.systemsbiology.net/sbeams";


  ##### Define the desired command and parameters
  my $server_command = "ProteinStructure/BrowseBioSequence.cgi";
  my $command_parameters = {
    biosequence_set_id => 5,
    #biosequence_gene_name_constraint => "bo%", for testing
    display_options => "limit_sequence_width",
    SBEAMSentrycode => "DF45jasj23jh",
  };


  #### Fetch the desired data from the SBEAMS server
  my $resultset = $remote_sbeams->fetch_data(
    server_uri => $server_uri,
    server_command => $server_command,
    command_parameters => $command_parameters,
  );

  #### Stop if the fetch was not a success
  unless ($resultset->{is_success}) {
    print "ERROR: Unable to fetch data.\n\n";
    exit;
  }
  unless ($resultset->{data_ref}) {
    print "ERROR: Unable to parse data result.  See raw_response.\n\n";
    exit;
  }

  #### Find the indexes of the columns of interest
  my @columns_names = qw ( biosequence_name biosequence_gene_name
    biosequence_accession aliases functional_description );
  my %idx;
  foreach my $column_name ( @columns_names ) {
    my $offset = $resultset->{column_hash_ref}->{$column_name};
    if ($offset gt '') {
      $idx{$column_name} = $offset;
    } else {
      die("ERROR: Unable to find column $column_name");
    }
  }

  #### Loop over all input rows processing information
  my $counter = 0;
  foreach my $row (@{$resultset->{data_ref}}) {

    my $biosequence_name = $row->[$idx{biosequence_name}];
    next unless ($biosequence_name);

    #### Build a list of protein links
    my @links;

    if ($biosequence_name) {
      my @tmp = ('ORF Name',$biosequence_name);
      push(@links,\@tmp);
    }

    my $biosequence_gene_name = $row->[$idx{biosequence_gene_name}];
    if ($biosequence_gene_name &&
      $biosequence_gene_name ne $biosequence_name) {
      my @tmp = ('Common Name',$biosequence_gene_name);
      push(@links,\@tmp);
    }

    my $biosequence_accession = $row->[$idx{biosequence_accession}];
    if ($biosequence_accession) {
      my @tmp = ('Gene ID',$biosequence_accession);
      push(@links,\@tmp);
    }

    my $functional_description = $row->[$idx{functional_description}];
    if ($functional_description) {
      my @tmp = ('Functional Description',$functional_description);
      push(@links,\@tmp);
    }

    my $ancient_name = $oldORFnames{$biosequence_name};
    if ($ancient_name) {
      my @tmp = ('Old ORF Name',$ancient_name);
      push(@links,\@tmp);
    }


    foreach my $link (@links) {
      #print "    ".join("=",@{$link})."\n";
      my %rowdata = (
        search_key_name => $link->[1],
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $biosequence_name,
        resource_type => 'Halobacterium ORF Name',
      );
       $self -> insertSearchKeyEntity( rowdata => \%rowdata);
    }
    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));
    my $xx=<STDIN> if (0);

  } # endfor each row

  print "\n";

} # end buildHalobacteriumKeyIndex

###############################################################################
# buildPfalciparumKeyIndex
###############################################################################
sub buildPfalciparumKeyIndex {
  my $METHOD = 'buildPfalciparumKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Pfalciparum key index...\n" if ($VERBOSE);

  my $biosequence_set_id  = $args{biosequence_set_id }
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my $organism_id = 44;
  my %proteins;

  #### Load information from gff file
  my $reference_file = "$reference_directory/PlasmoDB-9.1_Pfalciparum3D7.gff";

  #### Open file and skip header
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");
    while (my $line = <INFILE>) {
      last if ($line !~ /^##/);
    }

    #### Load data
    while (my $line = <INFILE>) {
    next unless ($line =~ /gene.*ID.*Name/);
    $line =~ s/[\r\n]//g;
    my @columns = split("\t",$line);

    my $mish_mash = $columns[8];
    my @keyvaluepairs = split(";",$mish_mash);
    
    my ($key,$value,$note,$protein_name);
    $mish_mash =~ /Name=([^;]+)/;
    
    $protein_name = $1;
    foreach my $keyvaluepair ( @keyvaluepairs ) {
      if ( $keyvaluepair =~ /(\w+)=(.+)/ ) {
       	$key = $1;
	      $value = $2;
      } else {
       	print "WARNING: Unable to parse '$keyvaluepair' into key=value\n";
       	next;
      }
      next if($key =~ /(ID|web_id|size|Name)/);
      if ($key eq 'description') {
				$note = $value;
				$note =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
        $note =~ s/\+/ /g;
      }
      if ($note) {
        if (length($note) > 800) {
        	$note = substr($note,0,800)."....";
        }
        $proteins{$protein_name}->{'Functional_Note'} = $note;
      }else{
        $proteins{$protein_name}->{$key} = $value;

      }

    }
  }

  close(INFILE);
  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );
  #### Loop over all input rows processing information
  my $counter = 0;
  foreach my $biosequence_name (keys(%proteins)) {

    #### Build a list of protein links
    my @links;
    foreach my $key ( qw (Alias Functional_Note) ) {
      if (exists($proteins{$biosequence_name}->{$key})) {
    	  my @tmp = ($key,$proteins{$biosequence_name}->{$key});
        print "$key $biosequence_name $proteins{$biosequence_name}->{$key}\n";
      	push(@links,\@tmp);
      }
    }

    foreach my $link (@links) {
      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }

      #print "    ".join("=",@{$link})."\n";
      my %rowdata = (
        search_key_name => $link->[1],
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $biosequence_name,
        resource_type => 'ApiDB',
      );
      $self->insertSearchKeyEntity( rowdata => \%rowdata);
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    #my $xx=<STDIN>;

  } # endfor each biosequence
  # check if there is any protein in the proteinList have not been entered into the entity table
  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);


} # end buildPfalciparumKeyIndex

###############################################################################
# buildStreptococcusKeyIndex
###############################################################################
sub buildStreptococcusKeyIndex {
  my $METHOD = 'buildStreptococcusKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Streptococcus key index...\n" if ($VERBOSE);

  my $biosequence_set_id  = $args{biosequence_set_id }
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my $organism_id = 25;
  my %proteins;



  #### Load information from ptt file
  my $reference_file = "$reference_directory/NC_002737.ptt";

  #### Open file and skip header
  my $header;
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");
  while ($header = <INFILE>) {
    last if ($header =~ /^Location/);
  }

  #### Create an array and hash of the columns
  $header =~ s/[\r\n]//g;
  my @columns_names = split("\t",$header);
  my %columns_names;
  my $index = 0;
  foreach my $column_name ( @columns_names ) {
    $columns_names{$column_name} = $index;
    #print "Column '$column_name'= $index\n";
    $index++;
  }

  #### Load data
  while (my $line = <INFILE>) {
    $line =~ s/[\r\n]//g;
    my @columns = split("\t",$line);
    my $protein_name = "gi|".$columns[$columns_names{PID}];
    $proteins{$protein_name}->{gi} = $protein_name;
    $proteins{$protein_name}->{ORF_name} = $columns[$columns_names{'Synonym'}];
    $proteins{$protein_name}->{gene_name} = $columns[$columns_names{'Gene'}];
    $proteins{$protein_name}->{COG} = $columns[$columns_names{'COG'}];
    $proteins{$protein_name}->{full_name} = $columns[$columns_names{'Product'}];
  }
  close(INFILE);


  #### Load information from gff file
  $reference_file = "$reference_directory/NC_002737.gff";

  #### Open file and skip header
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");
    while (my $line = <INFILE>) {
      last if ($line =~ /^##Type/);
    }

    #### Load data
    while (my $line = <INFILE>) {
    $line =~ s/[\r\n]//g;
    my @columns = split("\t",$line);
    next unless ($columns[2] eq 'CDS');

    my $mish_mash = $columns[8];
    my @keyvaluepairs = split(";",$mish_mash);


    my ($key,$value,$gi,$refseq,$geneID,$note);
    foreach my $keyvaluepair ( @keyvaluepairs ) {

      if ( $keyvaluepair =~ /(\w+)=(.+)/ ) {
       	$key = $1;
	      $value = $2;
      } else {
       	print "WARNING: Unable to parse '$keyvaluepair' into key=value\n";
       	next;
      }
      #print "keyvaluepair: $key=$value\n";

      if ($key eq 'db_xref') {
			if ($value =~ /^GI:(\d+)$/) {
				$gi = $1;
			} elsif ($value =~ /^GeneID:(\d+)$/) {
				$geneID = $1;
			} else {
				print "WARNING: unable to parse db_ref '$key=$value'\n";
			}
      }

      if ($key eq 'protein_id') {
				$refseq = $value;
			}

      if ($key eq 'note') {
				$note = $value;
				$note =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
      }

    }

    unless ($gi) {
      print "WARNING: No gi number for line '$line'\n";
      next;
    }

    my $protein_name = "gi|$gi";

    if ($refseq) {
      $proteins{$protein_name}->{RefSeq} = $refseq;
      $proteins{$protein_name}->{combined} = "$protein_name|ref|$refseq|";
    }

    if ($geneID) {
      $proteins{$protein_name}->{'Entrez GeneID'} = $geneID;
    }

    if ($note) {
      if (length($note) > 800) {
	$note = substr($note,0,800)."....";
      }
      $proteins{$protein_name}->{'Functional_Note'} = $note;
    }

  }
  close(INFILE);

  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );
  #### Loop over all input rows processing information
  my $counter = 0;
  foreach my $biosequence_name (keys(%proteins)) {

    #### Build a list of protein links
    my @links;

    if ($biosequence_name) {
      my @tmp = ('gi Accession',$biosequence_name);
      push(@links,\@tmp);
    }

    foreach my $key ( qw (ORF_name gene_name COG full_name RefSeq combined Functional_Note) ) {
      if (exists($proteins{$biosequence_name}->{$key})) {
    	  my @tmp = ($key,$proteins{$biosequence_name}->{$key});
      	push(@links,\@tmp);
      }
    }

    foreach my $link (@links) {
      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }

      #print "    ".join("=",@{$link})."\n";
      my %rowdata = (
        search_key_name => $link->[1],
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $biosequence_name,
        resource_type => 'S. pyogenes accession',
      );
      $self->insertSearchKeyEntity( rowdata => \%rowdata);
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    #my $xx=<STDIN>;

  } # endfor each biosequence
  # check if there is any protein in the proteinList have not been entered into the entity table
  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);


} # end buildStreptococcusKeyIndex


###############################################################################
# buildLeptospiraKeyIndex
###############################################################################
sub buildLeptospiraKeyIndex {
  my $METHOD = 'buildLeptospiraKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Leptospira key index...\n" if ($VERBOSE);

  my $biosequence_set_id  = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my $organism_id = 27;
  my %proteins;



  #### Load information from ptt file
  my $reference_file = "$reference_directory/NC_005823.ptt";

  #### Open file and skip header
  my $header;
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");
  while ($header = <INFILE>) {
    last if ($header =~ /^Location/);
  }

  #### Create an array and hash of the columns
  $header =~ s/[\r\n]//g;
  my @columns_names = split("\t",$header);
  my %columns_names;
  my $index = 0;
  foreach my $column_name ( @columns_names ) {
    $columns_names{$column_name} = $index;
    #print "Column '$column_name'= $index\n";
    $index++;
  }

  #### Load data
  while (my $line = <INFILE>) {
    $line =~ s/[\r\n]//g;
    my @columns = split("\t",$line);
    my $protein_name = "gi|".$columns[$columns_names{PID}];
    $proteins{$protein_name}->{gi} = $protein_name;
    $proteins{$protein_name}->{ORF_name} = $columns[$columns_names{'Synonym'}];
    $proteins{$protein_name}->{gene_name} = $columns[$columns_names{'Gene'}];
    $proteins{$protein_name}->{COG} = $columns[$columns_names{'COG'}];
    $proteins{$protein_name}->{full_name} = $columns[$columns_names{'Product'}];
  }
  close(INFILE);


  #### Load information from gff file
  $reference_file = "$reference_directory/NC_005823.gff";

  #### Open file and skip header
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");
  while (my $line = <INFILE>) {
    last if ($line =~ /^##Type/);
  }

  #### Load data
  while (my $line = <INFILE>) {
    $line =~ s/[\r\n]//g;
    my @columns = split("\t",$line);
    next unless ($columns[2] eq 'CDS');

    my $mish_mash = $columns[8];
    my @keyvaluepairs = split(";",$mish_mash);


    my ($key,$value,$gi,$refseq,$geneID,$note);
    foreach my $keyvaluepair ( @keyvaluepairs ) {

      if ( $keyvaluepair =~ /(\w+)=(.+)/ ) {
	$key = $1;
	$value = $2;
      } else {
	print "WARNING: Unable to parse '$keyvaluepair' into key=value\n";
	next;
      }
      #print "keyvaluepair: $key=$value\n";

      if ($key eq 'db_xref') {
	if ($value =~ /^GI:(\d+)$/) {
	  $gi = $1;
	} elsif ($value =~ /^GeneID:(\d+)$/) {
	  $geneID = $1;
	} else {
	  print "WARNING: unable to parse db_ref '$key=$value'\n";
	}
      }

      if ($key eq 'protein_id') {
	$refseq = $value;
      }

      if ($key eq 'note') {
	$note = $value;
	$note =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
      }

    }

    unless ($gi) {
      print "WARNING: No gi number for line '$line'\n";
      next;
    }

    my $protein_name = "gi|$gi";

    if ($refseq) {
      $proteins{$protein_name}->{RefSeq} = $refseq;
      $proteins{$protein_name}->{combined} = "$protein_name|ref|$refseq|";
    }

    if ($geneID) {
      $proteins{$protein_name}->{'Entrez GeneID'} = $geneID;
    }

    if ($note) {
      if (length($note) > 800) {
	$note = substr($note,0,800)."....";
      }
      $proteins{$protein_name}->{'Functional_Note'} = $note;
    }

  }
  close(INFILE);

  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );

  #### Loop over all input rows processing information
  my $counter = 0;
  foreach my $biosequence_name (keys(%proteins)) {

    #### Debugging
    #print "protein=",$biosequence_name,"\n";
    #print "protein(combined)=",$proteins{$biosequence_name}->{combined},"\n";


    #### Build a list of protein links
    my @links;

    if ($biosequence_name) {
      my @tmp = ('gi Accession',$biosequence_name);
      push(@links,\@tmp);
    }

    foreach my $key ( qw (ORF_name gene_name COG full_name RefSeq combined Functional_Note) ) {
      if (exists($proteins{$biosequence_name}->{$key})) {
	my @tmp = ($key,$proteins{$biosequence_name}->{$key});
	push(@links,\@tmp);
      }
    }

    foreach my $link (@links) {
      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }
      #print "    ".join("=",@{$link})."\n";
      my %rowdata = (
        search_key_name => $link->[1],
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $proteins{$biosequence_name}->{combined},
        resource_type => 'L. interrogans accession',
      );
      $self->insertSearchKeyEntity( rowdata => \%rowdata);
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    #my $xx=<STDIN>;

  } # endfor each biosequence

  $self->checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);

  print "\n";

} # end buildLeptospiraKeyIndex

###############################################################################
# buildDogKeyIndex
###############################################################################
sub buildDogKeyIndex {
  my $METHOD = 'buildDogKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Dog key index...\n" if ($VERBOSE);

  my $biosequence_set_id  = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my $organism_id = 37;

  
  my $counter =0;
  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );
  my $protein_file = "$reference_directory/canis_familiaris_EnsemblXref.txt";
  open(INFILE,$protein_file) || die("ERROR: Unable to open '$protein_file'");
  while (my $line = <INFILE>) {
    $line =~ /GN=(.*),UPSP=(.*)_.*,ENSP=(.*)/;    
    my $uniprotKB = $2;
    my $gene = $1;
    my $ensp = $3;

    my @links;
    my ($db, $id);
    my ($resource_name, $resource_type);
    foreach my $Accession ($uniprotKB, $ensp){
      my $prot = '';
      
			if ($Accession =~ /^ENS/){
				 $db="Ensembl";
				 $id = 31;
         $prot = $ensp;
         $resource_name = $uniprotKB;
         $resource_type = 'UniprotKB';         
			}else{
				 $db="UniProtKB";
				 $id=37;
         $prot = $uniprotKB;
         $resource_name = $ensp;
         $resource_type= 'ENSEMBL';
			}
      my @tmp = ($db, $Accession, $id );
			push(@links,\@tmp);
		  my @tmp = ('Gene Symbol',$gene);
		  push(@links,\@tmp);
		  foreach my $link (@links) {
			  my %rowdata = (
				  search_key_name => $link->[1],
				  search_key_type => $link->[0],
				  search_key_dbxref_id => $link->[2],
				  resource_name => $resource_name,
				  resource_type => $resource_type,
			  	protein_alias_master => $ensp,
			  );
			  $self -> insertSearchKeyEntity( rowdata => \%rowdata);
			}
     }
    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));
	 }
  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);

}
###############################################################################
# buildMTBKeyIndex
###############################################################################
sub buildMTBKeyIndex {
  my $METHOD = 'buildMTBKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building MTB key index...\n" if ($VERBOSE);

  my $biosequence_set_id  = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my $organism_id = 40;

  
  my %proteins = ();
  my $protein_file = "$reference_directory/TubercuList_v2-3.fasta";
  open(INFILE,$protein_file) || die("ERROR: Unable to open '$protein_file'");
  while (my $line = <INFILE>) {
    if ($line =~ /^>/) {
      my ($FullName, $uniprotKB, $gene);
      if($line =~ /^>/){        
          $line =~ />(\S+)\|(\S+)/;
          $FullName = "$1|$2";
          $uniprotKB= $1;
					if($1 ne $2){
            $gene = $2;
					}
       }
      print "uniprotKB $uniprotKB FullName $FullName $gene\n" if ($VERBOSE);
      $proteins{$uniprotKB}{'Gene Symbol'} = $gene;
      $proteins{$uniprotKB}{'Full Name'} = $FullName;
    }
  }
  close(INFILE);
  #### Open the GOA file
  #my $GOA_file = "$reference_directory/M_tuberculosis_ATCC_Oshkosh.goa";

  #my $associations = $self->readGOAAssociations(
  #  assocations_file => "$GOA_file",
  #);


  my $counter =0;
  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );

  foreach my $uniprotKB (keys %proteins) {
    my $Database = 'TubercuList' ;
    my $Accession = $uniprotKB;
    my $proteinName = $proteins{$uniprotKB}{'Full Name'};
    my $gene = $proteins{$uniprotKB}{'Gene Symbol'};
    my @links;

    my @tmp = ('TubercuList',$uniprotKB,58);
    push(@links,\@tmp);

    @tmp = ('Gene Symbol',$gene);
    push(@links,\@tmp);

    @tmp = ('Full Name',$proteinName);
    push(@links,\@tmp);

    #my $handle = "$Database:$Accession";
    #if ($associations->{$handle}) {
    #  if ($associations->{$handle}->{Symbol} &&
    #    $associations->{$handle}->{Symbol} ne $Accession) {
    #    my @tmp = ('UniProt Symbol',$associations->{$handle}->{Symbol},35);
    #    print $associations->{$handle}->{Symbol} ,"\n";
    #    push(@links,\@tmp);
    #  }
    #}

    foreach my $link (@links) {
      #print "    ".join("=",@{$link})."\n";
      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }

      my $resource_name = $link->[1];
      my $resource_type = $link->[0];
      my %rowdata = (
          search_key_name => $link->[1],
    	  search_key_type => $link->[0],
    	  search_key_dbxref_id => $link->[2],
	      resource_name => $proteinName,
    	  resource_type => 'MTB accession',
        );
        $self -> insertSearchKeyEntity( rowdata => \%rowdata);
    }

    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));
    my $xx=<STDIN> if (0);
 }
  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);

}

###############################################################################
# buildDrosophilaKeyIndex
###############################################################################
sub buildDrosophilaKeyIndex {
  my $METHOD = 'buildDrosophilaKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Drosophila key index...\n" if ($VERBOSE);

  my $biosequence_set_id = $args{biosequence_set_id }
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );

  #### Create a link from gene names to protein names
  my %gene2protein;
  my %genemapping;
  my $genemapping_file = "$reference_directory/fbgn_annotation_ID_fb_2009_05.tsv";
  open(MAP, $genemapping_file) ||  die("ERROR: Unable to open '$genemapping_file'");
  while (my $line = <MAP>) {
    next if ($line =~ /^#/);
    next if ($line =~ /^$/);
    chomp $line;
    my @tmp = split("\t", $line);
    my $fbgene = $tmp[1];
    my $gbgene;
    if($tmp[4]){
      $gbgene = $tmp[3].",".$tmp[4]; 
    }
    else{
      $gbgene = $tmp[3];
    }
    my @gbgenes =  split(",", $gbgene);
    foreach my $gb (@gbgenes){
       $genemapping{$gb} = $fbgene;
    }
  }  
  my %dbxref_ids = (
    'RefSeq'       => 39,
    'GeneBank'     => 46,
    'FlyBase'      => 2,
    'UniProt'      => 35,
    'Gene Ontology'=> 26,
  );
  my $xref_file = "$reference_directory/idmapping_protein_FBppxml.xls";
  open(REF , "<$xref_file") ||  die("ERROR: Unable to open '$xref_file'");
  my %xref;

  while (my $line = <REF>) {
   next if($line =~ /FlyBase/);
   chomp $line;
   my @ids = split("\t", $line);
   my $fbpp = $ids[0];
   my $cgpp = $ids[1];
   if($ids[1]){
     $xref{$cgpp}{Annotation_ID}= $cgpp;
     $xref{$fbpp}{FlyBase} = $fbpp;
       if($ids[3]){
         $xref{$cgpp}{GeneBank} = $ids[2];
       }
       if($ids[3]){
        $xref{$cgpp}{RefSeq} = $ids[3];
       }
   }
   if($ids[2]){
     $xref{$fbpp}{GeneBank} = $ids[2];
   }
   if($ids[3]){
     $xref{$fbpp}{RefSeq} = $ids[3];
   }
  } 
  my $protein_file = "$reference_directory/Drosophila_melanogaster.fasta";
  open(INFILE,$protein_file) || die("ERROR: Unable to open '$protein_file'");
  while (my $line = <INFILE>) {
    if ($line =~ /^>/) {
      my $protein;
      my $gene;
      if ($line =~ />(FBpp\d+)\s+pep.*gene:(FBgn.*)\s+transcript.*/){
        $protein = $1;
        $gene = $2;
      }
      elsif( $line =~/>(CG\d+\-*\w*)\s+pep.*gene:(.*)\s+transcript.*/){
        $protein =$1;
        $gene=$2;
      }
      if( !$protein || !$gene){
	     print "WARNING: Unable to find gene name/protein name in '$protein $gene'\n";
      }
      else{
        $gene2protein{$gene}->{$protein} = 1;
        if($protein =~ /FB/){
          $xref{$protein}{FlyBase} = $protein;
        }
        
        #print "Read mapping: $gene -> $protein\n"; 
      }
    }
  }
  close(INFILE);
  close (MAP);
  close (REF);
  #### Open the GOA file
  my $GOA_file = "$reference_directory/17.D_melanogaster.goa";
  open(INFILE,$GOA_file)
    or die("ERROR[$METHOD]: Unable to open file '$GOA_file'");

  #### Read all the data
  my $counter = 0;
  my $previous_id = 'xx';
  

  while (my $line=<INFILE>) {
    chomp($line);
    my @tmp;
    my @columns = split(/\t/,$line);
    my $UniProt_id = $columns[1];
    next unless ($UniProt_id);
    next if ($UniProt_id eq $previous_id);
    $previous_id = $UniProt_id;

    my $aliases = $columns[10];
    my $full_name = "Gene: $columns[10]: $columns[9]";
#    my @aliases = split("|",$aliases);

    #### Build a list of protein links
    my @links;
    if ($UniProt_id) {
      my @tmp = ('UniProt ID',$UniProt_id, $dbxref_ids{UniProt});
      push(@links,\@tmp);
    }

    my $gene_name;
    my $cggene_name;
    if ($aliases) {
      my @list = splitEntities(list=>$aliases,delimiter=>'\|');
      foreach my $item ( @list ) {
        my @tmp = ('Gene Alias',$item);
	    if ($item =~ /^CG.+/) {
          if(defined $genemapping{$item}){
            $cggene_name = $item;
	        $gene_name = $genemapping{$item};
          }
          else{
            print "UNMAPPED $item ";
          }
          push(@links,\@tmp);
	    }else {
	      push(@links,\@tmp);
	    }
      }
    }
    my @feature_names;
    my $protein_alias_master ='';
    if ($gene_name) {
      if ($gene2protein{$gene_name}) {
	    foreach my $protein ( keys(%{$gene2protein{$gene_name}}) ) {
	      push(@feature_names,$protein);
	    }
      }
    }
    if ($cggene_name) {
      if  ($gene2protein{$cggene_name}) {
        foreach my $protein ( keys(%{$gene2protein{$cggene_name}}) ) {
          push(@feature_names,$protein);
        }
      }
    }
    unless (@feature_names) {
      push(@feature_names,'UNKNOWN');
    }
    $protein_alias_master = $feature_names[0];

    foreach my $feature_name ( @feature_names ) {
        next if ($feature_name eq 'UNKNOWN');
        my @temp_links;
        @temp_links = @links;
        my $protein_alias;
        foreach my $key (qw (FlyBase GeneBank RefSeq Annotation_ID)){
          if (exists $xref{$feature_name}{$key}) {
           my @tmp;
           if($key ne 'Annotation_ID'){
             @tmp = ($key,$xref{$feature_name}{$key}, $dbxref_ids{$key});
           }
           else{
               @tmp = ('Annotation ID',$xref{$feature_name}{$key});
          }
           push(@temp_links,\@tmp);
           $protein_alias .= $xref{$feature_name}{$key}."|";
        }
        }  
        if($full_name){
          my @tmp;
          if($protein_alias){
            my $fullname = "Protein: $protein_alias $full_name";
            @tmp = ('Full Name',$fullname);
            push(@temp_links,\@tmp);
          }
          else{
            @tmp = ('Full Name',$full_name);
            push(@temp_links,\@tmp);
          }
        }
        foreach my $link (@temp_links) {
          if(defined $proteinList->{$link->[1]}){
            $proteinList->{$link->[1]} = 1;
          }
				#print "    ".join("=",@{$link})."\n";
					my %rowdata = (
						search_key_name => $link->[1],
						search_key_type => $link->[0],
						search_key_dbxref_id => $link->[2],
						resource_name => $feature_name,
						resource_type => 'Drosophila Protein',
						protein_alias_master => $protein_alias_master,
						);
						$self->insertSearchKeyEntity( rowdata => \%rowdata);
        }
        $full_name = '';
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    my $xx=<STDIN> if (0);

  } # endfor each row

  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);

} # end buildDrosophilaKeyIndex


###############################################################################
# buildPigKeyIndex
###############################################################################
sub buildPigKeyIndex {
  my $METHOD = 'buildPigKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Pig key index...\n" if ($VERBOSE);

  my $biosequence_set_id  = $args{biosequence_set_id }
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my %proteins;

  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );


  #### Load information from ptt file
  my $reference_file = "$reference_directory/Pig_combined.fasta";
  print "Reading $reference_file\n" if ($VERBOSE);
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");

  #### Load data
  while (my $line = <INFILE>) {
    $line =~ s/[\r\n]//g;
    if ($line =~ /^>/) {
      if ($line =~ /^>(\S+)/) {
	my $protein_name = $1;
	if ($line =~ /^>\S+\s+(.+)$/) {
	  my $description = $1;
	  if ($description =~ /^(.+) - Sus scrofa \(Pig\)\s*/) {
	    $proteins{$protein_name}->{full_name} = $1;
	  } elsif ($description =~ /^(.+) \(PRRSV\)\s*$/) {
	    $proteins{$protein_name}->{full_name} = $1;
	  } elsif ($description =~ /^(.+) \([A-Z0-9]+\)\s*$/) {
	    $proteins{$protein_name}->{full_name} = $1;
	  } elsif ($description =~ /^(.+) \[Sus scrofa\]\s*$/) {
	    $description = $1;
	    if ($description =~ /\](.+?)$/) {
	      $proteins{$protein_name}->{full_name} = $1;
	    }
	    if ($description =~ /([PQ][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9])/) {
	      $proteins{$protein_name}->{UniProt} = $1;
	    }
	    if ($description =~ /([PQ][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]_PIG)/) {
	      $proteins{$protein_name}->{UniProt} = $1;
	    }
	    if ($description =~ /(NP_[\d\.])/) {
	      $proteins{$protein_name}->{RefSeq} = $1;
	    }
	  } else {
	    $proteins{$protein_name}->{full_name} = $description;
	  }
	}
      }
    }
  }
  close(INFILE);


  #### Loop over all input rows processing information
  my $counter = 0;
  foreach my $biosequence_name (keys(%proteins)) {

    #### Debugging
    #print "protein=",$biosequence_name,"\n";
    #print "protein(combined)=",$proteins{$biosequence_name}->{combined},"\n";


    #### Build a list of protein links
    my (@links, @tmp);

    if ($biosequence_name) {
      my @tmp = ('Accession',$biosequence_name);
      push(@links,\@tmp);
    }

    foreach my $key ( qw (full_name UniProt) ) {
      if (exists($proteins{$biosequence_name}->{$key})) {
  	    my @tmp = ($key,$proteins{$biosequence_name}->{$key});
	    push(@links,\@tmp);
      }
    }

    foreach my $link (@links) {

      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }

      #print "    ".join("=",@{$link})."\n";
      my %rowdata = (
        search_key_name => substr($link->[1],0,255),
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $biosequence_name,
        resource_type => 'Pig accession',
      );
      $self-> insertSearchKeyEntity( rowdata => \%rowdata);
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    #my $xx=<STDIN>;

  } # endfor each biosequence
  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);
  print "\n";

} # end buildPigKeyIndex



###############################################################################
# buildEcoliKeyIndex
###############################################################################
sub buildEcoliKeyIndex {
  my $METHOD = 'buildEcoliKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Pig key index...\n" if ($VERBOSE);

  my $biosequence_set_id  = $args{biosequence_set_id }
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }


  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );


  my %proteins;

  #### Load information from ptt file
  my $reference_file = "$reference_directory/Ecoli_Combined_NODECOY.fasta";
  print "Reading $reference_file\n" if ($VERBOSE);
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");

  #### Load data
  while (my $line = <INFILE>) {
      $line =~ s/[\r\n]//g;
      if ($line =~ /^>/) {
	  if ($line =~ /^>(\S+)/) {
	      my $protein_name = $1;
	      if ($line =~ /^>\S+\s+(.+)$/) {
		  my $description = $1;
		  
		  if ($description =~ /^(.+) - Sus scrofa \(Pig\)\s*/) {
		      $proteins{$protein_name}->{full_name} = $1;
		  } 
	  
		  elsif ($description =~ /^(.+) \(PRRSV\)\s*$/) {
		      $proteins{$protein_name}->{full_name} = $1;
		  } 

		  elsif ($description =~ /^(.+) \([A-Z0-9]+\)\s*$/) {
		      $proteins{$protein_name}->{full_name} = $1;
		  } 

		  elsif ($description =~ /^(.+) \[Sus scrofa\]\s*$/) {
		      my $description = $1;
	  

		      if ($description =~ /\](.+?)$/) {
			  $proteins{$protein_name}->{full_name} = $1;
		      }
		      if ($description =~ /([PQ][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9])/) {
			  $proteins{$protein_name}->{UniProt} = $1;
		      }
		      if ($description =~ /([PQ][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]_PIG)/) {
			  $proteins{$protein_name}->{UniProt} = $1;
		      }
		      if ($description =~ /(NP_[\d\.])/) {
			  $proteins{$protein_name}->{RefSeq} = $1;
		      }
		  } else {
		      $proteins{$protein_name}->{full_name} = $description;
		  }
	      }
	  }
      }
  }
  close(INFILE);

  #### Loop over all input rows processing information
  my $counter = 0;
  foreach my $biosequence_name (keys(%proteins)) {

    #### Debugging
    #print "protein=",$biosequence_name,"\n";
    #print "protein(combined)=",$proteins{$biosequence_name}->{combined},"\n";


    #### Build a list of protein links
    my @links;

    if ($biosequence_name) {
      my @tmp = ('Accession',$biosequence_name);
      push(@links,\@tmp);
    }

    foreach my $key ( qw (full_name UniProt) ) {
      if (exists($proteins{$biosequence_name}->{$key})) {
    	my @tmp = ($key,$proteins{$biosequence_name}->{$key});
	    push(@links,\@tmp);
      }
    }

    foreach my $link (@links) {

      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }
      #print "    ".join("=",@{$link})."\n";
      my %rowdata = (
        search_key_name => substr($link->[1],0,255),
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $biosequence_name,
        resource_type => 'Ecoli accession',
      );
      $self-> insertSearchKeyEntity( rowdata => \%rowdata);
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    #my $xx=<STDIN>;

  } # endfor each biosequence

  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);

  print "\n";

} # end buildEcoliKeyIndex



###############################################################################
# buildCelegansKeyIndex
###############################################################################
sub buildCelegansKeyIndex {
  my $METHOD = 'buildCelegansKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building Celegans key index...\n" if ($VERBOSE);

  my $biosequence_set_id = $args{biosequence_set_id }
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my %proteins;
  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );

  my %dbxref_ids = (
		    'WormSeq'  => 43,
		    'WormProt' => 11,
		    'WormGene' => 41,
		    'RefSeq'   => 39,
		    'SwissProt'=>  1,
		    'UniProt'  => 35,
		    'WormLocus'=> 42
		    );

  #### Load information from fasta file
  my $reference_file = "$reference_directory/wormpep215.fasta";
  print "Reading $reference_file\n" if ($VERBOSE);
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");

  #### Load data
  while (my $line = <INFILE>) {
      next unless ($line =~ s/^>//);
      next if ($line =~ /^rev_/);

      $line =~ s/[\r\n]//g;

      if ($line =~ s/^(\S+)//) {  # protein name
	  my $protein_name = $1;

	  $proteins{$protein_name}->{WormSeq} = $protein_name;

	  if ($line =~ s/(CE\d+)//) {
	      $proteins{$protein_name}->{WormProt} = $1;
	  }
	
	  if ($line =~ s/(WBGene\d+)//) {
	      $proteins{$protein_name}->{WormGene} = $1;
	  }

	  if ($line =~ s/(status:\S+)//) {
	      $proteins{$protein_name}->{status} = $1;
	  }

	  if ($line =~ s/protein_id:(\S+)//) {
	      $proteins{$protein_name}->{RefSeq} = $1;
	  }

	  if ($line =~ s/SW:(\S+)//) {
	      $proteins{$protein_name}->{SwissProt} = $1;
	  }

	  if ($line =~ s/TR:(\S+)//) {
	      $proteins{$protein_name}->{UniProt} = $1;
	  }

	  if ($line =~ s/locus:(\S+)//) {
	      $proteins{$protein_name}->{WormLocus} = $1;
	  }

	  # kill leading and trailing spaces
	  $line =~ s/^\s+//;
	  $line =~ s/\s+$//;

	  if ($line) {  # annotation
	      if (length($line) > 800) {
		  $line = substr($line,0,800)."....";
	      }
	      $proteins{$protein_name}->{'full_name'} = $line;
	  }

      } else {
	  print "WARNING: No protein name found for line '$line'\n";
      }
      
  }
  close(INFILE);


  #### Loop over all input rows processing information
  my $counter = 0;
  foreach my $biosequence_name (keys(%proteins)) {

    #### Debugging
    #print "protein=",$biosequence_name,"\n";
    #print "protein(combined)=",$proteins{$biosequence_name}->{combined},"\n";


    #### Build a list of protein links
    my @links;

    if ($biosequence_name) {
      my @tmp = ('Accession',$biosequence_name);
      push(@links,\@tmp);
    }

    foreach my $key ( qw (full_name WormSeq WormProt WormGene WormLocus SwissProt UniProt RefSeq status) ) {
	if (exists($proteins{$biosequence_name}->{$key})) {
	    my @tmp;

	    if (exists($dbxref_ids{$key})) {
		@tmp = ($key,$proteins{$biosequence_name}->{$key},$dbxref_ids{$key});

	    } else {
		@tmp = ($key,$proteins{$biosequence_name}->{$key});
	    }

	    push(@links,\@tmp);
	}
    }


    foreach my $link (@links) {
      #print "    ".join("=",@{$link})."\n";
      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }
      my %rowdata = (
        search_key_name => substr($link->[1],0,255),
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $biosequence_name,
        resource_type => 'Celegans accession',
      );
      $self->insertSearchKeyEntity( rowdata => \%rowdata);
    }


    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

    #my $xx=<STDIN>;

  } # endfor each biosequence
  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);

  print "\n";

} # end buildCelegansKeyIndex

sub buildHoneyBeeKeyIndex {
  my $METHOD = 'buildHoneyBeeIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  print "INFO[$METHOD]: Building HoneyBee key index...\n" if ($VERBOSE);

  my $biosequence_set_id = $args{biosequence_set_id }
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  my $reference_directory = $args{reference_directory}
    or die("ERROR[$METHOD]: Parameter reference_directory not passed");

  unless (-d $reference_directory) {
    die("ERROR[$METHOD]: '$reference_directory' is not a directory");
  }

  my $proteinList =  $self->getProteinList(
    biosequence_set_id => $biosequence_set_id,
  );

  my %proteins;
  my %dbxref_ids = (
    'RefSeq'       => 39,
    'BeeBase_gene' => 45,
    'NCBIProt'     => 12,
    'Gene Ontology' => 26,
  );


  my @keylist = ('BeeBase_gene',
                    'NCBIProt', 
                    'RefSeq', 
                    'BeeBase_protein',
                    'Full Name',
                    'Prediction ID',
                    'Prediction Description');

  ### read in all protein name from combined fasta file
  my $db = "/net/db/projects/PeptideAtlas/pipeline/output/HoneyBee_2009-12/DATA_FILES/Apis_mellifica.fasta";
  my %completeListProtein=();
  open (DB ,"<$db") or die " cannot open $db\n";
  while (my $line = <DB>) {
    chomp $line;
    next if($line !~ />/);
    $line =~ s/>//;
    next if ($line =~ /DECOY/);
    my @elm = split(/\s+/, $line);
    $completeListProtein{$elm[0]} =1;;
  }


  ### Load information from blast2go output file blast2go_mapping_14072009.txt
  my $blast2go_file =  "$reference_directory/blast2go_mapping_14072009.txt";                  
  print "Reading $blast2go_file\n" if ($VERBOSE);
  open(BGO,$blast2go_file)
    or die("ERROR[$METHOD]: Unable to open file '$blast2go_file'");
  #### Load data
  while (my $line = <BGO>) {
    chomp $line;
    my $prot='';
    my $gos = '';
    $line =~ s/\s+$//;
    next if ($line =~/version/);
    $line =~ /(\S+)\s+(.*)/;
    $prot = $1;
    $gos  = $2;
    if($prot=~/^gi/){$prot =~ s/\_/|/;}
    $proteins{$prot}->{'Gene_Ontology'} = $gos;
    #if(not defined $completeListProtein{$prot}){$completeListProtein{$prot} = 1;}
    print "$prot $gos\n" if ($VERBOSE);
  }

  my $reference_file = "$reference_directory/alias.txt";
  print "Reading $reference_file\n" if ($VERBOSE);
  open(INFILE,$reference_file)
    or die("ERROR[$METHOD]: Unable to open file '$reference_file'");

  #### Load data
  while (my $line = <INFILE>) {
    chomp $line;
    my @elm = split("\t", $line);
    my $protein_name = $elm[0];
    if($protein_name =~ /^gnl\|Amel\|(.*)/){ $protein_name = $1;}
    foreach (@elm){
      if(/(GB\d+)\D+/){
        my $gene = $1;
        if(/GB.*\-\w+/){
          $proteins{$protein_name}->{'BeeBase_protein'}= $_;
        }
        else{
          $proteins{$protein_name}->{'BeeBase_gene'}= $gene;
        }
      }
      if(/gi\|\d+/){
        $proteins{$protein_name}->{'NCBIProt'}= $_;
      }
      if(/lcl\|/){
        $proteins{$protein_name}->{'Prediction ID'}= $_;
      }
      if(/Gene predicted by Gnomon/){
        $proteins{$protein_name}->{'Prediction Description'}= $_;
      }
      if(/XP\_\d+\.\d+/){
        $proteins{$protein_name}->{'RefSeq'}= $_;
      }
    
   }        
 }
  close(INFILE);

  #### Loop over all input rows processing information
  my $counter = 0;
  my $cc =0;
  foreach my $biosequence_name (keys(%completeListProtein)) {

    #### Debugging
    #print "protein=",$biosequence_name,"\n";
    #print "protein(combined)=",$proteins{$biosequence_name}->{combined},"\n";

    #### Build a list of protein links
    my @links;

    my $shortname = $biosequence_name;
    if($biosequence_name =~ /^gnl\|Amel\|(.*)/){ $shortname = $1;}
    elsif($biosequence_name =~ /^gi\|(\d+)\|.*/){ $shortname = "gi|$1";}
    foreach my $key ( @keylist) {
      if (exists($proteins{$shortname}->{$key})) {
        my @tmp;
        if (exists($dbxref_ids{$key})) {
	       @tmp = ($key,$proteins{$shortname}->{$key},$dbxref_ids{$key});
	    } else {
          @tmp = ($key,$proteins{$shortname}->{$key});
	    }
 	      push(@links,\@tmp);
      }
    }
       
    if($proteins{$shortname}->{'Gene_Ontology'}){
      my @list = splitEntities(list=>$proteins{$shortname}->{'Gene_Ontology'},delimiter=>',');
      foreach my $term(@list){
        my $numzero = 7 - length($term);
        $term = 'GO:'.0 x $numzero.$term;
        my @tmp = ('Gene Ontology',$term,$dbxref_ids{'Gene Ontology'});
        push(@links, \@tmp);
      }
    }  
    foreach my $link (@links) {

      if(defined $proteinList->{$link->[1]}){
        $proteinList->{$link->[1]} = 1;
      }
      my %rowdata = (
        search_key_name => $link->[1],
        search_key_type => $link->[0],
        search_key_dbxref_id => $link->[2],
        resource_name => $biosequence_name,
        resource_type => 'HoneyBee accession',
      );
      $self->insertSearchKeyEntity( rowdata => \%rowdata);
    }
    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

  } # endfor each biosequence

  $self -> checkCompleteness(proteinList=> $proteinList,
                             count      => $counter);


} # end buildHoneyBeeKeyIndex
sub insertPeptideSearchKey {

  my $SUB = 'insertPeptideSearchKey';
  my $self = shift || die ("self not passed");
  my %args = @_;
  my $rowdata = $args{rowdata};

	my $search_key_name = $rowdata->{search_key_name};
	my $search_key_type = $rowdata->{search_key_type};
	my $search_key_dbxref_id = $rowdata->{search_key_dbxref_id};
	my $organism_id = $rowdata->{organism_id};
	my $atlas_build_id = $rowdata->{atlas_build_id};
	my $resource_name = $rowdata->{resource_name};
	my $resource_type = $rowdata->{resource_type};
	my $resource_url = $rowdata->{resource_url};
	my $resource_n_matches = $rowdata->{resource_n_matches};
	my $protein_alias_master = $rowdata->{protein_alias_master} || $resource_name;


  $search_key_name =~ s/'/''/g; 
  my $sql = qq~
     SELECT SEARCH_KEY_ID  
     FROM $TBAT_SEARCH_KEY_ENTITY
     WHERE RESOURCE_NAME = '$resource_name'
       AND SEARCH_KEY_NAME = '$search_key_name'
  ~;
  #print "$sql\n"; 
  my @rows = $sbeams->selectOneColumn($sql);
  my %rowdata=();
  if(! @rows){
		  %rowdata = (
			search_key_name => $search_key_name, 
			search_key_type => $search_key_type,
			search_key_dbxref_id => $search_key_dbxref_id,
			resource_name => $resource_name,
			resource_type => $resource_type,
			protein_alias_master => $protein_alias_master,
		);

		$sbeams->updateOrInsertRow(
			insert => 1,
			table_name => "$TBAT_SEARCH_KEY_ENTITY",
			rowdata_ref => \%rowdata,
			verbose=>$VERBOSE,
			testonly=>$TESTONLY,
		);
  }

  $sql = qq~
     SELECT RESOURCE_NAME
     FROM $TBAT_SEARCH_KEY_LINK
     WHERE RESOURCE_NAME = '$resource_name'
       AND ATLAS_BUILD_ID = $atlas_build_id
  ~;

  @rows = $sbeams->selectOneColumn($sql);
  %rowdata=();
  if(! @rows){
		%rowdata = (
			organism_id => $organism_id, 
			atlas_build_id => $atlas_build_id,
			resource_name => $resource_name,
			resource_url => $resource_url,
			resource_n_matches => $resource_n_matches
		);

		$sbeams->updateOrInsertRow(
			insert => 1,
			table_name => "$TBAT_SEARCH_KEY_LINK",
			rowdata_ref => \%rowdata,
			verbose=>$VERBOSE,
			testonly=>$TESTONLY,
		);
  }
}

###############################################################################
# splitEntities: Split a semi-colon separated list of items into an array
###############################################################################
sub splitEntities {
  my $SUB = 'splitEntities';
  my %args = @_;

  my $list = $args{list};
  my $delimiter = $args{delimiter} || ';';

  my @tmp_IDS = split(/$delimiter/,$list);
  my @IDS;
  foreach my $ID ( @tmp_IDS ) {
    next if ($ID =~ /^\s*$/);
    push(@IDS,$ID);
  }

  return(@IDS);

} # end splitEntities



###############################################################################
# buildPeptideKeyIndex
###############################################################################
sub buildPeptideKeyIndex {
  my $METHOD = 'buildPeptideKeyIndex';
  my $self = shift || die ("self not passed");
  my %args = @_;

  my $organism_id = $args{organism_id}
    or die("ERROR[$METHOD]: Parameter organism_id not passed");

  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  print "INFO[$METHOD]: Building Peptide key index...\n" if ($VERBOSE);

  #### Get all the peptides for this build
  my $sql = qq~
       SELECT peptide_accession,peptide_sequence,n_observations
         FROM $TBAT_PEPTIDE P
         JOIN $TBAT_PEPTIDE_INSTANCE PI ON (P.peptide_id = PI.peptide_id)
        WHERE PI.atlas_build_id = '$atlas_build_id'
  ~;
  my @peptides = $sbeams->selectSeveralColumns($sql);

  my $counter = 0;

  #### Loop over each one, inserting records for both the accession numbers
  #### and the sequences
  foreach my $peptide ( @peptides ) {

    #### Register an entry for the PAp accession number
    my %rowdata = (
      search_key_name => $peptide->[0],
      search_key_type => 'PeptideAtlas',
      organism_id => $organism_id,
      atlas_build_id => $atlas_build_id,
      resource_name => $peptide->[0],
      resource_type => 'PeptideAtlas peptide',
      resource_url => "GetPeptide?atlas_build_id=$atlas_build_id&searchWithinThis=Peptide+Name&searchForThis=$peptide->[0]&action=QUERY",
      resource_n_matches => $peptide->[2],
    );
    $self->insertPeptideSearchKey( rowdata => \%rowdata);

    #### Register an entry for the peptide sequence
    %rowdata = (
      search_key_name => $peptide->[1],
      search_key_type => 'peptide sequence',
      organism_id => $organism_id,
      atlas_build_id => $atlas_build_id,
      resource_name => $peptide->[0],
      resource_type => 'PeptideAtlas peptide',
      resource_url => "GetPeptide?atlas_build_id=$atlas_build_id&searchWithinThis=Peptide+Name&searchForThis=$peptide->[0]&action=QUERY",
      resource_n_matches => $peptide->[2],
    );
    $self->insertPeptideSearchKey ( rowdata => \%rowdata);
    $counter++;
    print "$counter... " if ($counter/100 eq int($counter/100));

  }

  return(1);

} # end buildPeptideKeyIndex



###############################################################################
# getNProteinHits
###############################################################################
sub getNProteinHits {
  my $METHOD = 'getNProteinHits';
  my $self = shift || die ("self not passed");
  my %args = @_;

  my $organism_id = $args{organism_id}
    or die("ERROR[$METHOD]: Parameter organism_id not passed");

  my $atlas_build_id = $args{atlas_build_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  #### Get all the peptides in the database, regardless of build
  my $sql = qq~
       SELECT biosequence_name,SUM(n_observations) AS N_obs
         FROM $TBAT_PEPTIDE_INSTANCE PI
         JOIN $TBAT_ATLAS_BUILD AB ON (AB.atlas_build_id = PI.atlas_build_id)
         JOIN $TBAT_PEPTIDE_MAPPING PIM
              ON (PIM.peptide_instance_id = PI.peptide_instance_id)
         JOIN $TBAT_BIOSEQUENCE B
              ON (B.biosequence_id = PIM.matched_biosequence_id)
        WHERE AB.atlas_build_id = '$atlas_build_id'
        GROUP BY biosequence_name
  ~;
  my %proteins = $sbeams->selectTwoColumnHash($sql);

  return(\%proteins);

} # end getNProteinHits


###############################################################################
# getProteinList
###############################################################################
sub getProteinList {
  my $METHOD = 'getProteinList';
  my $self = shift || die ("self not passed");
  my %args = @_;
  my $sbeams = $self->getSBEAMS();

  my $biosequence_set_id = $args{biosequence_set_id}
    or die("ERROR[$METHOD]: Parameter atlas_build_id not passed");

  #### Get all the protein in the biosequence set
  my $sql = qq~
         SELECT B.biosequence_name
         FROM $TBAT_BIOSEQUENCE B
         WHERE B.biosequence_set_id= $biosequence_set_id
  ~;

  my @proteins = $sbeams->selectOneColumn($sql);
  my %proteins = ();
  foreach (@proteins){
   next if($_ =~ /DECOY/);
   $proteins{$_} = 0;
  }
  return(\%proteins);

} # end getProteinList

###############################################################################
# getProteinSynonyms
###############################################################################
sub getProteinSynonyms {
  my $METHOD = 'getProteinSynonyms';
  my $self = shift || die ("self not passed");
  my %args = @_;

  my $resource_name = $args{resource_name} || return;

  #### Get all the search_key_name in the database, regardless of build
  my $sql = qq~
			( SELECT SEARCH_KEY_NAME,SEARCH_KEY_TYPE,ACCESSOR,ACCESSOR_SUFFIX
				 FROM $TBAT_SEARCH_KEY_ENTITY SKE
				 LEFT JOIN $TBBL_DBXREF D ON ( SKE.SEARCH_KEY_DBXREF_ID = D.DBXREF_ID )
				 WHERE PROTEIN_ALIAS_MASTER in (
				   SELECT TOP 1 SKE2.PROTEIN_ALIAS_MASTER
				   FROM $TBAT_SEARCH_KEY_ENTITY SKE2
				   WHERE SKE2.RESOURCE_NAME = '$resource_name'
           AND SKE2.PROTEIN_ALIAS_MASTER != '$resource_name'
			   ) and PROTEIN_ALIAS_MASTER != '' 
			) 
		  UNION 
		  (	SELECT SKE3.SEARCH_KEY_NAME,SKE3.SEARCH_KEY_TYPE,ACCESSOR,ACCESSOR_SUFFIX
				FROM $TBAT_SEARCH_KEY_ENTITY SKE3
				LEFT JOIN $TBBL_DBXREF D ON ( SKE3.SEARCH_KEY_DBXREF_ID = D.DBXREF_ID )
			  WHERE SKE3.RESOURCE_NAME = '$resource_name' 
        AND SKE3.PROTEIN_ALIAS_MASTER = '$resource_name'
		 )
 ~;
  my @synonyms = $sbeams->selectSeveralColumns($sql);

  return @synonyms;

} # end getProteinSynonyms


sub checkAtlasBuild {
  my $self = shift;
  my %args = @_;
  die "Missing required argument build_id" if !$args{build_id};
  
  my $sbeams = $self->getSBEAMS();
  my ($cnt) = $sbeams->selectrow_array( <<"  END" );
  SELECT COUNT(*) 
  FROM $TBAT_ATLAS_BUILD 
  WHERE atlas_build_id = $args{build_id}
  AND record_status = 'N'
  END
  return $cnt;
}

sub get_organism_name{

  my $self = shift;
  my %args = @_;
  die "Missing required argument biosequence_set_id" if !$args{biosequence_set_id};
  my $biosequence_set_id = $args{biosequence_set_id};
  my $sbeams = $self->getSBEAMS();

  my $sql = qq~
    SELECT O.ORGANISM_NAME
    FROM $TBAT_BIOSEQUENCE_SET BS, $TB_ORGANISM O
    WHERE BS.ORGANISM_ID= O.ORGANISM_ID
    AND BS.BIOSEQUENCE_SET_ID = $biosequence_set_id
  ~;

  my ( $name ) = $sbeams->selectrow_array($sql);
  return $name;

}



###############################################################################
=head1 BUGS

Please send bug reports to SBEAMS-devel@lists.sourceforge.net

=head1 AUTHOR

Eric W. Deutsch (edeutsch@systemsbiology.org)

=head1 SEE ALSO

perl(1).

=cut
###############################################################################
1;

__END__
###############################################################################
###############################################################################

###############################################################################
