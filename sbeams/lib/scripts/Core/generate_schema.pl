#!/usr/local/bin/perl -w

###############################################################################
# Program     : generate_schema.pl
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This script generates SQL DROP/CREATE/ALTER statements
#               for different flavors of database based on the
#               table_property and table_column TSV files
#
# SBEAMS is Copyright (C) 2000-2002 by Eric Deutsch
# This program is governed by the terms of the GNU General Public License (GPL)
# version 2 as published by the Free Software Foundation.  It is provided
# WITHOUT ANY WARRANTY.  See the full description of GPL terms in the
# LICENSE file distributed with this software.
#
###############################################################################


###############################################################################
# Generic SBEAMS setup for all the needed modules and objects
###############################################################################
use strict;
use Getopt::Long;
use FindBin;

use lib qw (../perl ../../perl);
use vars qw ($sbeams $sbeamsMOD $q
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG
             $current_contact_id $current_username
            );


#### Set up SBEAMS core module
use SBEAMS::Connection;
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;
$sbeams = new SBEAMS::Connection;

use CGI;
$q = new CGI;


###############################################################################
# Set program name and usage banner for command like use
###############################################################################
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
Usage: $PROG_NAME [OPTIONS]
Options:
  --verbose n         Set verbosity level.  default is 0
  --quiet             Set flag to print nothing at all except errors
  --debug n           Set debug flag
  --table_property_file ccc   Set the name of table_property file
  --table_column_file ccc     Set the name of table_property file
  --schema_file ccc           Set the name of the output schema file
  --destination_type ccc      Set the destination database server type
        (one of: mssql, mysql, pgsql, oracle)

 e.g.:  $PROG_NAME --table_prop \$CONFDIR/Core/Core_table_property.txt \\
                           --table_col \$CONFDIR/Core/Core_table_column.txt \\
                           --schema_file Core_CreateTables.mssql \\
                           --destination_type mssql

EOU


#### Process options
unless (GetOptions(\%OPTIONS,"verbose:s","quiet","debug:s",
  "table_property_file:s","table_column_file:s","schema_file:s",
  "destination_type:s")) {
  print "$USAGE";
  exit;
}

$VERBOSE = $OPTIONS{"verbose"} || 0;
$QUIET = $OPTIONS{"quiet"} || 0;
$DEBUG = $OPTIONS{"debug"} || 0;
if ($DEBUG) {
  print "Options settings:\n";
  print "  VERBOSE = $VERBOSE\n";
  print "  QUIET = $QUIET\n";
  print "  DEBUG = $DEBUG\n";
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
  #exit unless ($current_username = $sbeams->Authenticate(
  #  work_group=>'Developer',
  #));

  #### Normally the authenticator guesses modes, so do it manually
  $sbeams->guessMode();


  #### Read in the default input parameters
  my %parameters;
  my $n_params_found = $sbeams->parse_input_parameters(
    q=>$q,parameters_ref=>\%parameters);
  #$sbeams->printDebuggingInfo($q);


  #### Decide what action to take based on calling information
  my $action = $parameters{action} || '';
  if ($action eq "???") {
    # Some action
  } else {
    $sbeams->printPageHeader() unless ($QUIET);
    generateSchema(ref_parameters=>\%parameters);
    $sbeams->printPageFooter() unless ($QUIET);
  }


} # end main



###############################################################################
# generateSchema
###############################################################################
sub generateSchema {
  my %args = @_;


  #### Process the arguments list
  my $ref_parameters = $args{'ref_parameters'}
    || die "ref_parameters not passed";
  my %parameters = %{$ref_parameters};


  #### Set the command-line options
  my $table_property_file = $OPTIONS{"table_property_file"};
  my $table_column_file = $OPTIONS{"table_column_file"};
  my $schema_file = $OPTIONS{"schema_file"};
  my $destination_type = $OPTIONS{"destination_type"};


  #### Define some generic variables
  my ($i,$element,$key,$value,$line,$result,$sql);


  #### Set an error buffer
  my $errors = "";

  #### If there are any left over parameters, print usage and bail
  if ($ARGV[0]) {
    $errors = "ERROR: Unable to parse parameter '".$ARGV[0]."'!\n";
  }


  #### Make sure all parameters were passed
  unless ($table_property_file && $table_column_file &&
          $schema_file && $destination_type) {
    $errors .= "ERROR: You must specify a value for all parameters ".
      "table_property_file, table_column_file, schema_file, ".
      "destination_type.\n";
  }


  #### If there are any left over parameters, print usage and bail
  if ($errors) {
    print "$errors\n";
    print $USAGE;
    exit 0;
  }


  #### Define the structures into which the files are loaded
  my $table_properties;
  my $table_columns;


  #### Verify the table_property file is openable
  unless ( -e "$table_property_file" ) {
    die("Cannot find file '$table_property_file'");
  }
  unless (open(INFILE,"$table_property_file")) {
    die("File '$table_property_file' exists but cannot be opened");
  }


  #### Read in the first line and try to determine what the columns are
  $line = <INFILE>;
  $line =~ s/[\r\n]//g;
  my @column_names = split("\t",$line);
  my $n_columns = @column_names;
  close(INFILE);


  #### List all the actual column names for code generation
  #print "'",join("','",@column_names),"'\n";
  #return;


  #### If there are 10 columns, verify it's a table_property file and load
  if ($n_columns == 10) {
    my @ref_columns = ('table_name','Category','table_group',
      'manage_table_allowed','db_table_name','PK_column_name',
      'multi_insert_column','table_url','manage_tables','next_step');
    for ($i=0; $i<$n_columns; $i++) {
      if ($column_names[$i] =~ /^\"(.*)\"$/) {
        $column_names[$i] = $1;
      }
      if ($ref_columns[$i] ne $column_names[$i]) {
        print "ERROR: File header verification failed.\n";
	print " Expected column $i to be '$ref_columns[$i]' but it appears ".
          "to be '$column_names[$i]'.  This is unexpected and we cannot ".
          "continue.  Please resolve and retry.\n";
        return;
      }
    }

    print "Reading $table_property_file\n" unless ($QUIET);
    $table_properties = readTableProperty(source_file=>$table_property_file);

  #### Else we don't know what kind of file this is
  } else {
    print "ERROR: File '$table_property_file' does not have ".
      "the right number of columns.  Verify file.\n";
    return;
  }



  #### Verify the table_column file is openable
  unless ( -e "$table_column_file" ) {
    die("Cannot find file '$table_column_file'");
  }
  unless (open(INFILE,"$table_column_file")) {
    die("File '$table_column_file' exists but cannot be opened");
  }


  #### Read in the first line and try to determine what the columns are
  $line = <INFILE>;
  $line =~ s/[\r\n]//g;
  @column_names = split("\t",$line);
  $n_columns = @column_names;
  close(INFILE);


  #### List all the actual column names for code generation
  #print "'",join("','",@column_names),"'\n";
  #return;


  #### If there are 22 columns, verify it's a table_column file and load
  if ($n_columns == 22) {
    my @ref_columns = ('table_name','column_index','column_name',
      'column_title','datatype','scale','precision','nullable',
      'default_value','is_auto_inc','fk_table','fk_column_name',
      'is_required','input_type','input_length','onChange','is_data_column',
      'is_display_column','is_key_field','column_text','optionlist_query',
      'url');
    for ($i=0; $i<$n_columns; $i++) {
      if ($column_names[$i] =~ /^\"(.*)\"$/) {
        $column_names[$i] = $1;
      }
      if ($ref_columns[$i] ne $column_names[$i]) {
        print "ERROR: File header verification failed.\n";
	print " Expected column $i to be '$ref_columns[$i]' but it appears ".
          "to be '$column_names[$i]'.  This is unexpected and we cannot ".
          "continue.  Please resolve and retry.\n";
        return;
      }
    }

    print "Reading $table_column_file\n" unless ($QUIET);
    $table_columns = readTableColumn(source_file=>$table_column_file);

  #### Else we don't know what kind of file this is
  } else {
    print "ERROR: File '$table_property_file' does not have ".
      "the right number of columns.  Verify file.\n";
    return;
  }


  #### Generate the schema based on the input data
  print "Generating schema for $destination_type\n" unless ($QUIET);
  writeSchema(
    table_properties => $table_properties,
    table_columns => $table_columns,
    schema_file => $schema_file,
    destination_type => $destination_type,
  );

  print "Done.\n\n" unless ($QUIET);


} # end generateSchema



###############################################################################
# readTableProperty
###############################################################################
sub readTableProperty {
  my %args = @_;


  #### Process the arguments list
  my $source_file = $args{'source_file'} || die "source_file not passed";


  #### Define some generic variables
  my ($i,$element,$key,$value,$line,$result,$sql);


  #### Open the file
  unless (open(INFILE,"$source_file")) {
    die("File '$source_file' cannot be opened");
  }


  #### Read in the first line and extract the columns
  $line = <INFILE>;
  $line =~ s/[\r\n]//g;
  my @column_names = split("\t",$line);
  my $n_columns = @column_names;

  my $table_properties;
  my @ordered_list;

  #### Read through the rest of the file, load the relevant data
  while ($line = <INFILE>) {
    my @columns = split("\t",$line);
    next if (scalar(@columns) < 4);
    my ($table_name,$category,$table_group) = @columns[0..2];

    #### If the table begins with a two capital letter prefix, remove it
    my $real_name = $table_name;
    $real_name =~ s/^[A-Z]{2,3}\_//;

    $table_properties->{$table_name}->{category} = $category;
    $table_properties->{$table_name}->{table_group} = $table_group;
    $table_properties->{$table_name}->{real_name} = $real_name;
    push(@ordered_list,$table_name);
  }

  #### Add the ordered list to the structure
  $table_properties->{__ordered_list} = \@ordered_list;

  #### Close and return
  close(INFILE);
  return $table_properties;

} # end readTableProperty



###############################################################################
# readTableColumn
###############################################################################
sub readTableColumn {
  my %args = @_;


  #### Process the arguments list
  my $source_file = $args{'source_file'} || die "source_file not passed";


  #### Define some generic variables
  my ($i,$element,$key,$value,$line,$result,$sql);


  #### Open the file
  unless (open(INFILE,"$source_file")) {
    die("File '$source_file' cannot be opened");
  }


  #### Read in the first line and extract the columns
  $line = <INFILE>;
  $line =~ s/[\r\n]//g;
  my @column_names = split("\t",$line);
  my $n_columns = @column_names;

  my $table_column;
  my @ordered_list;

  #### Read through the rest of the file, load the relevant data
  while ($line = <INFILE>) {
    my @columns = split("\t",$line);
    next if (scalar(@columns) < 10);
    my @data = @columns;
    my ($table_name,$column_index,$column_name) = @data[0..2];
    #print "$table_name\t$column_name\t$column_index\n";
    $table_column->{$table_name}->{$column_name} = \@data;
    unless (defined($table_column->{$table_name}->{__ordered_list})) {
      my @tmparray = ();
      $table_column->{$table_name}->{__ordered_list} = \@tmparray;
    }
    push(@{$table_column->{$table_name}->{__ordered_list}},$column_name);
  }

  #### Close and return
  close(INFILE);
  return $table_column;

} # end readTableColumn



###############################################################################
# writeSchema
###############################################################################
sub writeSchema {
  my %args = @_;


  #### Process the arguments list
  my $table_properties = $args{'table_properties'}
    || die "table_properties not passed";
  my $table_columns = $args{'table_columns'}
    || die "table_columns not passed";
  my $schema_file = $args{'schema_file'}
    || die "schema_file not passed";
  my $destination_type = $args{'destination_type'}
    || die "destination_type not passed";


  #### Define some generic variables
  my ($i,$element,$key,$value,$line,$result,$sql);


  #### Set the line break
  my $LB = "\n";
  #my $LB = "\r\n";

  #### Set the statement break
  my $SB = ";$LB";
  $SB = "${LB}GO${LB}" if ($destination_type eq "mssql");


  #### Initialize some buffers
  my $create_tables_buffer = "";
  my $add_constraints_buffer = "";
  my $add_audit_constraints_buffer = "";
  my $drop_constraints_buffer = "";
  my $drop_tables_buffer = "";
  my $drop_sequences_buffer = "";
  my $drop_triggers_buffer = "";
  my $grants_buffer = "";
  my $error_buffer = "";
  my $dictionary_buffer = "";


  #### Loop over all tables backwards to create the DROP TABLE statements
  my $table_name;
  my @table_list = @{$table_properties->{__ordered_list}};
  my @processed_table_list;


  #### Loop over all tables forward to create the CREATE TABLE statements
  foreach $table_name (@table_list) {

    #### If this is a query definition, don't try to CREATE and TABLE
    next if ($table_properties->{$table_name}->{table_group} eq 'QUERY');

    my $real_table_name = $table_properties->{$table_name}->{real_name};

    #### If we have column informnation
    if (defined($table_columns->{$table_name})) {

      print "  CREATE TABLE: $table_name\n" if ($VERBOSE);

      my $line_buffer = "";
      $line_buffer .= "CREATE TABLE $real_table_name ($LB";
      my $primary_key_constraint = "";
      my $create_sequence_statement;
      my $drop_sequence_statement;
      my $create_trigger_statement;
      my $drop_trigger_statement;

      #### Create the Data Dictionary Preamble
      $dictionary_buffer .= generateTableDictionaryHeader(
        table_name => $real_table_name,
      );


      #### Loop over all columns
      my @column_list = @{$table_columns->{$table_name}->{__ordered_list}};
      my $column_name;
      my $table_ref = $table_columns->{$table_name};
      foreach $column_name (@column_list) {
        my ($column_title,$datatype,$scale,$precision,$nullable,$default_value,
            $is_auto_inc,$fk_table,$fk_column,$column_description) =
          @{$table_ref->{$column_name}}[3..11,19];

        #### Look up the fk_table name if any
        if ($fk_table && $table_properties->{$fk_table}->{real_name}) {
          $fk_table = $table_properties->{$fk_table}->{real_name};
        }

        my $result = generateColumnDefinition(
          table_name => $real_table_name,
          column_name => $column_name,
          datatype => $datatype,
          scale => $scale,
          precision => $precision,
          nullable => $nullable,
          default_value => $default_value,
          is_auto_inc => $is_auto_inc,
          fk_table => $fk_table,
          fk_column => $fk_column,
          destination_type => $destination_type,
        );

        $dictionary_buffer .= generateColumnDictionary(
          table_name => $real_table_name,
          column_name => $column_name,
          column_title => $column_title,
          datatype => $datatype,
          scale => $scale,
          precision => $precision,
          nullable => $nullable,
          default_value => $default_value,
          is_auto_inc => $is_auto_inc,
          fk_table => $fk_table,
          fk_column => $fk_column,
          column_description => $column_description,
          destination_type => 'HTML',
        );

        $line_buffer .= $result->{line}.",$LB";

        #### Add generated constraints to corresponding buffers
        if ($result->{add_reference_constraint}) {

          #### If this is an audit column, then keep it separate
          if ($column_name eq 'created_by_id' ||
              $column_name eq 'modified_by_id' ||
              $column_name eq 'owner_group_id') {
            $add_audit_constraints_buffer .=
              $result->{add_reference_constraint}."$SB";
          } else {
            $add_constraints_buffer .=
              $result->{add_reference_constraint}."$SB";
          }

        }
        if ($result->{drop_reference_constraint}) {
          $drop_constraints_buffer .=
            $result->{drop_reference_constraint}."$SB";
        }

        #### Remember the PRIMARY KEY constraint if one shows up
        if ($result->{primary_key_constraint}) {
          $primary_key_constraint .= $result->{primary_key_constraint};
        }

        #### Remember the SEQUENCE statements if one shows up
        if ($result->{create_sequence_statement}) {
          $create_sequence_statement .= $result->{create_sequence_statement}.
            "$SB";
          $drop_sequences_buffer .= $result->{drop_sequence_statement}.
            "$SB";
        }

        #### Remember the TRIGGER statements if one shows up
        if ($result->{create_trigger_statement}) {
          $create_trigger_statement .= $result->{create_trigger_statement}.
            "$LB";
          $drop_triggers_buffer .= $result->{drop_trigger_statement}.
            "$SB";
        }

      }

      #### Add the PRIMARY KEY clause if there is one
      if ($primary_key_constraint) {
        $line_buffer .= "  $primary_key_constraint$LB";
      #### Else hack off the trailing comma
      } else {
        for (my $i=0; $i<length(",$LB"); $i++) {
          chop($line_buffer);
        }
        $line_buffer .= $LB;
      }


      $line_buffer .= ")";
      $line_buffer .= "$SB";
      $create_tables_buffer .= $create_sequence_statement
        if ($create_sequence_statement);
      $create_tables_buffer .= $line_buffer;
      $create_tables_buffer .= $create_trigger_statement
        if ($create_trigger_statement);

      if ($destination_type eq 'pgsql') {
        $grants_buffer .= "GRANT ALL ON $table_name TO sbeams$SB";
        $grants_buffer .= "GRANT SELECT ON $table_name TO sbeamsro$SB";
        $grants_buffer .= "GRANT SELECT ON $table_name TO readonly$SB";
      }

      push(@processed_table_list,$table_name);

      #### Create the Data Dictionary End
      $dictionary_buffer .= generateTableDictionaryFooter(
        table_name => $table_name,
      );


    #### Otherwise, complain that we don't have schema for this table
    } else {
      $error_buffer .= "There is no column information for table: ".
        "'$table_name'!$LB";
    }

  $create_tables_buffer .= "$LB$LB";

  }


  #### Generate the DROP TABLE list
  foreach $table_name (reverse @processed_table_list) {
    my $real_table_name = $table_properties->{$table_name}->{real_name};
    $drop_tables_buffer .= "DROP TABLE $real_table_name$SB";
  }
  $drop_tables_buffer .= "$LB$LB";


  #### Open the output 'DROPCONSTRAINTS' file
  my $filename = "${schema_file}_DROPCONSTRAINTS.$destination_type";
  unless (open(OUTFILE,">$filename")) {
    die("File '$filename' cannot be opened");
  }


  #### PostgreSQL does not yet support DROPing CONSTRAINTS
  if ($destination_type eq 'pgsql') {
    $drop_constraints_buffer = qq~
      /* PostgreSQL does not yet seem to be able to
         ALTER TABLE x DROP CONSTRAINT y
         but does not seem to mind DROPing tables to which there are
         REFERENCEs, so skip the DROP CONSTRAINTs until it is supported
      */
    ~;
  }

  print OUTFILE "$LB$LB$drop_constraints_buffer$LB"
    if ($drop_constraints_buffer);
  close(OUTFILE);


  #### Open the output 'DROPTABLES' file
  $filename = "${schema_file}_DROPTABLES.$destination_type";
  unless (open(OUTFILE,">$filename")) {
    die("File '$filename' cannot be opened");
  }

  print OUTFILE "$LB$LB$drop_triggers_buffer$LB"
    if ($drop_triggers_buffer);
  print OUTFILE "$LB$LB$drop_tables_buffer$LB";
  print OUTFILE "$LB$LB$drop_sequences_buffer$LB"
    if ($drop_sequences_buffer);
  close(OUTFILE);


  #### Open the output 'CREATETABLES' file
  $filename = "${schema_file}_CREATETABLES.$destination_type";
  unless (open(OUTFILE,">$filename")) {
    die("File '$filename' cannot be opened");
  }

  print OUTFILE "$LB$LB$create_tables_buffer$LB";
  print OUTFILE "$LB$LB$grants_buffer$LB" if ($grants_buffer);
  close(OUTFILE);


  #### Open the output 'CREATECONSTRAINTS' file
  $filename = "${schema_file}_CREATECONSTRAINTS.$destination_type";
  unless (open(OUTFILE,">$filename")) {
    die("File '$filename' cannot be opened");
  }

  print OUTFILE "$LB$LB$add_constraints_buffer$LB";
  print OUTFILE "$LB$LB$LB/**** Audit trail FOREIGN KEYS ****/";
  print OUTFILE "$LB$LB$add_audit_constraints_buffer$LB";
  close(OUTFILE);


  #### Open the output 'DATADICTIONARY' file
  $filename = "${schema_file}_DATADICTIONARY.html";
  unless (open(OUTFILE,">$filename")) {
    die("File '$filename' cannot be opened");
  }

  print OUTFILE "$dictionary_buffer";
  close(OUTFILE);


  return;

} # end writeSchema



###############################################################################
# generateColumnDefinition
###############################################################################
sub generateColumnDefinition {
  my %args = @_;


  #### Process the arguments list
  my $table_name = $args{'table_name'} || die "table_name not passed";
  my $column_name = $args{'column_name'} || die "column_name not passed";
  my $datatype = $args{'datatype'} || die "datatype not passed";
  my $scale = $args{'scale'} || "";
  my $precision = $args{'precision'} || "";
  my $nullable = $args{'nullable'} || "";
  my $default_value = $args{'default_value'} || "";
  my $is_auto_inc = $args{'is_auto_inc'} || "";
  my $fk_table = $args{'fk_table'} || "";
  my $fk_column = $args{'fk_column'} || "";
  my $destination_type = $args{'destination_type'}
    || die "destination_type not passed";


  #### Do some adjustment of the datatype names.  This should be done better
  if ($destination_type eq 'oracle') {
    if ($datatype eq 'text') {
      $datatype = 'varchar2(4000)'
    } elsif ($datatype eq 'datetime') {
      $datatype = 'date'
    }
    #### I guess "comment" is a reserved word in Oracle???
    if ($column_name eq 'comment') {
       $column_name = 'comments'
    }
  }


  #### Define the columns that need to be qualified with $scale
  my %is_single_paren = (varchar=>1,char=>1);


  #### Define the output result
  my $result;
  $result->{success} = '';


  #### Start building the line with the column name and some padding
  my $padding_length = 25 - length($column_name);
  $padding_length = 0 if ($padding_length < 0);
  my $line = "  $column_name " . " " x $padding_length . " ";


  #### Add the datatype

  #### If this is an auto incrementing value then use dialect
  my $primary_key_constraint;
  my $create_sequence_statement;
  my $drop_sequence_statement;
  my $create_trigger_statement;
  my $drop_trigger_statement;
  if (uc($is_auto_inc) =~ /Y/) {

    if ($destination_type eq 'mssql') {
      $line .= "$datatype IDENTITY";

    } elsif ($destination_type eq 'mysql') {
      $line .= "$datatype AUTO_INCREMENT";

    } elsif ($destination_type eq 'pgsql') {
      my $sequence_name = "seq_${table_name}_${column_name}";
      #### PostgreSQL truncates SEQUENCES to 31 characters
      #### at this writing so truncate the name here too
      $sequence_name = substr($sequence_name,0,31);
      $line .= "$datatype DEFAULT NEXTVAL('$sequence_name')";
      $create_sequence_statement =
        "CREATE SEQUENCE $sequence_name;\n".
        "GRANT ALL ON $sequence_name TO sbeams";
      $drop_sequence_statement =
        "DROP SEQUENCE $sequence_name";

    } elsif ($destination_type eq 'oracle') {
      my $sequence_name = "seq_${table_name}_${column_name}";
      #### Maximum length for Oracle sequence name is 30
      $sequence_name = substr($sequence_name,0,30);
      $line .= "int";
      $create_sequence_statement =
        "CREATE SEQUENCE $sequence_name \n".
        "   minvalue 1  maxvalue 999999999999 nocycle;\n".
        "GRANT ALL ON $sequence_name TO sbeams";
      $drop_sequence_statement =
        "DROP SEQUENCE $sequence_name";
      $create_trigger_statement =
        "CREATE TRIGGER ${table_name}_BI\n".
        "   BEFORE INSERT ON ${table_name}\n". 
        "   FOR EACH ROW BEGIN\n".
        "      select $sequence_name.nextval\n".
        "      into :new.${column_name} from dual;\n".
        "   END;\n".
        "/\n";
      $drop_trigger_statement =
        "DROP TRIGGER ${table_name}_BI\n";

    } else {
      $line .= "SERIAL";
    }

    $primary_key_constraint = "PRIMARY KEY ($column_name)";

  #### Otherwise if its just a PRIMARY KEY column, then add that constraint
  #### and just write out the datatype (Needs a function to xlate FIXME)
  } elsif (uc($is_auto_inc) =~ /P/) {
    $primary_key_constraint = "PRIMARY KEY ($column_name)";
    $line .= "$datatype";

  #### Otherwise just write it out
  } else {
    $line .= "$datatype";
  }


  #### If this requires parenthesized scaling
  if ($is_single_paren{$datatype}) {
    $line .= "($scale)";
  }

  ####  Oracle requires default value before NULLability so
  ####  reoder following to section for oracle
  if ($destination_type eq 'oracle') {
    #### Set a DEFAULT value if any
    if ($default_value) {
      if ($default_value eq 'CURRENT_TIMESTAMP') {
          $line .= " DEFAULT sysdate";
      } else {
        $line .= " DEFAULT '$default_value'";
      }
    }

    #### Set NULLability
    if (uc($nullable) =~ /Y/) {
      $line .= " NULL";
    } else {
      $line .= " NOT NULL";
    }
  }

  #### For other databases NULL before DEFAULT. Maybe others allow Oracle way?
  else {
    #### Set NULLability
    if (uc($nullable) =~ /Y/) {
      $line .= " NULL";
    } else {
      $line .= " NOT NULL";
    }

    #### Set a DEFAULT value if any
    if ($default_value) {
      if ($default_value eq 'CURRENT_TIMESTAMP') {
        if ($destination_type eq 'mysql') {
          $line .= " /* DEFAULT $default_value (not supported) */";
        } else {
          $line .= " DEFAULT $default_value";
        }
      } else {
        $line .= " DEFAULT '$default_value'";
      }
    }
  }


  #### Set a REFERENCES clause if appropriate
  my $add_reference_constraint;
  my $add_audit_reference_constraint;
  my $drop_reference_constraint;
  if ($fk_table && $fk_column) {
    #$line .= " /* REFERENCES $fk_table($fk_column) */";
    my $constraint_name =  "fk_${table_name}_${column_name}"; 
    #### Oracle has constraint name maximum length of 30
    $constraint_name = 'fk_'.substr(${table_name},1,13).
                         '_'.substr(${column_name},1,13)
          if ($destination_type eq 'oracle') ;
    $add_reference_constraint = "ALTER TABLE $table_name ADD CONSTRAINT ".
        "$constraint_name FOREIGN KEY ($column_name) ".
        "REFERENCES $fk_table($fk_column)";

    $drop_reference_constraint = "ALTER TABLE $table_name DROP CONSTRAINT ".
      "$constraint_name";

    #### MySQL 3.23.x doesn't support references yet
    $drop_reference_constraint = "" if ($destination_type eq 'mysql');
  }


  $result->{line} = $line;
  $result->{add_reference_constraint} = $add_reference_constraint;
  $result->{drop_reference_constraint} = $drop_reference_constraint;
  $result->{primary_key_constraint} = $primary_key_constraint;
  $result->{create_sequence_statement} = $create_sequence_statement;
  $result->{drop_sequence_statement} = $drop_sequence_statement;
  $result->{create_trigger_statement} = $create_trigger_statement;
  $result->{drop_trigger_statement} = $drop_trigger_statement;
  $result->{success} = 'Y';


  return $result;

} # end generateColumnDefinition


###############################################################################
# generateColumnDictionary
###############################################################################
sub generateColumnDictionary {
  my %args = @_;


  #### Process the arguments list
  my $table_name = $args{'table_name'} || die "table_name not passed";
  my $column_name = $args{'column_name'} || die "column_name not passed";
  my $column_title = $args{'column_title'} || die "column_title not passed";
  my $datatype = $args{'datatype'} || die "datatype not passed";
  my $scale = $args{'scale'} || "&nbsp;";
  my $precision = $args{'precision'} || "&nbsp;";
  my $nullable = $args{'nullable'} || "&nbsp;";
  my $default_value = $args{'default_value'} || "&nbsp;";
  my $is_auto_inc = $args{'is_auto_inc'} || "&nbsp;";
  my $fk_table = $args{'fk_table'} || "&nbsp;";
  my $fk_column = $args{'fk_column'} || "&nbsp;";
  my $column_description = $args{'column_description'} || "&nbsp;";
  my $destination_type = $args{'destination_type'}
    || die "destination_type not passed";


  #### Do some adjustment of the datatype names.  This should be done better
  if ($destination_type eq 'oracle') {
    #### I guess "comment" is a reserved word in Oracle???
    if ($column_name eq 'comment') {
       $column_name = 'comments'
    }
  }


  #### Define the columns that need to be qualified with $scale
  my %is_single_paren = (varchar=>1,char=>1);

  #### If this requires parenthesized scaling
  if ($is_single_paren{$datatype}) {
    $datatype .= "($scale)";
  }

  my $result = "
    <TR>
      <TD>$column_name</TD>
      <TD>$column_title</TD>
      <TD>$datatype</TD>
      <TD>$nullable</TD>
      <TD>$default_value</TD>
      <TD>$is_auto_inc</TD>
      <TD>$fk_table</TD>
      <TD>$fk_column</TD>
      <TD>$column_description</TD>
    </TR>
  ";

  return $result;

} # end generateColumnDictionary


###############################################################################
# generateTableDictionaryHeader
###############################################################################
sub generateTableDictionaryHeader {
  my %args = @_;


  #### Process the arguments list
  my $table_name = $args{'table_name'} || die "table_name not passed";


  my $result = "
    <H1>$table_name</H1>
    <TABLE border=1>
    <TR>
      <TH>column_name</TH>
      <TH>column_title</TH>
      <TH>datatype</TH>
      <TH>nullable</TH>
      <TH>default_value</TH>
      <TH>is_auto_inc</TH>
      <TH>fk_table</TH>
      <TH>fk_column</TH>
      <TH>column_description</TH>
    </TR>
  ";

  return $result;

} # end generateTableDictionaryHeader


###############################################################################
# generateTableDictionaryFooter
###############################################################################
sub generateTableDictionaryFooter {
  my %args = @_;


  #### Process the arguments list
  my $table_name = $args{'table_name'} || die "table_name not passed";


  my $result = "
    </TABLE>
  ";

  return $result;

} # end generateTableDictionaryFooter
