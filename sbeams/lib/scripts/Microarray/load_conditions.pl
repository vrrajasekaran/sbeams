#!/usr/local/bin/perl -w

###############################################################################
# Program     : load_conditions.pl
# Author      : Michael Johnson <mjohnson@systemsbiology.org>
#
# Description : This script goes to the appropriate directory to search for
#               .sig/.merge files and subsequently loads the condition
#               and corresponding data into SBEAMS.  Sorry for the horrible use
#               of global variables!
#
# Mappings    : reporter_name - Hs:GENE_NAME, Mm:operon_oligo_id, Sc:ORF
#               full_name - Hs:gene_name, Mm:gene_name, Sc:SYM
#               canonical_name - Hs:external_id, Mm:external_id, Sc:ORF
#               common_name - Hs:gene_symbol, Mm:gene_symbol, Sc:SYM
#               gene_name - Hs:GENE_NAME, Mm:GENE_NAME, Sc:SYM
#
# Notes       : A sample column_map file is:
#
# #### SBEAMS gene_expression bulk loader column mapping file
#
# #### File name of the source data.  Either absolute or relative to the
# ####   location of the mapfile
# mapped_file=prostate_vs_bladder.clone
#
# condition=prostate_vs_bladder
#
# delimiter = \t
#
# #### List of <database_column_name>=<file_column_number>, 0 indexed.  e.g.:
# #### reporter_name=0
# reporter_name=0
# full_name=45
# canonical_name=40
# common_name=46
# gene_name=0
# external_identifier=40
# log10_ratio=4
# log10_std_deviation = 5
# lambda = 26
# mu_X = 24
# mu_Y = 25
###############################################################################


###############################################################################
# Generic SBEAMS setup for all the needed modules and objects
###############################################################################
use strict;
use Text::Tabs;
use Getopt::Long;
use FindBin;
use Cwd;

use lib "$FindBin::Bin/../../perl";
use vars qw ($sbeams $q
             $PROG_NAME $USAGE %OPTIONS 
			 $VERBOSE $QUIET $DEBUG 
			 $DATABASE $TESTONLY $PROJECT_ID 
			 $CURRENT_CONTACT_ID $CURRENT_USERNAME 
			 $SBEAMS_SUBDIR
            );


#### Set up SBEAMS core module
use SBEAMS::Connection;
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;

use SBEAMS::Microarray;
use SBEAMS::Microarray::Settings;
use SBEAMS::Microarray::Tables;
use SBEAMS::Microarray::TableInfo;


$sbeams = new SBEAMS::Connection;
$sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);

use CGI;
$q = CGI->new();

###############################################################################
# Set program name and usage banner for command like use
###############################################################################
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
$PROG_NAME is used to load conditions into SBEAMS. 

UPDATED VERSION!

THIS SHOULD BE CALLED FROM WITHIN THE DIRECTORY THAT CONTAINS
THE DATA FILES!!

Usage: $PROG_NAME --project_id n [OPTIONS]
Options:
    --verbose <num>    Set verbosity level.  Default is 0
    --quiet            Set flag to print nothing at all except errors
    --debug n          Set debug flag
    --project_id <num> Set the SBEAMS project ID. This is required.
    --set_tag <name>   Determines which biosequence set to use when populating
                       the gene_expression table (not fully functional)
    --map              Looks/loads according to column_map files
    --testonly         Information in the database is not altered
EOU

#### Process options
unless (GetOptions(\%OPTIONS,
		   "verbose:i",
		   "quiet",
		   "debug:i",
		   "project_id=s",
		   "file_name:s",
		   "set_tag:s",
		   "map",
		   "testonly")) {
  print "$USAGE";
  exit;
}

$PROJECT_ID = $OPTIONS{project_id};
$VERBOSE    = $OPTIONS{verbose} || 0;
$QUIET      = $OPTIONS{quiet};
$DEBUG      = $OPTIONS{debug};
$TESTONLY   = $OPTIONS{testonly};

if ($DEBUG) {
  print "Options settings:\n";
  print "  VERBOSE = $VERBOSE\n";
  print "  QUIET = $OPTIONS{quiet}\n";
  print "  DEBUG = $OPTIONS{debug}\n";
  print "  PROJECT_ID = $OPTIONS{project_id}\n";
  print "  FILE_NAME = $OPTIONS{file_name}\n";
  print "  TESTONLY = $OPTIONS{testonly}\n";
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

  
#### Try to determine which module we want to affect
  my $module = $sbeams->getSBEAMS_SUBDIR();
  my $work_group = 'unknown';
  if ($module eq 'Microarray') {
    $work_group = "Microarray_admin";
    $DATABASE = $DBPREFIX{$module};
  }
  if ($module eq 'Proteomics') {
    $work_group = "${module}_admin";
    $DATABASE = $DBPREFIX{$module};
  }
  if ($module eq 'Biosap') {
    $work_group = "Biosap";
    $DATABASE = $DBPREFIX{$module};
  }
  if ($module eq 'SNP') {
    $work_group = "SNP";
    $DATABASE = $DBPREFIX{$module};
  }


#### Do the SBEAMS authentication and exit if a username is not returned
  exit unless ($CURRENT_USERNAME = $sbeams->Authenticate(
							work_group=>$work_group,
	 ));

## Presently, force module to be microarray and work_group to be Microarray_admin
  if ($module ne 'Microarray') {
	print "WARNING: Module was not Microarray.  Resetting module to Microarray\n";
	$work_group = "Microarray_admin";
	$DATABASE = $DBPREFIX{$module};
	}


  $sbeams->printPageHeader() unless ($QUIET);
  handleRequest();
  $sbeams->printPageFooter() unless ($QUIET);

} # end main



###############################################################################
# handleRequest
#
# Handles the core functionality of this script
###############################################################################
sub handleRequest {
  my %args = @_;
  my $SUB_NAME = "handleRequest";

#### Define standard variables
  my ($sql);
  my (@rows,$condition_files);
  my (%final_hash);
	
#### Set the command-line options
  my $directory = cwd(); #NOTE: this is meant to be called from within project directory
#  my $directory = "/net/arrays/Pipeline/output/project_id/$PROJECT_ID";
  my $file_name = $OPTIONS{'file_name'};
  my $set_tag = $OPTIONS{'set_tag'};
  my $search_for_map = $OPTIONS{'map'} || "false";

  unless ($PROJECT_ID) {
	print "ERROR: project_id must be specified!\n";
	print $USAGE;
	return;
  }

#### Print out the header
  unless ($QUIET) {
    $sbeams->printUserContext();
    print "\n";
  }

  
## If set_tag is set, get biosequences
  if ($set_tag) {
	$sql = qq~
	  SELECT BS.biosequence_id, BS.biosequence_name, BS.biosequence_gene_name
	  FROM $TBMA_BIOSEQUENCE BS
	  LEFT JOIN $TBMA_BIOSEQUENCE_SET BSS ON (BSS.biosequence_set_id = BS.biosequence_set_id)
	  WHERE BSS.set_tag = '$set_tag'
	  and BS.record_status != 'D'
	  ~;
	@rows = $sbeams->selectHashArray($sql);

## make the final hash
	foreach my $temp_row (@rows) {
	  my %temp_hash = %{$temp_row};
	  $final_hash{$temp_hash{'biosequence_gene_name'}} = $temp_hash{'biosequence_id'};
	  $final_hash{$temp_hash{'biosequence_name'}} = $temp_hash{'biosequence_id'};
	}      
  }
  

## Deal with files
  if ($file_name) {
	unless(-r $file_name && -e $file_name) {
	  print "[ERROR] File: $file_name can not be read! Please check this out and re-run\n";
	}
  }
  
  if ($search_for_map ne "false"){
    print "#loading column_map files\n";
    $condition_files = loadColumnMapFile(directory=>$directory,
					 loaded_files=>$condition_files,
					 bs_hash_ref=>\%final_hash);
  }else {
    print "# Attempting to load files\n";
    $condition_files = loadFiles(file_name=>$file_name,
								 directory=>$directory,
								 condition_ref=>$condition_files,
								 bs_hash_ref=>\%final_hash);
  }

  return;
}

###############################################################################
# getProcessedDate
#
# Given a file name, the associated timestamp is returned
###############################################################################
sub getProcessedDate {
    my %args= @_;
    my $SUB_NAME="getProcessedDate";

    my $file = $args{'file'};

## Get the last modification date from this file
    my @stats = stat($file);
    my $mtime = $stats[9];
    my $source_file_date;
    if ($mtime) {
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($mtime);
	$source_file_date = sprintf("%d-%d-%d %d:%d:%d",
				    1900+$year,$mon+1,$mday,$hour,$min,$sec);
	if ($VERBOSE > 0){print "INFO: source_file_date is '$source_file_date'\n";}
    }else {
	$source_file_date = "CURRENT_TIMESTAMP";
	print "WARNING: Unable to determine the source_file_date for ".
	    "'$file'.\n";
    }
    return $source_file_date;
}


###############################################################################
# insertCondition
#
# Given a condition name (and condition_id, if available), a record will be 
# INSERTed or UPDATEd in the condition table
###############################################################################
sub insertCondition {
    my %args = @_;
    my $SUB_NAME = "insertCondition";

## Define local variables
    my $condition = $args{'condition'};
    my $condition_id = $args{'condition_id'};
    my $processed_date = $args{'processed_date'};
    my (%rowdata, $rowdata_ref,$pk);
    my ($insert, $update) = 0;

    ($condition_id) ? $update = 1 : $insert = 1;

    if ($insert + $update != 1){
	die "ERROR[$SUB_NAME]:You need to set insert OR update to 1\n";
    }
    if($update == 1 && !defined($condition_id)){
	die "ERROR[$SUB_NAME]:UPDATE requires update and condition_id flag\n";
    }
    
    if ($insert == 1) {
	$rowdata{'condition_name'} = $condition;
	$rowdata{'project_id'} = $PROJECT_ID;
	$rowdata{'processed_date'} = $processed_date;
	$rowdata_ref = \%rowdata;
	$pk = $sbeams->updateOrInsertRow(table_name=>$TBMA_CONDITION,
									 rowdata_ref=>$rowdata_ref,
									 return_PK=>1,
									 verbose=>$VERBOSE,
									 testonly=>$TESTONLY,
									 insert=>1,
									 add_audit_parameters=>1);
  }elsif ($update == 1) {
	$rowdata{'condition_name'} = $condition;
	$rowdata{'project_id'} = $PROJECT_ID;
	$rowdata{'processed_Date'} = $processed_date;
	$rowdata_ref = \%rowdata;
	$pk  = $sbeams->updateOrInsertRow(table_name=>$TBMA_CONDITION,
									  rowdata_ref=>$rowdata_ref,
									  return_PK=>1,
									  verbose=>$VERBOSE,
									  testonly=>$TESTONLY,
									  update=>1,
									  PK=>'condition_id',
									  PK_value=>$condition_id,
									  add_audit_parameters=>1);
    }
    return $pk;
}	


###############################################################################
# insertGeneExpression
###############################################################################
sub insertGeneExpression {
  my %args = @_;
  my $SUB_NAME = "insertGeneExpression";

  ## Define local variables
  my $condition_id = $args{'condition_id'} 
  || die "ERROR[$SUB_NAME]: condition_id must be set\n";
  my $source_file = $args{'source_file'};
  my $id_hash_ref = $args{'id_hash'};
  my $set_tag = $OPTIONS{'set_tag'};
  my $column_map_ref = $args{'column_map_ref'} 
  || die "ERROR[$SUB_NAME]:column mapping reference needs to be set\n";
  my %column_map = %{$column_map_ref};
  my $delimiter = $args{'delimiter'} || "\t";

  #### Deutsch changed.  What if the user asked from 0?  This breaks.
  #my $skip_lines = $args{'skip_lines'} || 1;
  my $skip_lines = $args{'skip_lines'};
  $skip_lines = 1 unless (defined($skip_lines));

  ## Define standard variables
  my $CURRENT_CONTACT_ID = $sbeams->getCurrent_contact_id();
  my ($sql, @rows);

  ## See if there are gene_expression entries with the specified id. DELETE, if so.
  $sql = qq~
      SELECT gene_expression_id
      FROM $TBMA_GENE_EXPRESSION
      WHERE condition_id = '$condition_id'
      ~;
  @rows = $sbeams->selectOneColumn($sql);

  if (@rows) {
    if ($VERBOSE > 0) {
      print "\nRecords exist for this condition.  Will DELETE them, then re-INSERT\n";
    }
    $sql = "DELETE FROM $TBMA_GENE_EXPRESSION WHERE condition_id = '$condition_id'";
    $sbeams->executeSQL($sql);
  }


  ## Define Transform Map
  my $full_name_column;
  my $common_name_column;
  foreach my $key (keys %column_map) {
    if ($column_map{$key} eq "full_name") {
      $full_name_column = $key;
    }elsif($column_map{$key} eq "common_name") {
      $common_name_column = $key;
    }
  }

  my %transform_map = ('1000'=>sub{return $condition_id;},
					   $full_name_column=>sub{return substr shift @_ ,0,1024;}, 
					   $common_name_column=>sub{return substr shift @_,0,255;},
					   );

  ## For debugging purposes, we can print out the column mapping
  if ($VERBOSE >= 0) {
    print "\n Column Mapping for $source_file:\n";
    while ( (my $k,my $v) = each %column_map ) {
      if (ref($v) eq "ARRAY"){
	foreach my $t (@{$v}) {
	  print "$k => $t\n";
        }
      }else {
	print "$k => $v\n";
      }
    }
  }
  
  if ($TESTONLY) {
    print "\n$TESTONLY- TEST ONLY MODE\n";
  }
  print "\nTransferring $source_file -> gene_expression";
  $sbeams->transferTable(source_file=>$source_file,
						 delimiter=>$delimiter,
						 skip_lines=>$skip_lines,
						 dest_PK_name=>'gene_expression_id',
						 dest_conn=>$sbeams,
						 column_map_ref=>\%column_map,
						 transform_map_ref=>\%transform_map,
						 table_name=>$TBMA_GENE_EXPRESSION,
						 insert=>1,
						 verbose=>$VERBOSE,
						 testonly=>$TESTONLY,
						 );
    
  ## Insert biosequences, if set_tag was specified
  if ($set_tag && $id_hash_ref) {
    my %id_hash = %{$id_hash_ref};
    $sql = qq~
	SELECT GE.gene_name, GE.second_name, GE.gene_expression_id
	FROM $TBMA_GENE_EXPRESSION GE
	WHERE GE.condition_id = '$condition_id'
	~;
    @rows = $sbeams->selectHashArray($sql);

    my %ge_hash;

    ## make the final hash
    foreach my $temp_row (@rows) {
      my %temp_hash = %{$temp_row};
      $ge_hash{$temp_hash{'gene_name'}} = $temp_hash{'gene_expression_id'};
      $ge_hash{$temp_hash{'canonical_name'}} = $temp_hash{'gene_expression_id'};
    }

    ## For each gene_expression record, try to find a corresponding biosequence
    while ( my($key,$value) = each %ge_hash ){
      my $result =  $id_hash{$key};
      if ($result){
	if ($VERBOSE > 0) {
	  print "UPDATEing $key\n";
        }
	my $ge_id = $value;
	my %rowdata;
	$rowdata{'biosequence_id'} = $result;
	my $rowdata_ref = \%rowdata;
	$sbeams->updateOrInsertRow(table_name=>$TBMA_GENE_EXPRESSION,
				   rowdata_ref=>$rowdata_ref,
				   return_PK=>0,
				   verbose=>$VERBOSE,
				   testonly=>$TESTONLY,
				   update=>1,
				   PK=>'gene_expression_id',
				   PK_value=>$ge_id);
      }
    }
    close(INFILE);
  }
}

###############################################################################
# conditionAlreadyLoaded
#
# This sub determines whether a file has already been loaded into the
# condition/gene_expression tables
###############################################################################
sub conditionAlreadyLoaded {
  my %args = @_;
  my $SUB_NAME = "conditionAlreadyLoaded";

  ## Define local variables
  my $file = $args{'file'}
  || die "\nERROR[$SUB_NAME]:file needs to be specified\n";
  my $file_ref = $args{'file_ref'}
  || return "false";
  my @files = @{$file_ref};

  ## See if the file exists in the list of already-loaded files
  foreach my $test_file (@files) {
    if ($file eq $test_file) {
      return "true";
    }
  }
  return "false";
}



###############################################################################
# loadColumnMapFile
#
# Loads data via the column_map file
#
# Each column_map file should contain the name of the mapped file on the first 
# line, followed by a list of the mapping, separated by returns.  If the 
# condition is not specified in the file, then set the condition to be the 
# column_map file's name.
###############################################################################
sub loadColumnMapFile {
  my %args = @_;
  my $SUB_NAME = "loadColumnMapFile";
  my $condition_ref = $args{'loaded_files'};
  my $directory = $args{'directory'}
  || die "ERROR[$SUB_NAME]:directory is required\n";
  my $bs_hash_ref = $args{'bs_hash_ref'};
  my $delimiter = "\t";
  my $skip_lines;
  my @condition_files;
  my ($mapped_file, $condition, $condition_id, $processed_date);


  my @map_files = glob ("$directory/*\.column_map");
  my $map_count = @map_files;
  if ($map_count >= 1) {
    if ($VERBOSE > 0) {
	print "The following column_map files were found:\n";
	foreach my $temp_name (@map_files){
	    print "$temp_name\n";
        }
    }
  }else {return \@condition_files;}

  foreach my $map_file (@map_files) {
    if ($condition_ref) {
      @condition_files = @{$condition_ref};
    }

    ## Read in column_map file
    my %column_mapping;
    if (open (MAP_FILE, "$map_file")){
      while (<MAP_FILE>) {
	next if (/^\#/ || /^\s$/);

	# If file path starts with '/' it's the full path
	# If file is just a name, it's in the current dir.
	if (/mapped.file\s*\=\s*\/(.*)/) {
	  $mapped_file = "/$1";
#	  print "file path is $mapped_file\n";
        }elsif (/mapped.file\s*\=\s*(.*)/) {
	  $mapped_file = "$directory/$1";
#	  print "file path is $mapped_file\n";
	}elsif (/delimiter\s*\=\s*(.*)/) {
	  $delimiter = $1;

	  # Quick hack to resolve tab interpolation
	  my $tab = '\t';
	  my $space = '\s';
	  if ($delimiter eq $tab) {$delimiter = "\t";}
	  if ($delimiter eq $space) {$delimiter = "\s";}

	}elsif (/condition\s*\=\s*(.*)/) {
	  $condition = $1;
	}elsif (/skip_lines\s*\=\s*(.*)/) {
	  $skip_lines = $1;
        }elsif (/(\w+)\s*\=\s*(\d+)/) {
	  if (ref($column_mapping{$2}) eq "ARRAY") {
	    push @{$column_mapping{$2}}, $1;
	  }elsif (defined($column_mapping{$2})) {
	    my @mapped_array = ($column_mapping{$2}, $1);
	    $column_mapping{$2} = \@mapped_array;
	  }else {
	    $column_mapping{$2} = $1;
	  }
        }else {
	  #print "nothing on this line\n";
	}
      }
      close (MAP_FILE);

      $column_mapping{'1000'} = 'condition_id';

      if (!defined($condition)) {
	$map_file =~ s(^.*/)();
	$map_file =~/(.*)\.column_map$/;
	$condition = $1;
      }

      if (!defined($mapped_file)) {
	print "No file found indicated for mapping.\n";
	$mapped_file = $map_file;
	$mapped_file =~ s/\.column_map/\.sig/;
	print "Will try to use $mapped_file\n";
      }

      $processed_date = getProcessedDate(file=>"$mapped_file");
      $condition_id = getConditionID(condition=>$condition);

   ## INSERT/UPDATE the condition
      if (!defined($condition_id)) {
	print "\n->INSERTing condition $condition\n";
      }else {
	print "\n->UPDATEing condition $condition\n";
      }

      $condition_id = insertCondition(processed_date=>$processed_date,
				      condition=>$condition,
				      condition_id=>$condition_id);
	
   ##  Insert the gene_expression data!
      insertGeneExpression(condition_id=>$condition_id,
			   column_map_ref=>\%column_mapping,
			   source_file=>"$mapped_file",
			   id_hash=>$bs_hash_ref,
			   delimiter=>$delimiter,
			   skip_lines=>$skip_lines,
			  );

      push (@condition_files, $map_file);
    }else{
      print "ERROR[$SUB_NAME]:Could not open $map_file\n";
    }
  }     
      return \@condition_files;
}


###############################################################################
# loadFiles
###############################################################################
sub loadFiles {
  my %args = @_;
  my $SUB_NAME =  "loadFiles";

  ## Define local variables
  my $file_name = $args{'file_name'};
  my $condition_ref = $args{'condition_ref'};
  my $directory = $args{'directory'}
  || die "\nERROR[$SUB_NAME]: need directory\n";
  my $bs_hash_ref = $args{'bs_hash_ref'};
  my $search_string;

  ## Local Variables
  my ($search_file, $condition, $condition_id, $processed_date);
  my $new_conditions = 0;

  ## Search for files ending with $search_string
  my @search_files;
  foreach my $search ("clone","sig","merge"){
	$search_string = $search;
	@search_files = glob("$directory/*\.$search_string");
	last if (@search_files);
  }

  if (@search_files) {
	print scalar(@search_files) ." files found using $search_string\n";
  }else {
	print "ERROR: load_conditions can't find a valid type of file to load within $directory\n";
	exit;
  }

  foreach my $search_file (@search_files) {

	## Determine condition    
    $search_file =~ s(^.*/)();
    $search_file =~ /(.*)\.$search_string$/;
    $condition = $1;

	print "Attempting to load Condition $1\n";

    ## See if condition has already been loaded during the running of this script
    ## If it hasn't been loaded, fire it up.
    if (conditionAlreadyLoaded(file=>$search_file,
							   file_ref=>$condition_ref) eq "true") {
      print "Condtion \'$condition\' has already been loaded.\n";
    }else {
      push (@{$condition_ref}, $search_file);
      $new_conditions++;
      $processed_date = getProcessedDate(file=>"$directory/$search_file");
      $condition_id = getConditionID(condition=>$condition);
      if ($VERBOSE > 0 ) {
		print "condition_id for condition \'$condition\' is $condition_id.\n";
      }
	    
      ## INSERT/UPDATE the condition
      if (!defined($condition_id)) {
		print "\n->INSERTing condition $condition\n";
      }else {
		print "\n->UPDATEing condition $condition\n";
      }
      $condition_id = insertCondition(processed_date=>$processed_date,
									  condition=>$condition,
									  condition_id=>$condition_id);
	
      ## Find out how the columns map to fields in the database
      my $column_map_ref= getColumnMapping(source_file=>"$directory/$search_file");


#	  if ($column_map_ref) {
#		print "Column_mapping:\n";
#		my %temp = %{$column_map_ref};
#		foreach my $key (keys %temp ) {
#		  print "$key => $temp{$key}\n";
#		}
#		return;
#	  }
      
      ##  Insert the gene_expression data!
      insertGeneExpression(condition_id=>$condition_id,
						   column_map_ref=>$column_map_ref,
						   source_file=>"$directory/$search_file",
						   id_hash=>$bs_hash_ref,
						   delimiter => "\t");
    }
  }
  print "# $new_conditions loaded using search string: $search_string\n";
  return $condition_ref;
}


###############################################################################
# getConditionID
#
# returns the condition_id given a condition name, if there's a match
###############################################################################
sub getConditionID {
  my %args = @_;
  my $SUB_NAME = "getConditionID";

  ## Define local variables
  my $condition = $args{'condition'}
  || die "\nERROR[$SUB_NAME]:condition_id needs to be specified\n";

  my $sql = qq~
      SELECT condition_id
      FROM $TBMA_CONDITION
      WHERE condition_name = '$condition'
      AND record_status != 'D'
      ~;
  my @rows = $sbeams->selectOneColumn($sql);
  my $n_rows = @rows;
  ($n_rows > 0 ) ? return $rows[0] : return;
}


###############################################################################
# getColumnMapping
#
# Determines column mapping for sig/merge files.  This could be augmented
# extended to handle other types.
###############################################################################
sub getColumnMapping {
  my %args = @_;
  my $SUB_NAME = "getColumnMapping";

  ## Decode the argument list
  my $source_file = $args{'source_file'}
  || die "no source file passed in find_column_hash";

  my $file_type;

  ## Open file and  make sure file exists
  open(INFILE,"$source_file") || die "Unable to open $source_file";

  ## Check to make sure file is in the correct format
  my ($line,$element,%column_hash, @column_names);
  my $n_columns = 0;

  ## Get first line and split it by tabs
  print "Opening $source_file\n";
  while ($n_columns < 1){
    $line = <INFILE>;
    $line =~ s/\#//;
    chomp($line);
    @column_names = split "\t", $line;
    $n_columns = @column_names;
  }
  close(INFILE);

  ## Determine what type of file/organism we have
  if (!defined ($file_type)){
    if   ($line =~ /UG\sBuild/ &&
		  $line =~ /Tissue/ &&
		  $line =~ /Band/ &&
		  $line =~ /Antibiotics/) {
	  $file_type = "human";
	}elsif($line =~ /operon_oligo_ID/ &&
		  $line =~ /chromosome_start_position/ &&
		  $line =~ /locus_link/ && 
		  $line =~ /melting_temperature/) {
	  $file_type = "mouse";
	}elsif($line =~ /reporter_type/ &&
		  $line =~ /stranded/ &&
		  $line =~ /control_qualifier/) {
	  $file_type = "yeast";
	}elsif($line =~ /younglab_ORF/ &&
		  $line =~ /intergenic_name/ &&
		  $line =~ /pcr_score/ &&
		  $line =~ /primer_reverse_sequence/) {
	  $file_type = "yeast";
	}elsif($line =~ /sequence_name/ &&
		   $line =~ /control_qualifier/ &&
		   $line =~ /operon_oligo_ID/ && 
		   $line =~ /control_type/) {
	  $file_type = "halo";
	}else {
	  $file_type = "generic";
	}
  }

  print "# Will load file according to $file_type scheme\n";

  ## Get appropriate mapping of column headers to database fields
  my $header_hash_ref;
  if ($source_file =~ /clone/) {
      $header_hash_ref = getHeaderHash (organism=>$file_type);
  }else {
      $header_hash_ref = getHeaderHash (organism=>"generic");
  }
  my %header_hash = %{$header_hash_ref};

  ## Move through column headings and map headers to column numbers
  my $counter = 0;
  foreach my $header (@column_names) {
    foreach my $key (keys %header_hash) {
      if ($key =~ /^$header$/){
	  $column_hash{$counter} = $header_hash{$key};
      }
    }
    $counter++;
  }

  ## add column 1000 to store biosequence_id
  $column_hash{'1000'} = 'condition_id';

  return (\%column_hash);
}


###############################################################################
# getHeaderHash
#
# Returns a hash mapping of column headers to fields in the database
#
###############################################################################
sub getHeaderHash {
  my %args = @_;
  my $SUB_NAME = "getHeaderHash";
  my $organism = $args{'organism'} || "generic";
  my %hash;

  if ($organism eq "yeast") {
    %hash = ('external_ID'=>['reporter_name','canonical_name','external_identifier'],
			 'GENE_NAME'=>['full_name','gene_name'],
			 'DESCRIPT.'=>'common_name'
	     );
  }elsif ($organism eq "mouse") {
    %hash = ('GENE_NAME'=>'gene_name',
			 'gene_name'=>'full_name',
			 'gene_symbol'=>'common_name',
			 'operon_oligo_ID'=>['reporter_name'],
			 'external_id'=>['canonical_name','external_identifier']
			 );
  }elsif ($organism eq "human") {
    %hash = ('GENE_NAME'=>['reporter_name','gene_name'],
			 'gene_name'=>'full_name',
			 'external_id'=>['canonical_name','external_identifier'],
			 'gene_symbol'=>'common_name'
			 );
  }elsif ($organism eq "halo") {
	%hash = ('GENE_NAME'=>['reporter_name','gene_name','external_identifier'],
			 'gene_name'=>'common_name',
			 'sequence_name'=>'canonical_name'
			 );
  }elsif ($organism eq "generic") {
    %hash = ('GENE_NAME'=>['reporter_name','canonical_name'],
			 'DESCRIPT.'=>['full_name','common_name','gene_name']
			 );
  }
 
  ## Add Universal hash mappings for all 'clone' files
  $hash{'RATIO'} = 'log10_ratio';
  $hash{'STD'} = 'log10_std_deviation';
  $hash{'lambda'} = 'lambda';
  $hash{'mu_X'} = 'mu_X';
  $hash{'mu_Y'} = 'mu_Y';
  return \%hash;
};
