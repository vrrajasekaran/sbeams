package SBEAMS::Connection::DBInterface;

###############################################################################
# Program     : SBEAMS::Connection::DBInterface
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This is part of the SBEAMS::Connection module which handles
#               general communication with the database.
#
###############################################################################


use strict;
use vars qw(@ERRORS $dbh $sth $q $resultset_ref $rs_params_ref);
use CGI::Carp qw(fatalsToBrowser croak);
use DBI;
use POSIX;
use Data::Dumper;
use URI::Escape;
use Storable;


#use lib "/net/db/src/CPAN/Data-ShowTable-3.3a/blib/lib";
#use Data::ShowTableTest;
use Data::ShowTable;

use SBEAMS::Connection::Settings;
use SBEAMS::Connection::DBConnector;
use SBEAMS::Connection::Tables;
use SBEAMS::Connection::TableInfo;

$q       = new CGI;


###############################################################################
# Global variables
###############################################################################
#$dbh = SBEAMS::Connection::DBConnector::getDBHandle();
#### Can we get rid of this?? This may be creating a connection before
#### we want it?


###############################################################################
# Constructor
###############################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;
    return($self);
}


###############################################################################
# apply Sql Change
#
# This is kind of an old and krusty method that really needs updating
#
# All INSERT, UPDATE, DELETE SQL commands initiated by the user should be
# delivered here first so that all permission checking and logging of the
# commands takes place.
###############################################################################
sub applySqlChange {
    my $self = shift || croak("parameter self not passed");
    my $sql_query = shift || croak("parameter sql_query not passed");
    my $current_contact_id = shift
       || croak("parameter current_contact_id not passed");
    my $table_name = shift || croak("parameter table_name not passed");
    my $record_identifier = shift
       || croak("parameter record_identifier not passed");

    #### Get the database handle
    $dbh = $self->getDBHandle();

    # Privilege that a certain work_group has over a table_group
    my $table_group_privilege_id;
    # Privilege that a certain user has within a work_group
    my $user_work_group_privilege_id;
    # Privilege that a certain user has given himself within the user_context
    my $user_context_privilege_id;
    my $nrows = 0;

    my $current_privilege_id = 999;
    my $privilege_id;
    my @row;
    my $result = "CODE ERROR";
    my $returned_PK;
    @ERRORS = ();


    # Get the names of all the permission levels
    my %level_names = $self->selectTwoColumnHash("
	SELECT privilege_id,name FROM $TB_PRIVILEGE");

    my ($DB_TABLE_NAME) = $self->returnTableInfo($table_name,"DB_TABLE_NAME");
    #print "DB_TABLE_NAME = $DB_TABLE_NAME<BR>\n";
    #print "table_name = $table_name<BR>\n";


    # Extract the first word, hopefully INSERT, UPDATE, or DELETE
    $sql_query =~ /\s*(\w*)/;
    my $sql_action = uc($1);


    # New method of checking table/group/user level permissions
    my $current_work_group_id = $self->getCurrent_work_group_id();
    my $current_work_group_name = $self->getCurrent_work_group_name();
    my $check_privilege_query = qq!
	SELECT UC.contact_id,UC.work_group_id,TGS.table_group,
		TGS.privilege_id,UWG.privilege_id,UC.privilege_id
	  FROM table_group_security TGS
	  LEFT JOIN user_context UC ON ( TGS.work_group_id=UC.work_group_id )
  	  LEFT JOIN table_property TP ON ( TGS.table_group=TP.table_group )
	  LEFT JOIN user_work_group UWG ON ( TGS.work_group_id=UWG.work_group_id
	       AND UC.contact_id=UWG.contact_id )
	 WHERE TGS.work_group_id='$current_work_group_id'
	   AND TP.table_name='$table_name'
	   AND UWG.contact_id='$current_contact_id'
    !;

    my $sth = $dbh->prepare("$check_privilege_query") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;
    #push(@ERRORS, "Returned Permissions:");
    $nrows = 0;
    while (@row = $sth->fetchrow_array) {
      #push(@ERRORS, "---> ".join(" | ",@row));
      $table_group_privilege_id = $row[3];
      $user_work_group_privilege_id = $row[4];
      $user_context_privilege_id = $row[5];
      $nrows++;
    }
    $sth->finish;


    # If no rows came back, the table/work_group relationship is not defined
    if ($nrows==0) {
      push(@ERRORS, "The privilege of your current work group
        ($current_work_group_name) is not defined for this table");
      $result = "DENIED";
    }


    # Don't know how to handle multiple rows yet
    if ($nrows>1) {
      push(@ERRORS, "Multiple permissions were found, and I don't know what
        to do.  Please contact <B>edeutsch</B> about this error");
      $result = "DENIED";
    }


    $privilege_id=99;
    if ($table_group_privilege_id > 0) {
      $privilege_id=$table_group_privilege_id;
    }

    if (defined($user_work_group_privilege_id) &&
        $user_work_group_privilege_id>$privilege_id) {
      $privilege_id=$user_work_group_privilege_id;
    }

    if (defined($user_context_privilege_id) &&
        $user_context_privilege_id>$privilege_id) {
      $privilege_id=$user_context_privilege_id;
    }

    my ($privilege_name) = $self->selectOneColumn("
	SELECT name FROM $TB_PRIVILEGE WHERE privilege_id='$privilege_id'");


    if ($privilege_id >= 40) {
      push(@ERRORS, "You do not have privilege to write to this table.");
      $result = "DENIED";
    }


    elsif ($sql_action eq "INSERT") {
      $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
      $rv  = $sth->execute or croak $dbh->errstr;
      $result = "SUCCESSFUL";

      # Find out what the IDENTITY value for this INSERT was so it can
      # be reported back.
      # This is current MS SQL SERVER SPECIFIC.  A different command
      # would be required for a different database.
      my $check_auto_incr_value_query = qq!
        SELECT SCOPE_IDENTITY()
      !;

      my $sth = $dbh->prepare("$check_auto_incr_value_query")
        or croak $dbh->errstr;
      my $rv  = $sth->execute or croak $dbh->errstr;
      @row = $sth->fetchrow_array;
      ($returned_PK) = @row;
      $sth->finish;
    }


    elsif ( ($sql_action eq "UPDATE") or ($sql_action eq "DELETE") ) {

      # Get modified by, group_owner, status of record to be affected
      my $check_permission_query = qq!
        SELECT T.modified_by_id,T.owner_group_id,T.record_status
          FROM $DB_TABLE_NAME T
--          LEFT JOIN $TB_USER_CONTEXT UC ON (T.owner_group_id.UC.work_group_id)
         WHERE T.$record_identifier!;
      $sth = $dbh->prepare("$check_permission_query") or croak $dbh->errstr;
      $rv  = $sth->execute or croak $dbh->errstr;
      @row = $sth->fetchrow_array;
      my ($modified_by_id,$owner_group_id,$record_status) = @row;
      $sth->finish;


      my $permission="DENIED";
      $permission="ALLOWED" if ( ($record_status ne "L")
                             and ($privilege_id <= 20) );
      $permission="ALLOWED" if ( ($record_status eq "M")
                             and ($privilege_id <= 30) );
      $permission="ALLOWED" if ( ($record_status ne "L")
                             and ($privilege_id <= 25)
                             and ($owner_group_id == $current_work_group_id) );
      $permission="ALLOWED" if ( $modified_by_id==$current_contact_id );

      if ($permission eq "ALLOWED") {
        $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
        $rv  = $sth->execute or croak $dbh->errstr;
        $result = "SUCCESSFUL";
      } else {
        push(@ERRORS, "You do not have permission to $sql_action this record.");
        push(@ERRORS, "Your privilege level is $privilege_name.");
        push(@ERRORS, "You are not the owner of this record.")
          if ($current_contact_id!=$modified_by_id);
        push(@ERRORS, "The group owner of this record ($owner_group_id) is not the same as your current working group ($current_work_group_id = [$current_work_group_name]).")
          if ($owner_group_id != $current_work_group_id);
        push(@ERRORS, "This record is Locked.")
          if ($record_status eq "L");
        $result = "DENIED";
      }

    }


    my $altered_sql_query = $self->convertSingletoTwoQuotes($sql_query);
    my $log_query = qq!
        INSERT INTO $TB_SQL_COMMAND_LOG
               (created_by_id,result,sql_command)
        VALUES ($current_contact_id,'$result','$altered_sql_query')
    !;

    $sth = $dbh->prepare("$log_query") or croak $dbh->errstr;
    $rv  = $sth->execute or croak $dbh->errstr;
    $sth->finish;


    return ($result,$returned_PK,@ERRORS);
}


###############################################################################
# SelectOneColumn
#
# Given a SQL query, return an array containing the first column of
# the resultset of that query.
###############################################################################
sub selectOneColumn {
    my $self = shift || croak("parameter self not passed");
    my $sql = shift || croak("parameter sql not passed");

    my @row;
    my @rows;

    #### Get the database handle
    $dbh = $self->getDBHandle();

    my $sth = $dbh->prepare($sql) or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (@row = $sth->fetchrow_array) {
        push(@rows,$row[0]);
    }

    $sth->finish;

    return @rows;

} # end selectOneColumn


###############################################################################
# selectSeveralColumns
#
# Given a SQL statement which returns one or more columns, return an array
# of references to arrays of the results of each row of that query.
###############################################################################
sub selectSeveralColumns {
    my $self = shift || croak("parameter self not passed");
    my $sql = shift || croak("parameter sql not passed");

    my @rows;

    #### Get the database handle
    $dbh = $self->getDBHandle();

    #### FIX ME replace with $dbh->selectall_arrayref ?????
    my $sth = $dbh->prepare($sql) or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (my @row = $sth->fetchrow_array) {
        push(@rows,\@row);
    }

    $sth->finish;

    return @rows;

} # end selectSeveralColumns


###############################################################################
# selectHashArray
#
# Given a SQL statement which returns one or more columns, return an array
# of references to hashes of the results of each row of that query.
###############################################################################
sub selectHashArray {
    my $self = shift || croak("parameter self not passed");
    my $sql = shift || croak("parameter sql not passed");

    my @rows;

    #### Get the database handle
    $dbh = $self->getDBHandle();

    my $sth = $dbh->prepare($sql) or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (my $columns = $sth->fetchrow_hashref) {
        push(@rows,$columns);
    }

    $sth->finish;

    return @rows;

} # end selectHashArray


###############################################################################
# selectTwoColumnHash
#
# Given a SQL statement which returns exactly two columns, return a hash
# containing the results of that query.
###############################################################################
sub selectTwoColumnHash {
    my $self = shift || croak("parameter self not passed");
    my $sql_query = shift || croak("parameter sql_query not passed");

    my %hash;

    #### Get the database handle
    $dbh = $self->getDBHandle();

    my $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (my @row = $sth->fetchrow_array) {
        $hash{$row[0]} = $row[1];
    }

    $sth->finish;

    return %hash;

}


###############################################################################
# insert_update_row
#
# This method builds either an INSERT or UPDATE SQL statement based on the
# supplied parameters and executes the statement.
###############################################################################
sub insert_update_row {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;

  #### Decode the argument list
  my $table_name = $args{'table_name'} || die "ERROR: table_name not passed";
  my $rowdata_ref = $args{'rowdata_ref'}
    || die "ERROR: rowdata_ref not passed";
  my $database_name = $args{'database_name'} || '';
  my $return_PK = $args{'return_PK'} || 0;
  my $verbose = $args{'verbose'} || 0;
  my $print_SQL = $args{'print_SQL'} || 0;
  my $testonly = $args{'testonly'} || 0;
  my $insert = $args{'insert'} || 0;
  my $update = $args{'update'} || 0;
  my $PK = $args{'PK_name'} || $args{'PK'} || '';
  my $PK_value = $args{'PK_value'} || '';
  my $quoted_identifiers = $args{'quoted_identifiers'} || '';


  #### Make sure either INSERT or UPDATE was selected
  unless ( ($insert or $update) and (!($insert and $update)) ) {
    croak "ERROR: Need to specify either 'insert' or 'update'\n\n";
  }


  #### If this is an UPDATE operation, make sure that we got the PK and value
  if ($update) {
    unless ($PK and $PK_value) {
      croak "ERROR: Need both PK and PK_value if operation is UPDATE\n\n";
    }
  }


  #### Initialize some variables
  my ($column_list,$value_list,$columnvalue_list) = ("","","");
  my ($key,$value,$value_ref);


  #### If verbose, prepare this section
  if ($verbose) {
    print "---- updateOrInsertRow --------------------------------\n";
    print "  Key,value pairs:\n";
  }


  #### Loops over each passed rowdata element, building the query
  while ( ($key,$value) = each %{$rowdata_ref} ) {

    #### If quoted identifiers is set, then quote the key
    $key = '"'.$key.'"' if ($quoted_identifiers);

    #### If $value is a reference, assume it's a reference to a hash and
    #### extract the {value} key value.  This is because of Xerces.
    $value = $value->{value} if (ref($value));

    print "	$key = $value\n" if ($verbose > 0);

    #### Add the key as the column name
    $column_list .= "$key,";

    #### Enquote and add the value as the column value
    $value = $self->convertSingletoTwoQuotes($value);
    if (uc($value) eq "CURRENT_TIMESTAMP") {
      $value_list .= "$value,";
      $columnvalue_list .= "$key = $value,\n";
    } else {
      $value_list .= "'$value',";
      $columnvalue_list .= "$key = '$value',\n";
    }

  }


  unless ($column_list) {
    print "ERROR: insert_row(): column_list is empty!\n";
    return '';
  }


  #### Chop off the final commas
  chop $column_list;
  chop $value_list;
  chop $columnvalue_list;  # First the \n
  chop $columnvalue_list;  # Then the comma


  #### Create the final table name
  my $full_table_name = "$database_name$table_name";
  $full_table_name = '"'.$full_table_name.'"' if ($quoted_identifiers);


  #### Build the SQL statement
  my $sql;
  if ($update) {
    my $PK_tag = $PK;
    $PK_tag = '"'.$PK.'"' if ($quoted_identifiers);
    $sql = "UPDATE $full_table_name SET $columnvalue_list WHERE $PK_tag = '$PK_value'";
  } else {
    $sql = "INSERT INTO $full_table_name ( $column_list ) VALUES ( $value_list )";
  }

  #### Print out the SQL if desired
  if ($verbose > 0 || $print_SQL > 0) {
    print "  SQL statement:\n";
    print "    $sql\n\n";
  }


  #### If we're just testing
  if ($testonly) {

    #### If the user asked for the PK to be returned, make a random one up
    if ($return_PK) {
      return int(rand()*10000);

    #### Otherwise, just return a 1
    } else {
      return 1;
    }
  }


  #### Execute the SQL
  $self->executeSQL($sql);


  #### If user didn't want PK, return with success
  return "1" unless ($return_PK);


  #### If user requested the resulting PK, return it
  if ($update) {
    return $PK_value;
  } else {
    return $self->getLastInsertedPK(table_name=>"$database_name$table_name",
      PK_column_name=>"$PK");
  }


}


###############################################################################
# executeSQL
#
# Execute the supplied SQL statement with no return value.
###############################################################################
sub executeSQL {
    my $self = shift || croak("parameter self not passed");
    my $sql = shift || croak("parameter sql not passed");

    #### Get the database handle
    $dbh = $self->getDBHandle();

    my $sth = $dbh->prepare($sql) or die($dbh->errstr);
    my $rows  = $sth->execute or die($dbh->errstr);

    #### This doesn't seem to die if the execute fails????
    #my ($rows) = $dbh->do("$sql") or die($dbh->errstr);

    return $rows;

}



###############################################################################
# getLastInsertedPK
#
# Return the value of the AUTO GEN key for the last INSERTed row
###############################################################################
sub getLastInsertedPK {
    my $self = shift || croak("parameter self not passed");
    my %args = @_;
    my $subName = "getLastInsertedPK";


    #### Decode the argument list
    my $table_name = $args{'table_name'};
    my $PK_column_name = $args{'PK_column_name'};


    my $sql;
    my $DBType = $self->getDBType() || "";


    #### Method to determine last inserted PK depends on database server
    if ($DBType =~ /MS SQL Server/i) {
      $sql = "SELECT SCOPE_IDENTITY()";

    } elsif ($DBType =~ /MySQL/i) {
      $sql = "SELECT LAST_INSERT_ID()";

    } elsif ($DBType =~ /PostgreSQL/i) {
      croak "ERROR[$subName]: Both table_name and PK_column_name need to be " .
        "specified here for PostgreSQL since no automatic PK detection is " .
        "yet possible." unless ($table_name && $PK_column_name);

      #### YUCK! PostgreSQL 7.1 appears to truncate table name and PK name at
      #### 13 characters to form the automatic SEQUENCE.  Might be fix later?
      my $table_name_tmp = substr($table_name,0,13);
      my $PK_column_name_tmp = substr($PK_column_name,0,13);
 
      $sql = "SELECT currval('${table_name_tmp}_${PK_column_name_tmp}_seq')"

    } else {
      croak "ERROR[$subName]: Unable to determine DBType\n\n";
    }


    #### Get value and return it
    my ($returned_PK) = $self->selectOneColumn($sql);
    return $returned_PK;

}



###############################################################################
# parseConstraint2SQL
#
# Given human-entered constraint, convert it to a SQL "AND" clause which some
# suitable checking to make sure the user isn't trying to enter something
# bogus
###############################################################################
sub parseConstraint2SQL {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;

  #### Decode the argument list
  my $constraint_column = $args{'constraint_column'}
   || die "ERROR: constraint_column not passed";
  my $constraint_type = $args{'constraint_type'}
   || die "ERROR: constraint_type not passed";
  my $constraint_name = $args{'constraint_name'}
   || die "ERROR: constraint_name not passed";
  my $constraint_value = $args{'constraint_value'};
  my $verbose = $args{'verbose'} || 0;


  #### Strip leading and trailing whitespace
  return unless (defined($constraint_value));
  $constraint_value =~ s/^\s+//;
  $constraint_value =~ s/\s+$//;


  #### If no value was provided, simply return an empty string
  #### Don't return is the value is "0" because that may be a value
  return if ($constraint_value eq "");


  #### Parse type int
  if ($constraint_type eq "int") {
    print "Parsing int $constraint_name<BR>\n" if ($verbose);
    if ($constraint_value =~ /^[\d]+$/) {
      return "   AND $constraint_column = $constraint_value";
    } else {
      print "<H4>Cannot parse $constraint_name constraint ".
        "'$constraint_value'!  Check syntax.</H4>\n\n";
      return -1;
    }
  }


  #### Parse type flexible_int
  if ($constraint_type eq "flexible_int") {
    print "Parsing flexible_int $constraint_name<BR>\n" if ($verbose);
    if ($constraint_value =~ /^[\d]+$/) {
      return "   AND $constraint_column = $constraint_value";
    } elsif ($constraint_value =~ /^between\s+[\d]+\s+and\s+[\d]+$/i) {
      return "   AND $constraint_column $constraint_value";
    } elsif ($constraint_value =~ /^([\d]+)\s*\+\-\s*([\d]+)$/i) {
      my $lower = $1 - $2;
      my $upper = $1 + $2;
      return "   AND $constraint_column BETWEEN $lower AND $upper";
    } elsif ($constraint_value =~ /^[><=][=]*\s*[\d]+$/) {
      return "   AND $constraint_column $constraint_value";
    } else {
      print "<H4>Cannot parse $constraint_name constraint ".
        "'$constraint_value'!  Check syntax.</H4>\n\n";
      return -1;
    }
  }


  #### Parse type flexible_float
  if ($constraint_type eq "flexible_float") {
    print "Parsing flexible_float $constraint_name<BR>\n" if ($verbose);
    if ($constraint_value =~ /^[\d\.]+$/) {
      return "   AND $constraint_column = $constraint_value";
    } elsif ($constraint_value =~ /^between\s+[\d\.]+\s+and\s+[\d\.]+$/i) {
      return "   AND $constraint_column $constraint_value";
    } elsif ($constraint_value =~ /^([\d\.]+)\s*\+\-\s*([\d\.]+)$/i) {
      my $lower = $1 - $2;
      my $upper = $1 + $2;
      return "   AND $constraint_column BETWEEN $lower AND $upper";
    } elsif ($constraint_value =~ /^[><=][=]*\s*[\d\.]+$/) {
      return "   AND $constraint_column $constraint_value";
    } else {
      print "<H4>Cannot parse $constraint_name constraint ".
        "'$constraint_value'!  Check syntax.</H4>\n\n";
      return -1;
    }
  }


  #### Parse type int_list: a list of integers like "+1, 2,-3"
  if ($constraint_type eq "int_list") {
    print "Parsing int_list $constraint_name<BR>\n" if ($verbose);
    if ($constraint_value =~ /^[\d,\s]+$/ ) {
      return "   AND $constraint_column IN ( $constraint_value )";
    } else {
      print "<H4>Cannot parse $constraint_name constraint ".
        "'$constraint_value'!  Check syntax.</H4>\n\n";
      return -1;
    }
  }


  #### Parse type plain_text: a plain, unquoted bit of text
  if ($constraint_type eq "plain_text") {
    print "Parsing plain_text $constraint_name<BR>\n" if ($verbose);
    print "constraint_value = $constraint_value<BR>\n" if ($verbose);

    #### Convert any ' marks to '' to appear okay within the strings
    $constraint_value = $self->convertSingletoTwoQuotes($constraint_value);

    #### Bad word checking here has been disabled because the string will be
    #### quoted, so there shouldn't be a way to put in dangerous SQL...
    #if ($constraint_value =~ /SELECT|TRUNCATE|DROP|DELETE|FROM|GRANT/i) {}

    return "   AND $constraint_column LIKE '$constraint_value'";
  }




  die "ERROR: unrecognized constraint_type!";

}


###############################################################################
# build Option List
#
# Given an SQL query which returns exactly two columns (option value and
# option description), an HTML <OPTION> list is returned.  If a second
# parameter is supplied, the option VALUE which matches will be SELECTED.
###############################################################################
sub buildOptionList {
    my $self = shift;
    my $sql_query = shift;
    my $selected_option = shift;
    my $method_options = shift;
    my $selected_flag;

    my %selected_options;

    #### If we explicitly were called with an MULITOPIONLIST, separate
    #### a comma-delimited list into several elements
    my @tmp;
    if ($method_options =~ /MULTIOPTIONLIST/) {
      @tmp = split(",",$selected_option);
    } else {
      @tmp = ($selected_option);
    }

    my $element;
    foreach $element (@tmp) {
      $selected_options{$element}=1;
    }

    #### Get the database handle
    $dbh = $self->getDBHandle();

    my $options="";
    my $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (my @row = $sth->fetchrow_array) {
        $selected_flag="";
        $selected_flag=" SELECTED"
          if ($selected_options{$row[0]});
        $options .= qq!<OPTION$selected_flag VALUE="$row[0]">$row[1]\n!;
    } # end while

    $sth->finish;

    return $options;

}


###############################################################################
# Get Record Status Options
#
# Returns the record status option list.
###############################################################################
sub getRecordStatusOptions {
    my $self = shift;
    my $selected_option = shift;

    $selected_option = "N" unless $selected_option gt "";

    my $sql_query = qq!
        SELECT record_status_id, name
          FROM $TB_RECORD_STATUS
         ORDER BY sort_order!;

    return $self->buildOptionList($sql_query,$selected_option);

} # end getRecordStatusOptions


###############################################################################
# DisplayQueryResult
#
# Executes a query and displays the results as an HTML table
###############################################################################
sub displayQueryResult {
    my $self = shift;
    my %args = @_;

    #### Process the arguments list
    my $sql_query = $args{'sql_query'} || croak "parameter sql_query missing";
    my $url_cols_ref = $args{'url_cols_ref'};
    my $hidden_cols_ref = $args{'hidden_cols_ref'};
    my $row_color_scheme_ref = $args{'row_color_scheme_ref'};
    my $printable_table = $args{'printable_table'};
    my $max_widths_ref = $args{'max_widths'};
    $resultset_ref = $args{'resultset_ref'};


    #### Get the database handle
    $dbh = $self->getDBHandle();

    #### Execute the query
    $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;


    #print $sth->{NUM_OF_FIELDS},"<BR>\n";
    #print join ("|",@{ $sth->{TYPE} }),"<BR>\n";

    #### Define <TD> tags
    my @TDformats=('NOWRAP');


    #### If a row_color_scheme was not passed, create one:
    unless ($row_color_scheme_ref) {
      my %row_color_scheme;
      $row_color_scheme{change_n_rows} = 3;
      my @row_color_list = ("#E0E0E0","#C0D0C0");
      $row_color_scheme{color_list} = \@row_color_list;
      $row_color_scheme_ref = \%row_color_scheme;
    }


    #### Decode the type numbers into type strings
    my $types_ref = $self->decodeDataType($sth->{TYPE});


    #### Make some adjustments to the default column width settings
    my @precisions = @{$sth->{PRECISION}};
    my $i;
    for ($i = 0; $i <= $#precisions; $i++) {
      #### Set the width to negative (variable)
      $precisions[$i] = (-1) * $precisions[$i];

      #### Override the width if the user specified it
      $precisions[$i] = $max_widths_ref->{$sth->{NAME}->[$i]}
        if ($max_widths_ref->{$sth->{NAME}->[$i]});

      #### Set the precision to 20 for dates (2001-01-01 00:00:01)
      $precisions[$i] = 20 if ($types_ref->[$i] =~ /date/i);

      #### Print for debugging
      #print $sth->{NAME}->[$i],"(",$types_ref->[$i],"): ",
      #  $precisions[$i],"<BR>\n";
    }


    #### Prepare returned resultset
    my @resultsetdata;
    my %column_hash;
    my $element;
    $resultset_ref->{column_list_ref} = $sth->{NAME};
    $i = 0;
    foreach $element (@{$sth->{NAME}}) {
      $column_hash{$element} = $i;
      $i++;
    }
    $resultset_ref->{column_hash_ref} = \%column_hash;
    $resultset_ref->{data_ref} = \@resultsetdata;


    #### If a printable table was desired, use one format
    if ( $printable_table ) {

      ShowHTMLTable { titles=>$sth->{NAME},
	types=>$types_ref,
	widths=>$sth->{PRECISION},
	row_sub=>\&fetchNextRow,
        table_attrs=>'WIDTH=675 BORDER=1 CELLPADDING=2 CELLSPACING=2',
        title_formats=>['BOLD'],
        url_keys=>$url_cols_ref,
        hidden_cols=>$hidden_cols_ref,
        THformats=>['BGCOLOR=#C0C0C0'],
        TDformats=>['NOWRAP']
      };

    #### Otherwise, use the standard viewable format which doesn't print well
    } else {

      ShowHTMLTable { titles=>$sth->{NAME},
	types=>$types_ref,
	widths=>\@precisions,
	row_sub=>\&fetchNextRow,
        table_attrs=>'BORDER=0 CELLPADDING=2 CELLSPACING=2',
        title_formats=>['FONT COLOR=white,BOLD'],
        url_keys=>$url_cols_ref,
        hidden_cols=>$hidden_cols_ref,
        THformats=>['BGCOLOR=#0000A0'],
        TDformats=>\@TDformats,
        row_color_scheme=>$row_color_scheme_ref
      };

    }


    #### finish up
    print "\n";
    $sth->finish;

    return 1;


} # end displayQueryResult


###############################################################################
# fetchNextRow called by ShowTable
###############################################################################
sub fetchNextRow {
  my $flag = shift @_;
  #print "Entering fetchNextRow (flag = $flag)...<BR>\n";

  #### If flag == 1, just testing to see if this is rewindable
  if ($flag == 1) {
    #print "Test if rewindable: yes<BR>\n";
    return 1;
  }

  #### If flag > 1, then really do the rewind  
  if ($flag > 1) {
    #print "rewind...<BR>";
    $sth->execute;
    #print "and return.<BR>\n";
    return 1;
  }

  #### Else return the next row
  my @row = $sth->fetchrow_array;
  if (@row) {
    push(@{$resultset_ref->{data_ref}},\@row);
  }

  return @row;
}


###############################################################################
# fetchNextRow called by ShowHTMLTable
###############################################################################
sub fetchNextRowOld {
    my $flag = shift @_;
    if ($flag) {
      print "fetchNextRow: flag = $flag<BR>\n";
      return $sth->execute;
    }
    return $sth->fetchrow_array;
}


###############################################################################
# decodeDataType
###############################################################################
sub decodeDataType {
    my $self = shift;
    my $types_ref = shift || die "decodeDataType: insufficient paramaters\n";

    my %typelist = ( 1=>"varchar", 4=>"int", 2=>"numeric", 6=>"float",
      11=>"date",-1=>"text" );
    my ($i,$type,$newtype);
    my @types = @{$types_ref};
    my @newtypes;

    for ($i = 0; $i <= $#types; $i++) {
      $type = $types[$i];
      $newtype = $typelist{$type} || $type;
      push(@newtypes,$newtype);
      #print "$i: $type --> $newtype\n";
    }

    return \@newtypes;
}





#### A new way of doing things: having a resultset in memory



###############################################################################
# fetchResultSet
#
# Executes a query and loads the result into a resultset structure
###############################################################################
sub fetchResultSet {
    my $self = shift;
    my %args = @_;

    #### Process the arguments list
    my $sql_query = $args{'sql_query'} || croak "parameter sql_query missing";
    $resultset_ref = $args{'resultset_ref'};


    #### Get the database handle
    $dbh = $self->getDBHandle();

    #### Execute the query
    $sth = $dbh->prepare("$sql_query") ||
      croak("Unable to prepare query:\n".$dbh->errstr);
    my $rv  = $sth->execute ||
      croak("Unable to execute query:\n".$dbh->errstr);


    #### Decode the type numbers into type strings
    my $types_list_ref = $self->decodeDataType($sth->{TYPE});

    my @precisions = @{$sth->{PRECISION}};


    #### Prepare returned resultset
    my @resultsetdata;
    my %column_hash;
    my $element;
    $resultset_ref->{column_list_ref} = $sth->{NAME};
    my $i = 0;
    foreach $element (@{$sth->{NAME}}) {
      $column_hash{$element} = $i;
      $i++;
    }
    $resultset_ref->{column_hash_ref} = \%column_hash;
    $resultset_ref->{types_list_ref} = $types_list_ref;
    $resultset_ref->{precisions_list_ref} = \@precisions;
    $resultset_ref->{data_ref} = \@resultsetdata;
    $resultset_ref->{row_pointer} = 0;
    $resultset_ref->{row_counter} = 0;
    $resultset_ref->{page_size} = 100;


    #### Read the result set into memory
    while (fetchNextRow()) { 1; }


    #### finish up
    $sth->finish;

    return 1;


} # end fetchResultSet


###############################################################################
# displayResultSet
#
# Displays a resultset in memory as an HTML table
###############################################################################
sub displayResultSet {
    my $self = shift;
    my %args = @_;

    #### Process the arguments list
    my $url_cols_ref = $args{'url_cols_ref'};
    my $hidden_cols_ref = $args{'hidden_cols_ref'};
    my $row_color_scheme_ref = $args{'row_color_scheme_ref'};
    my $printable_table = $args{'printable_table'};
    my $max_widths_ref = $args{'max_widths'};
    my $table_width = $args{'table_width'} || "";
    $resultset_ref = $args{'resultset_ref'};
    $rs_params_ref = $args{'rs_params_ref'};
    my $column_titles_ref = $args{'column_titles_ref'};


    #### Set the display window of rows
    my $page_size = $rs_params_ref->{'page_size'} || 100;
    my $page_number = $rs_params_ref->{'page_number'} || 0;
    $resultset_ref->{row_pointer} = $page_size * $page_number;
    $resultset_ref->{row_counter} = 0;
    $resultset_ref->{page_size} = $page_size;


    #### If a row_color_scheme was not passed, create one:
    unless ($row_color_scheme_ref) {
      my %row_color_scheme;
      $row_color_scheme_ref->{header_background} = '#0000A0';
      $row_color_scheme{change_n_rows} = 3;
      my @row_color_list = ("#E0E0E0","#C0D0C0");
      $row_color_scheme{color_list} = \@row_color_list;
      $row_color_scheme_ref = \%row_color_scheme;
    }
    $row_color_scheme_ref->{header_background} = '#0000A0'
      unless ($row_color_scheme_ref->{header_background});


    my $types_ref = $resultset_ref->{types_list_ref};
    $column_titles_ref = $resultset_ref->{column_list_ref}
      unless ($column_titles_ref);


    #### Make some adjustments to the default column width settings
    my @precisions = @{$resultset_ref->{precisions_list_ref}};
    my $i;
    for ($i = 0; $i <= $#precisions; $i++) {
      #### Set the width to negative (variable)
      $precisions[$i] = (-1) * $precisions[$i];

      #### Override the width if the user specified it
      $precisions[$i] = $max_widths_ref->{$sth->{NAME}->[$i]}
        if ($max_widths_ref->{$sth->{NAME}->[$i]});

      #### Set the precision to 20 for dates (2001-01-01 00:00:01)
      $precisions[$i] = 20 if ($types_ref->[$i] =~ /date/i);

      #### Print for debugging
      #print $sth->{NAME}->[$i],"(",$types_ref->[$i],"): ",
      #  $precisions[$i],"<BR>\n";
    }


    #### If the desired output format is TSV, dump out the data that way
    if ($self->output_mode() eq 'tsv' || $self->output_mode() eq 'excel') {
      my @row;

      #### Set a very high page size if using defaults
      $resultset_ref->{page_size} = 1000000
        if ($resultset_ref->{default_values} eq 'YES');

      #### If the invocation_mode is http, provide a header
      if ($self->invocation_mode() eq 'http') {
        print "Content-type: text/tab-separated-values\n\n"
          if ($self->output_mode() eq 'tsv');
        print "Content-type: application/excel\n\n"
          if ($self->output_mode() eq 'excel');
      }

      #### Print all the rows with TABs.
      #### FIXME: Verify that there are no TABs in the data iteself!
      print join("\t",@{$resultset_ref->{column_list_ref}}),"\n";
      while (@row = returnNextRow()) {
        print join("\t",@row),"\n";
      }
      return;
    }


    #### If the desired output format is 'interactive' or 'boxtable',
    #### dump out the data that way
    if ($self->output_mode() eq 'interactive' ||
        $self->output_mode() eq 'boxtable') {

      #### Set a very high page size if not interactive and using defaults
      $resultset_ref->{page_size} = 1000000
        if ($rs_params_ref->{default_values} eq 'YES' &&
            $self->output_mode() ne 'interactive');

      #### Display the BoxTable
      ShowBoxTable{
        titles=>$column_titles_ref,
	types=>$types_ref,
	widths=>\@precisions,
	row_sub=>\&returnNextRow,
      };
      return;
    }


    #### If the desired output format is XML, dump out the data that way
    if ($self->output_mode() eq 'xml') {

      #### If the invocation_mode is http, provide a header
      if ($self->invocation_mode() eq 'http') {
        print "Content-type: text/xml\n\n";
      }

      my $identifier = $rs_params_ref->{'set_name'} || 'unknown';
      print "<?xml version=\"1.0\" standalone=\"yes\"?>\n";
      print "<resultset identifier=\"$identifier\">\n";
      my @row;
      my $irow;
      my ($value,$element);
      my $nrows = scalar(@{$resultset_ref->{data_ref}});

      for ($irow=0;$irow<$nrows;$irow++) {
        print "  <row identifier=\"$irow\"\n";
        $i=0;
        @row = @{$resultset_ref->{data_ref}->[$irow]};

        foreach $element (@{$resultset_ref->{column_list_ref}}) {
          $value = $row[$i];
          $value =~ s/\"/\'/g;
          print "    $element=\"$value\"\n";
          $i++;
        }
        print "  />\n";
      }
      print "</resultset>\n";
      return;
    }


    #### If a printable table was desired, use one format
    if ( $printable_table ) {

      ShowHTMLTable{
        titles=>$column_titles_ref,
	types=>$types_ref,
	widths=>\@precisions,
	row_sub=>\&returnNextRow,
        table_attrs=>'WIDTH=675 BORDER=1 CELLPADDING=2 CELLSPACING=2',
        title_formats=>['BOLD'],
        url_keys=>$url_cols_ref,
        hidden_cols=>$hidden_cols_ref,
        THformats=>["BGCOLOR=".$row_color_scheme_ref->{header_background}],
        TDformats=>['NOWRAP']
      };

    #### Otherwise, use the standard viewable format which doesn't print well
    } else {

      my @TDformats;
      if ($table_width) {
        if ($table_width eq 'fit_to_page') {
          @TDformats = ();
          $table_width = "";
        } else {
          $table_width = "WIDTH=$table_width";
          @TDformats=('');
        }
      } else {
        @TDformats=('NOWRAP');
      }


      ShowHTMLTable{
        titles=>$column_titles_ref,
	types=>$types_ref,
	widths=>\@precisions,
	row_sub=>\&returnNextRow,
        table_attrs=>"$table_width BORDER=0 CELLPADDING=2 CELLSPACING=2",
        title_formats=>['FONT COLOR=white,BOLD'],
        url_keys=>$url_cols_ref,
        hidden_cols=>$hidden_cols_ref,
        THformats=>["BGCOLOR=".$row_color_scheme_ref->{header_background}],
        TDformats=>\@TDformats,
        row_color_scheme=>$row_color_scheme_ref
      };

    }


    #### finish up
    print "\n";

    return 1;


} # end displayResultSet



###############################################################################
# displayResultSetControls
#
# Displays the links and form to control ResultSet display
###############################################################################
sub displayResultSetControls {
    my $self = shift;
    my %args = @_;


    #### If the output mode is not html or interactive, do not display controls
    if ($self->output_mode() ne 'html' && 
        $self->output_mode() ne 'interactive' ) {
      return;
    }


    my ($i,$element,$key,$value,$line,$result,$sql);

    #### Process the arguments list
    my $resultset_ref = $args{'resultset_ref'};
    $rs_params_ref = $args{'rs_params_ref'};
    my $query_parameters_ref = $args{'query_parameters_ref'};
    my $base_url = $args{'base_url'};

    my %rs_params = %{$rs_params_ref};
    my %parameters = %{$query_parameters_ref};


    #### Start form
    if ($self->output_mode() eq 'html') {
      print qq~
      <TABLE WIDTH="800" BORDER=0><TR><TD>
      <FORM METHOD="POST">
      ~;
    }


    #### Display the row statistics and warn the user
    #### if they're not seeing all the data
    my $start_row = $rs_params{page_size} * $rs_params{page_number} + 1;
    my $nrows = scalar(@{$resultset_ref->{data_ref}});
    print "Displayed rows $start_row - $resultset_ref->{row_pointer} of ".
      "$nrows\n\n";

    if ( $parameters{row_limit} == scalar(@{$resultset_ref->{data_ref}}) ) {
      if ($self->output_mode() eq 'html') {
        print "&nbsp;&nbsp;(<font color=red>WARNING: </font>Resultset ".
	  "truncated at $parameters{row_limit} rows. ".
	  "Increase row limit to see more.)\n";
      } else {
        print "WARNING: Resultset ".
	  "truncated at $parameters{row_limit} rows. ".
	  "Increase row limit to see more.)\n";
      }
    }


    #### If the output mode is not html, then finish here
    if ($self->output_mode() ne 'html') {
      return;
    }


    #### Provide links to the other pages of the dataset
    print "<BR>Result Page \n";
    $i=0;
    my $nrowsminus = $nrows - 1 if ($nrows > 0);
    my $npages = int($nrowsminus / $rs_params{page_size}) + 1;
    for ($i=0; $i<$npages; $i++) {
      my $pg = $i+1;
      if ($i == $rs_params{page_number}) {
        print "[<font color=red>$pg</font>] \n";
      } else {
        print "<A HREF=\"$base_url?apply_action=VIEWRESULTSET&".
          "rs_set_name=$rs_params{set_name}&".
          "rs_page_size=$rs_params{page_size}&".
          "rs_page_number=$pg\">$pg</A> \n";
      }
    }
    print "of $npages<BR>\n";


    #### Print out a form to control some variable parameters
    my $this_page = $rs_params{page_number} + 1;
    print qq~
      <INPUT TYPE="hidden" NAME="rs_set_name" VALUE="$rs_params{set_name}">
      Page Size:
      <INPUT TYPE="text" NAME="rs_page_size" SIZE=4
        VALUE="$rs_params{page_size}">
      &nbsp;&nbsp;&nbsp;&nbsp;Page Number:
      <INPUT TYPE="text" NAME="rs_page_number" SIZE=4
        VALUE="$this_page">
      <INPUT TYPE="submit" NAME="apply_action" VALUE="VIEWRESULTSET">
    ~;


    #### Supply some additional links to the Result Set
    print qq~
      <BR>Download ResultSet in Format:
      <a href="$CGI_BASE_DIR/GetResultSet.cgi/$rs_params{set_name}.tsv?rs_set_name=$rs_params{set_name}&format=tsv">TSV</a>,
      <a href="$CGI_BASE_DIR/GetResultSet.cgi/$rs_params{set_name}.xls?rs_set_name=$rs_params{set_name}&format=excel">Excel</a>
      <BR>
    ~;


    #### Supply URLs to get back to this resultset or redo this query
    my $pg = $rs_params{page_number};
    my $param_string = "";
    while ( ($key,$value) = each %{$query_parameters_ref} ) {
      if ($value) {
        $param_string .= "&" if ($param_string);
        $value = uri_escape($value);
	$value =~ s/\+/\%2b/g;
        $param_string .= "$key=$value";
      }
    }

    print qq~
      <BR><nobr>URL to
      <A HREF=\"$base_url?apply_action=VIEWRESULTSET&rs_set_name=$rs_params{set_name}&rs_page_size=$rs_params{page_size}&rs_page_number=$pg\">
      recall this result set</A>:
      $SERVER_BASE_DIR$base_url?apply_action=VIEWRESULTSET&rs_set_name=$rs_params{set_name}&rs_page_size=$rs_params{page_size}&rs_page_number=$pg</nobr>

      <nobr>URL to
      <A HREF=\"$base_url?apply_action=QUERY&$param_string\">
      re-execute this query</A>:
      $SERVER_BASE_DIR$base_url?apply_action=QUERY&$param_string</nobr>
      <BR>
    ~;


    #### Finish the form
    print qq~
      </FORM>
      </TR></TD></TABLE>
    ~;


    #### Print out some debugging information about the returned resultset:
    if (0 == 1) {
      print "<BR><BR>resultset_ref = $resultset_ref<BR>\n";
      while ( ($key,$value) = each %{$resultset_ref} ) {
        printf("%s = %s<BR>\n",$key,$value);
      }
      #print "columnlist = ",
      #  join(" , ",@{$resultset_ref->{column_list_ref}}),"<BR>\n";
      print "nrows = ",scalar(@{$resultset_ref->{data_ref}}),"<BR>\n";
      print "rs_set_name=",$rs_params{set_name},"<BR>\n";
    }


    return 1;


} # end displayResultSetControls


###############################################################################
# parseResultSetParams
#
# Parse the parameters that control the resultset navigation
###############################################################################
sub parseResultSetParams {
  my $self = shift;
  my %args = @_;

  #### Process the arguments list
  my $q = $args{'q'};


  #### Define the keywords we're looking for
  my @desired_params = ('rs_set_name','rs_page_size','rs_page_number');


  #### Parse the resultset parameters into a hash
  my %rs_params;
  my $n_params_found = $self->parse_input_parameters(
    q=>$q,parameters_ref=>\%rs_params,
    columns_ref=>\@desired_params,
    add_standard_params=>'NO');


  #### Remap them to names without the rs_.  This is crazy.
  $rs_params{set_name} = $rs_params{rs_set_name}
    if ($rs_params{rs_set_name});
  $rs_params{page_size} = $rs_params{rs_page_size}
    if ($rs_params{rs_page_size});
  $rs_params{page_number} = $rs_params{rs_page_number}
    if ($rs_params{rs_page_number});


  #### Add some defaults if nothing was provided
  unless ($rs_params{page_size} > 0) {
    $rs_params{page_size} = 50;
    $rs_params{default_values} = 'YES';
  }

  unless ($rs_params{page_number} > 0) {
    $rs_params{page_number} = 1;
    $rs_params{default_values} = 'YES';
  }


  #### The user will use a 1-based scheme, but internally switch to 0-based
  $rs_params{page_number} -= 1 if ($rs_params{page_number});


  #### Return the hash
  return %rs_params;

} # end parseResultSetParams


###############################################################################
# readResultSet
#
# Reads a resultset from a file
###############################################################################
sub readResultSet {
    my $self = shift;
    my %args = @_;

    #### Process the arguments list
    my $resultset_file = $args{'resultset_file'};
    $resultset_ref = $args{'resultset_ref'};
    my $query_parameters_ref = $args{'query_parameters_ref'};

    my $indata = "";


    #### Read in the query parameters
    my $infile = "$PHYSICAL_BASE_DIR/tmp/queries/${resultset_file}.params";
    open(INFILE,"$infile") || die "Cannot open $infile\n";
    while (<INFILE>) { $indata .= $_; }
    close(INFILE);


    #### eval the dump
    my $VAR1;
    eval $indata;
    %{$query_parameters_ref} = %{$VAR1};


    #### Read in the resultset
    #$indata = "";
    $infile = "$PHYSICAL_BASE_DIR/tmp/queries/${resultset_file}.resultset";
    %{$resultset_ref} = %{retrieve($infile)};
    #open(INFILE,"$infile") || die "Cannot open $infile\n";
    #while (<INFILE>) { $indata .= $_; }
    #close(INFILE);

    #### eval the dump
    #eval $indata;
    #%{$resultset_ref} = %{$VAR1};


    return 1;


} # end readResultSet


###############################################################################
# writeResultSet
#
# Writes a resultset to a file
###############################################################################
sub writeResultSet {
    my $self = shift;
    my %args = @_;

    #### Process the arguments list
    my $resultset_file_ref = $args{'resultset_file_ref'};
    $resultset_ref = $args{'resultset_ref'};
    my $query_parameters_ref = $args{'query_parameters_ref'};
    my $file_prefix = $args{'file_prefix'} || 'query_';


    #### If a filename was not provides, create one
    if ($$resultset_file_ref eq "SETME") {
      my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
      my $timestr = strftime("%Y%m%d-%H%M%S",$sec,$min,$hour,$mday,$mon,$year);
      $$resultset_file_ref = $file_prefix . $self->getCurrent_username() ."_" . 
	$timestr;
    }
    my $resultset_file = $$resultset_file_ref;


    #### Write out the query parameters
    my $outfile = "$PHYSICAL_BASE_DIR/tmp/queries/${resultset_file}.params";
    open(OUTFILE,">$outfile") || die "Cannot open $outfile\n";
    printf OUTFILE Data::Dumper->Dump( [$query_parameters_ref] );
    close(OUTFILE);


    #### Write out the resultset
    $outfile = "$PHYSICAL_BASE_DIR/tmp/queries/${resultset_file}.resultset";
    store($resultset_ref,$outfile);
    #open(OUTFILE,">$outfile") || die "Cannot open $outfile\n";
    #$Data::Dumper::Indent = 0;
    #printf OUTFILE Data::Dumper->Dump( [$resultset_ref] );
    #close(OUTFILE);


    return 1;


} # end writeResultSet


###############################################################################
# returnNextRow called by ShowTable
###############################################################################
sub returnNextRow {
  my $flag = shift @_;
  #print "Entering returnNextRow (flag = $flag)...<BR>\n";

  #### If flag == 1, just testing to see if this is rewindable
  if ($flag == 1) {
    #print "Test if rewindable: yes<BR>\n";
    return 1;
  }

  #### If flag > 1, then really do the rewind  
  if ($flag > 1) {
    #print "rewind...<BR>";
    $resultset_ref->{row_counter} = 0;
    $resultset_ref->{row_pointer} = $rs_params_ref->{page_size} * 
      $rs_params_ref->{page_number};
    #print "and return.<BR>\n";
    return 1;
  }

  #### Else return the next row
  my @row;
  my $irow = $resultset_ref->{row_pointer};
  my $nrows = scalar(@{$resultset_ref->{data_ref}});
  my $nrow = $resultset_ref->{row_counter};
  my $page_size = $resultset_ref->{page_size};
  if ($irow < $nrows && $nrow < $page_size) {
    (@row) = @{$resultset_ref->{data_ref}->[$irow]};
    $resultset_ref->{row_pointer}++;
    $resultset_ref->{row_counter}++;
  }

  return @row;
}



###############################################################################
# processTableDisplayControls
#
# Displays and processes a set of crude table display controls
##############################################################################
sub processTableDisplayControls {
    my $self = shift;
    my $TABLE_NAME = shift;

    my $detail_level  = $q->param('detail_level') || "BASIC";
    my $where_clause  = $q->param('where_clause');
    my $orderby_clause  = $q->param('orderby_clause');

    if ( $where_clause =~ /delete|insert|update/i ) {
      croak "Syntax error in WHERE clause"; }
    if ( $orderby_clause =~ /delete|insert|update/i ) {
      croak "Syntax error in ORDER BY clause"; }

    my $full_orderby_clause;
    my $full_where_clause;
    $full_where_clause = "AND $where_clause" if ($where_clause);
    $full_orderby_clause = "ORDER BY $orderby_clause" if ($orderby_clause);

    # If a user typed ", he probably meant ' instead, so replace since "
    # will fail.  This is a bit rude, because what if the user really meant "
    # then he should use [ and ]
    $full_where_clause =~ s/"/'/g;  #### "
    $full_orderby_clause =~ s/"/'/g;  #### "

    # If a user typed ", we need to escape them for the form printing
    $where_clause =~ s/"/&#34;/g;
    $orderby_clause =~ s/"/&#34;/g;


    my $basic_flag = "";
    my $full_flag = "";
    $basic_flag = " SELECTED" if ($detail_level eq "BASIC");
    $full_flag = " SELECTED" if ($detail_level eq "FULL");

    print qq!
        <BR><HR SIZE=5 NOSHADE><BR>
        <FORM METHOD="post">
            <SELECT NAME="detail_level">
              <OPTION$basic_flag VALUE="BASIC">BASIC
              <OPTION$full_flag VALUE="FULL">FULL
            </SELECT>
        <B>WHERE</B><INPUT TYPE="text" NAME="where_clause"
                     VALUE="$where_clause" SIZE=25>
        <B>ORDER BY</B><INPUT TYPE="text" NAME="orderby_clause"
                     VALUE="$orderby_clause" SIZE=25>
        <INPUT TYPE="hidden" NAME="TABLE_NAME" VALUE="$TABLE_NAME">
        <INPUT TYPE="submit" NAME="redisplay" VALUE="DISPLAY"><P>
    !;


    return ($full_where_clause,$full_orderby_clause);

} # end processTableDisplayControls


###############################################################################
# convertSingletoTwoQuotes
#
# Converts all instances of a single quote to two consecutive single
# quotes as wanted by an SQL string already enclosed in single quotes
###############################################################################
sub convertSingletoTwoQuotes {
  my $self = shift;
  my $string = shift;

  return if (! defined($string));
  return '' if ($string eq '');
  return 0 unless ($string);

  my $resultstring = $string;
  $resultstring =~ s/'/''/g;  ####'

  return $resultstring;
} # end convertSingletoTwoQuotes



###############################################################################
# parse_input_parameters
#
# Parse the available input parameters (which may come via CGI or via
# the command line) into the %parameters hash
###############################################################################
sub parse_input_parameters {
  my $self = shift;
  my %args = @_;


  #### Process the arguments list
  my $q = $args{'q'};
  my $ref_parameters = $args{'parameters_ref'};
  my $ref_columns = $args{'columns_ref'} || [];
  my $ref_input_types = $args{'input_types_ref'} || {};
  my $add_standard_params = $args{'add_standard_params'} || 'YES';


  #### Define some generic varibles
  my ($i,$element,$key,$value,$line,$result,$sql);


  #### Set a counter for the number of paramters found
  my $n_params_found = 0;
  my $n_CGI_params_found = 0;
  my $n_cmdln_params_found = 0;


  #### Resolve the keys from the command line if any
  my %cmdln_parameters;
  foreach $element (@ARGV) {
    if ( ($key,$value) = split("=",$element) ) {
      #print "$key = $value\n";
      $cmdln_parameters{$key} = $value;
    } else {
      print "ERROR: Unable to parse '$element'\n";
      return;
    }
  }


  #### Add a set of standard set of input options
  my @columns = @{$ref_columns};
  if ($add_standard_params eq 'YES') {
    push(@columns,'apply_action','action','output_mode','TABLE_NAME',
      'QUERY_NAME','navigation_bar');
  }


  #### Read the form values for each of the desired parameters
  foreach $element (@columns) {

    my $value;

    #### If the type is a multioptionlist, extract as an array but
    #### turn into a comma separated list
    my $input_type = $ref_input_types->{$element} || '';
    if ($input_type eq "multioptionlist") {
      my @tmparray = $q->param($element);

      #### Remove any leading or trailing blank items
      if (scalar(@tmparray) > 1) {
        pop @tmparray unless ($tmparray[$#tmparray]);
        shift @tmparray unless ($tmparray[0]);
      }

      #### Convert to a comma separated list
      $value = join(",",@tmparray);


    #### Otherwise just extract as is
    } else {
      $value = $q->param($element);
    }


    #### If something was recovered, note it
    if ($value) {
      $n_CGI_params_found++;
      $ref_parameters->{$element} = $value;

    #### See if we can pull it out of %OPTIONS
    } elsif ($cmdln_parameters{$element}) {
      $value = $cmdln_parameters{$element};
      if ($value) {
        $n_cmdln_params_found++;
        $ref_parameters->{$element} = $value;
      }

    #### Otherwise we didn't find this parameter
    } else {
    }

  }


  #### Sum the total parameters found
  $n_params_found = $n_CGI_params_found + $n_cmdln_params_found;


  #### If some CGI parameters were found, assume we're doing a web interface
  if ($n_CGI_params_found) {
    $self->invocation_mode('http');
    print "ERROR: Dual mode parameters?\n" if ($n_cmdln_params_found);
  }


  #### If some command line parameters were found, assume we were invoked
  #### from the command line unless we already have a mode.  Do not
  #### override an existing mode, because we will allow a faked web
  #### mode from the command line
  if ($n_cmdln_params_found) {
    unless ($self->invocation_mode()) {
      $self->invocation_mode('user');
    }
  }


  if ($ref_parameters->{output_mode}) {
    $self->output_mode($ref_parameters->{output_mode});
  }


  return $n_params_found;

} # end parse_input_parameters



###############################################################################
# display_input_form
#
# Print the parameter input form for this particular table or query
###############################################################################
sub display_input_form {
  my $self = shift;
  my %args = @_;


  #### If the output mode is not html, then we don't want a form
  if ($self->output_mode() ne 'html') {
    return;
  }


  #### Process the arguments list
  my $TABLE_NAME = $args{'TABLE_NAME'};
  my $CATEGORY = $args{'CATEGORY'};
  my $PROGRAM_FILE_NAME = $args{'PROGRAM_FILE_NAME'};
  my $apply_action = $args{'apply_action'};
  my $parameters_ref = $args{'parameters_ref'};
  my %parameters = %{$parameters_ref};
  my $input_types_ref = $args{'input_types_ref'};
  my %input_types = %{$input_types_ref};
  my $mask_user_context = $args{'mask_user_context'};


  #### Define popular variables
  my ($i,$element,$key,$value,$line,$result,$sql);
  my $PK_COLUMN_NAME;
  my ($row);


  #### Query to obtain column information about this table or query
  $sql = qq~
      SELECT column_name,column_title,is_required,input_type,input_length,
             is_data_column,is_display_column,column_text,
             optionlist_query,onChange
        FROM $TB_TABLE_COLUMN
       WHERE table_name='$TABLE_NAME'
         AND is_data_column='Y'
       ORDER BY column_index
  ~;
  my @columns_data = $self->selectSeveralColumns($sql);


  # First just extract any valid optionlist entries.  This is done
  # first as opposed to within the loop below so that a single DB connection
  # can be used.
  # THIS IS LEGACY AND NO LONGER A USEFUL REASON TO DO SEPARATELY
  my %optionlist_queries;
  my $file_upload_flag = "";
  foreach $row (@columns_data) {
    my @row = @{$row};
    my ($column_name,$column_title,$is_required,$input_type,$input_length,
        $is_data_column,$is_display_column,$column_text,
        $optionlist_query,$onChange) = @row;
    if ($optionlist_query gt "") {
      $optionlist_queries{$column_name}=$optionlist_query;
    if ($input_type eq "file") {
      $file_upload_flag = "ENCTYPE=\"multipart/form-data\""; }
    }
  }


  # There appears to be a Netscape bug in that one cannot [BACK] to a form
  # that had multipart encoding.  So, only include form type multipart if
  # we really have an upload field.  IE users are fine either way.
  $self->printUserContext() unless ($mask_user_context);
  print qq!
      <P>
      <H2>$CATEGORY</H2>
      $LINESEPARATOR
      <FORM METHOD="post" ACTION="$PROGRAM_FILE_NAME" $file_upload_flag>
      <TABLE>
  !;


  # ---------------------------
  # Build option lists for each optionlist query provided for this table
  my %optionlists;
  foreach $element (keys %optionlist_queries) {

      # If "$contact_id" appears in the SQL optionlist query, then substitute
      # that with either a value of $parameters{contact_id} if it is not
      # empty, or otherwise replace with the $current_contact_id
      if ( $optionlist_queries{$element} =~ /\$contact_id/ ) {
        if ( $parameters{"contact_id"} eq "" ) {
          my $current_contact_id = $self->getCurrent_contact_id();
          $optionlist_queries{$element} =~
              s/\$contact_id/$current_contact_id/;
        } else {
          $optionlist_queries{$element} =~
              s/\$contact_id/$parameters{contact_id}/;
        }
      }


      # If "$project_id" appears in the SQL optionlist query, then substitute
      # that with either a value of $parameters{project_id} if it is not
      # empty, or otherwise replace with the $current_project_id
      if ( $optionlist_queries{$element} =~ /\$project_id/ ) {
        if ( $parameters{"project_id"} eq "" ) {
          my $current_project_id = $self->getCurrent_project_id();
          $optionlist_queries{$element} =~
              s/\$project_id/$current_project_id/;
        } else {
          $optionlist_queries{$element} =~
              s/\$project_id/$parameters{project_id}/;
        }
      }


      #### Evaluate the $TBxxxxx table name variables if in the query
      if ( $optionlist_queries{$element} =~ /\$TB/ ) {
        $optionlist_queries{$element} = 
          main::evalSQL($optionlist_queries{$element});
      }


      #### Set the MULTIOPTIONLIST flag if this is a multi-select list
      my $method_options;
      $method_options = "MULTIOPTIONLIST"
        if ($input_types{$element} eq "multioptionlist");

      # Build the option list
      $optionlists{$element}=$self->buildOptionList(
         $optionlist_queries{$element},$parameters{$element},$method_options);
  }


  #### Now loop through again and write the HTML
  foreach $row (@columns_data) {
    my @row = @{$row};
    my ($column_name,$column_title,$is_required,$input_type,$input_length,
        $is_data_column,$is_display_column,$column_text,
        $optionlist_query,$onChange) = @row;


    #### Set the JavaScript onChange string if supplied
    if ($onChange gt "") {
      $onChange = " onChange=\"$onChange\"";
    }


    #### If the action included the phrase HIDE, don't print all the options
    if ($apply_action =~ /HIDE/i) {
      print qq!
        <TD><INPUT TYPE="hidden" NAME="$column_name"
         VALUE="$parameters{$column_name}"></TD>
      !;
      next;
    }


    #### If some level of detail is chosen, don't show this constraint if
    #### it doesn't meet the detail requirements
    #print "input_form_format = ",$parameters{input_form_format},", - - ",
    #  "is_display_column = ",$is_display_column,"<BR>\n";
    if (defined($parameters{input_form_format})) {
      if ( ($parameters{input_form_format} eq 'minimum_detail'
                     && $is_display_column ne 'Y') ||
           ($parameters{input_form_format} eq 'medium_detail'
                     && $is_display_column eq '2')
         ) {

        #### And finally if there's not a value in it, then hide it
        unless ($parameters{$column_name}) {
          print qq!
            <TD><INPUT TYPE="hidden" NAME="$column_name"
             VALUE="$parameters{$column_name}"></TD>
          !;
          next;
        }
      }
    }


    #### Write the parameter name, in red if required
    if ($is_required eq "N") {
      print "<TR><TD><B>$column_title:</B></TD>\n";
    } else {
      print "<TR><TD><B><font color=red>$column_title:</font></B></TD>\n";
    }


    if ($input_type eq "text") {
      print qq!
        <TD><INPUT TYPE="$input_type" NAME="$column_name"
         VALUE="$parameters{$column_name}" SIZE=$input_length $onChange></TD>
      !;
    }


    if ($input_type eq "file") {
      print qq!
        <TD><INPUT TYPE="$input_type" NAME="$column_name"
         VALUE="$parameters{$column_name}" SIZE=$input_length $onChange>
      !;
      if ($parameters{$column_name}) {
        print qq!
          <A HREF="$DATA_DIR/$parameters{$column_name}">view file</A>
        !;
      }
      print qq!
         </TD>
      !;
    }


    if ($input_type eq "password") {

      # If we just loaded password data from the database, and it's not
      # a blank field, the replace it with a special entry that we'll
      # look for and decode when it comes time to UPDATE.
      if ($parameters{$PK_COLUMN_NAME} gt "" && $apply_action ne "REFRESH") {
        if ($parameters{$column_name} gt "") {
          $parameters{$column_name}="**********".$parameters{$column_name};
        }
      }

      print qq!
        <TD><INPUT TYPE="$input_type" NAME="$column_name"
         VALUE="$parameters{$column_name}" SIZE=$input_length></TD>
      !;
    }


    if ($input_type eq "fixed") {
      print qq!
        <TD><INPUT TYPE="hidden" NAME="$column_name"
         VALUE="$parameters{$column_name}">$parameters{$column_name}</TD>
      !;
    }

    if ($input_type eq "textarea") {
      print qq!
        <TD><TEXTAREA NAME="$column_name" rows=$input_length cols=40>$parameters{$column_name}</TEXTAREA></TD>
      !;
    }

    if ($input_type eq "textdate") {
      if ($parameters{$column_name} eq "") {
        my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time());
        $year+=1900; $mon+=1;
        $parameters{$column_name} = "$year-$mon-$mday $hour:$min";
      }
      print qq!
        <TD><INPUT TYPE="text" NAME="$column_name"
         VALUE="$parameters{$column_name}" SIZE=$input_length>
        <INPUT TYPE="button" NAME="${column_name}_button"
         VALUE="NOW" onClick="ClickedNowButton($column_name)">
         </TD>
      !;
    }

    if ($input_type eq "optionlist") {
      print qq~
        <TD><SELECT NAME="$column_name" $onChange>
          <!-- $parameters{$column_name} -->
        <OPTION VALUE=""></OPTION>
        $optionlists{$column_name}</SELECT></TD>
      ~;
    }

    if ($input_type eq "scrolloptionlist") {
      print qq!
        <TD><SELECT NAME="$column_name" SIZE=$input_length $onChange>
        <OPTION VALUE=""></OPTION>
        $optionlists{$column_name}</SELECT></TD>
      !;
    }

    if ($input_type eq "multioptionlist") {
      print qq!
        <TD><SELECT NAME="$column_name" MULTIPLE SIZE=$input_length $onChange>
        <OPTION VALUE=""></OPTION>
        $optionlists{$column_name}</SELECT></TD>
      !;
    }

    if ($input_type eq "current_contact_id") {
      my $username = "";
      my $current_username = $self->getCurrent_username();
      my $current_contact_id = $self->getCurrent_contact_id();
      if ($parameters{$column_name} eq "") {
          $parameters{$column_name}=$current_contact_id;
          $username=$current_username;
      } else {
          if ( $parameters{$column_name} == $current_contact_id) {
            $username=$current_username;
          } else {
            $username=$self->getUsername($parameters{$column_name});
          }
      }
      print qq!
        <TD><INPUT TYPE="hidden" NAME="$column_name"
         VALUE="$parameters{$column_name}">$username</TD>
      !;
    }

  print qq!
    <TD BGCOLOR="E0E0E0">$column_text</TD></TR>
  !;


  }


} # end display_input_form



###############################################################################
# display_form_buttons
#
# Display the parameter form buttons for this particular table or query
###############################################################################
sub display_form_buttons {
  my $self = shift;
  my %args = @_;


  #### Process the arguments list
  my $TABLE_NAME = $args{'TABLE_NAME'};


  #### If the output mode is not html, then we don't want anything
  if ($self->output_mode() ne 'html') {
    return;
  }


  #### Show the QUERY, REFRESH, and Reset buttons
  print qq~
      <INPUT TYPE="hidden" NAME="QUERY_NAME" VALUE="$TABLE_NAME">
      <TR><TD COLSPAN=2>
      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
      <INPUT TYPE="submit" NAME="action" VALUE="QUERY">
      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
      <INPUT TYPE="submit" NAME="action" VALUE="REFRESH">
      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
      <INPUT TYPE="reset"  VALUE="Reset">
       </TR></TABLE>
       </FORM>
  ~;

} # end display_form_buttons



###############################################################################
# display_sql
#
# Display the actual SQL used (if desired and permitted)
###############################################################################
sub display_sql {
  my $self = shift;
  my %args = @_;


  #### Process the arguments list
  my $sql = $args{'sql'} || '';


  #### Strip out blank lines
  while ($sql =~ s/\n[ ]+\n/\n/g) {};


  #### Define prefix and suffix based on output format
  my $prefix = '';
  my $suffix = '';
  if ($self->output_mode eq 'html') {
    $prefix = '<PRE>';
    $suffix = '</PRE><BR>';
  }


  #### Display the SQL used
  print "$prefix$sql$suffix\n";


} # end display_sql


###############################################################################
# build_SQL_columns_list
#
# Build the columns list for a SQL statement
###############################################################################
sub build_SQL_columns_list {
  my $self = shift;
  my %args = @_;
  my $METHOD = 'build_SQL_columns_list';


  #### Process the arguments list
  my $column_array_ref = $args{'column_array_ref'} ||
    die "$METHOD: column_array_ref not passed!";
  my $colnameidx_ref = $args{'colnameidx_ref'} ||
    die "$METHOD: colnameidx_ref not passed!";
  my $column_titles_ref = $args{'column_titles_ref'} ||
    die "$METHOD: column_titles_ref not passed!";

  my $columns_clause = "";
  my $element;
  my $i = 0;
  foreach $element (@{$column_array_ref}) {
    $columns_clause .= "," if ($columns_clause);
    $columns_clause .= qq ~
           $element->[1] AS '$element->[0]'~;
    $colnameidx_ref->{$element->[0]} = $i;
    push(@{$column_titles_ref},$element->[2]);
    $i++;
  }


  #### Return result
  return $columns_clause;

} # end build_SQL_columns_list


###############################################################################
# transferTable
#
# Given a SQL query and how to map the data from one table to another,
# copy data from one table to another
###############################################################################
sub transferTable {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;

  #### Decode the argument list
  my $src_conn = $args{'src_conn'};
  my $sql = $args{'sql'};
  my $source_file = $args{'source_file'};
  my $delimiter = $args{'delimiter'} || "\t";
  my $comment_char = $args{'comment_char'};
  my $skip_lines = $args{'skip_lines'} || 0;
  die ("either sql or source_file must be passed")
    unless ($sql || $source_file);
  die ("parameters sql and source_file cannot both be passed")
    if ($sql && $source_file);
  my $src_PK_name = $args{'src_PK_name'} || '';
  my $src_PK_column = $args{'src_PK_column'};
  $src_PK_column = -1 unless (defined($src_PK_column));
  if ($sql) {
    die ("parameter src_PK_name must be passed if sql is passed")
      unless ($src_PK_name);
    die("parameter src_PK_column must be passed if sql is passed")
      unless ($src_PK_column>=0);
  }

  my $dest_conn = $args{'dest_conn'} || die "ERROR: dest_conn not passed";
  my $column_map_ref = $args{'column_map_ref'}
    || die "ERROR: column_map_ref not passed";
  my $transform_map_ref = $args{'transform_map_ref'}
    || die "ERROR: transform_map_ref not passed";
  my $newkey_map_ref = $args{'newkey_map_ref'};

  my $table_name = $args{'table_name'} || die "ERROR: table_name not passed";
  my $dest_PK_name = $args{'dest_PK_name'} || '';

  my $update = $args{'update'} || 0;
  my $update_keys_ref = $args{'update_keys_ref'};

  my $verbose = $args{'verbose'} || 0;
  my $testonly = $args{'testonly'} || 0;


  #### Define standard variables
  my ($i,$element,$key,$value,$line,$result);
  my @rows;

  #### Get data from source
  #### Execute source query if sql is set
  if ($sql) {
    print "\n  Getting data from source...";
    @rows = $src_conn->selectSeveralColumns($sql);
  }


  #### Read from file if src_file is set
  if ($source_file) {
    print "\n  Loading data from file...";
    @rows = $self->importTSVFile(source_file=>$source_file,
      delimiter=>$delimiter,
      skip_lines=>$skip_lines,
      comment_char=>$comment_char);
  }


  my %rowdata;
  my $row;
  my %newkays;


  print "\n  Loading data into destination";
  foreach $row (@rows) {
    %rowdata = ();

    while ( ($key,$value) = each %{$column_map_ref} ) {
      if (defined($row->[$key])) {
  	if ($transform_map_ref->{$key}) {
  	  my $current_value = $row->[$key];
  	  my $mapped_value = $transform_map_ref->{$key}->{$current_value};
  	  if (defined($mapped_value)) {
  	    $rowdata{$value} = $mapped_value;
  	  } else {
  	    print "Unable to transform column $key having value ".
              "'$current_value'\n";
  	  }
  	} else {
  	  $rowdata{$value} = $row->[$key];
  	}

      }

    }


    #### Logic to control whether we want returned PKs or not
    my $return_PK = 0;
    $return_PK = 1 if ($dest_PK_name);


    #### If the update flag is set, then try to find out which record to update
    my $did_update = 0;
    if ($update) {
      my @constraints;
      my $constraints_str;
      while ( ($key,$value) = each %{$update_keys_ref} ) {
        push(@constraints,"$key = '".$row->[$value]."'");
      }
      if (@constraints) {
        $constraints_str = join(" AND ",@constraints);
        $sql = qq~
          SELECT $dest_PK_name
            FROM $table_name
           WHERE $constraints_str
        ~;

        #print $sql;
        my @results = $self->selectOneColumn($sql);

        #### If there is one matching record
        if (scalar(@results) == 1) {
          $result = $dest_conn->insert_update_row(update=>1,
            table_name=>$table_name,
            rowdata_ref=>\%rowdata,
            PK=>$dest_PK_name,PK_value=>$results[0],
            return_PK=>$return_PK,
            verbose=>$verbose,
            testonly=>$testonly,
          );
          $did_update = 1;

        #### If there's more than one, then complain and exit
        } elsif (scalar(@results) > 1) {
          print "ERROR: Found more than one record matching $constraints_str";
          return;

        #### If there are none, then assume we will INSERT
        } else {
          $did_update = 0;
	}
      }
    }


    #### If we didn't do an update operation, do an INSERT
    if ($did_update == 0) {
      $result = $dest_conn->insert_update_row(insert=>1,
  	table_name=>$table_name,
  	rowdata_ref=>\%rowdata,
  	PK=>$dest_PK_name,return_PK=>$return_PK,
        verbose=>$verbose,
        testonly=>$testonly,
      );
    }

    print ".";

    if ($dest_PK_name && $result) {
      $newkey_map_ref->{$row->[$src_PK_column]} = $result;
    }

  }

  return 1;

} # end transferTable



###############################################################################
# importTSVFile: Import data from a delimited file into an array of arrays
###############################################################################
sub importTSVFile {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;


  my $SUB_NAME = "importTSVFile";

  my ($i,$VERBOSE,$line,$line_number);

  #### Decode the argument list
  my $source_file = $args{'source_file'};
  my $delimiter = $args{'delimiter'};
  my $comment_char = $args{'comment_char'};
  my $skip_lines = $args{'skip_lines'} || 0;

  my @rows;


  #### If a source_file was specified
  if ($source_file) {

    #### Determine if the specified file exists
    unless ( -e "$source_file" ) {
      mydie("Cannot find file '$source_file'");
    }


    #### Open source file
    unless (open(INFILE,"$source_file")) {
      mydie("Cannot open file '$source_file'");
    }
    my $input_source = \*INFILE;


    #### Skip a number of lines if desired
    if ($skip_lines > 0) {
      $i=0;
      print "Skipping $skip_lines lines...\n" if ($VERBOSE);
      while ($line=<INFILE>) {
        $i++;
        last if ($i >= $skip_lines);
      }
    }

  }

  #### Loop over all data in the file
  while ($line = <INFILE>) {
    $line_number++;

    #### Strip CRs of all flavors
    $line =~ s/[\n\r]//g;

    #### Skip line if it's a comment
    next if ($comment_char && $line =~ /^$comment_char/);

    #### Split the line into columns
    my @splitline = split(/$delimiter/,$line);

    #### Decode the enquoted values if any
    my $n_columns = @splitline;
    for ($i=0; $i<$n_columns; $i++) {
      if ($splitline[$i] =~ /^\"(.*)\"$/) {
        $splitline[$i] = $1;
      }
    }

    #### Add onto the rows array
    push(@rows,\@splitline);

  }


  return @rows;

} # end importTSVFile


###############################################################################
# unix2dosFile: For compatibility, always revert to the DOS version of carriage
#               returns.
###############################################################################
sub unix2dosFile {
  my $self = shift || croak("parameter self not passed");
  my %configuration = @_;
  my $SUB_NAME = "unix2dosFile";

  my ($i,$VERBOSE,$line,$line_number);

  #### Decode the argument list
  my $file = $configuration{'file'};

  open (INFILE,"$file")  || die "Cannot open file '$file'";
  open (DOSFILE,">$file.dos")  || die "Cannot open file '$file.dos'";

  #### Loop over all data in the file
  while ($line = <INFILE>) {

    #### Strip CRs of all flavors
    $line =~ s/[\n\r]//g;

    #### Add a DOS type carriage return
    $line =~ s/$/\r\n/;

    print DOSFILE $line;
  }

  close INFILE;
  close DOSFILE;

  rename("$file.dos","$file");

} # end unix2dosFile



###############################################################################
# getModules: Get the list of Modules available to us
###############################################################################
sub getModules {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;


  #### Try to read the available modules file
  my @modules;
  @modules = $self->readModuleFile(
    source_file=>"$PHYSICAL_BASE_DIR/lib/conf/Core/AvailableModules.conf");

  #### Try to read the main distributed modules file
  unless (@modules) {
    @modules = $self->readModuleFile(
      source_file=>"$PHYSICAL_BASE_DIR/lib/conf/Core/Modules.conf");
  }


  #### Return whatever we got
  return @modules;

} # end getModules



###############################################################################
# readModuleFile: Get the list of Modules available to us
###############################################################################
sub readModuleFile {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;


  #### Define some basic stuff
  my $SUB_NAME = 'readModuleFile';
  my ($i,$line);


  #### Decode the argument list
  my $source_file = $args{'source_file'}
    || die "$SUB_NAME: Must provide a source_file";
  my $verbose = $args{'verbose'} || 0;


  #### Verify the existence of the file
  return unless ($source_file);
  unless ( -e $source_file ) {
    print "$SUB_NAME: source_file '$source_file' does not exist\n"
      if ($verbose);
    return;
  }


  #### Open the file
  unless (open(INFILE,"$source_file")) {
    die("$SUB_NAME: Cannot open source_file '$source_file'");
  }


  #### Read in all the modules
  my @modules = ();
  while ($line = <INFILE>) {
    $line =~ s/[\r\n]//g;
    next if ($line =~ /^\#/);
    next if ($line =~ /^\s+$/);
    next unless ($line);
    push(@modules,$line);
  }
  close(INFILE);


  #### Return whatever we got
  return @modules;

} # end readModuleFile





###############################################################################

1;

__END__

###############################################################################
###############################################################################
###############################################################################

=head1 SBEAMS::Connection::DBInterface

SBEAMS Core database interface module.

=head2 SYNOPSIS

See SBEAMS::Connection for usage synopsis.

=head2 DESCRIPTION

This module provides a set of methods for interacting with the RDBMS
back end with the goal that all SQL queries and statements in any
other module or script be database-engine independent.  Any
operations which depend on the brand of RDMBS (SQL Server, DB2, Oracle,
MySQL, PostgreSQL, etc.) should be abstracted through a method in
this module.


=head2 METHODS

=over

=item * B<applySqlChange()>

This method is olde and krusty and should be replaced/updated


=item * B<selectOneColumn($sql)>

Given an SQL query in the first parameter as a string, this method
executes the query and returns an array containing the first column of
the resultset of that query.

my @array = selectOneColumn("SELECT last_name FROM contact");

PITFALL ALERT:  If you want to return a single scalar value from a query
(e.g. SELECT last_name WHERE social_sec_no = '123-45-6789'), you must write:

  my ($value) = selectOneColumn($sql);

instead of:

  my $value = selectOneColumn($sql);

otherwise you will end up with the number of returned rows
instead of the value!


=item * B<selectSeveralColumns($sql)>

Given an SQL query in the first parameter as a string, this method
executes the query and returns an array containing references to arrays
containing the data for each row in the resultset of that query.

  my @array = selectSeveralColumns("SELECT * FROM contact");


=item * B<selectHashArray($sql)>

Given an SQL query in the first parameter as a string, this method
executes the query and returns an array containing references to hashes
containing the column names data for each row in the resultset of that query.

  my @array = selectHashArray("SELECT * FROM contact");


=item * B<selectTwoColumnHash($sql)>

Given an SQL query in the first parameter as a string, this method
executes the query and returns a hash containing the values of the second
column keyed on the first column for all data in the resultset of that query.
If there is a duplication of the first column value in the resultset, the
original value in the second column is lost.

  my %hash = selectTwoColumnHash("SELECT contact_id,last_name FROM contact");


=item * B<insert_update_row(several key value parameters)>

This method builds either an INSERT or UPDATE SQL statement based on the
supplied parameters and executes the statement.

table_name => Name of the table to be affected

rowdata_ref => Reference to a hash containing the column names and value
to be INSERTed or UPDATEd

database_name => Prefix to be stuck before the table name to fully
qualify the table to be affected

insert => TRUE if the data should be INSERTed as a new row

update => TRUE if the data should be used to UPDATE an existing row.
Note that at present exactly one of insert or update should be TRUE.  An
error is returned if this is not true.  This behavior should be modified
so that both TRUE means "look for record to UPDATE and if not found, then
INSERT the data".

verbose => If TRUE, print out diagnostic information including SQL

testonly => Do not actually execute the SQL, just build it

PK => specifies the Primary Key column of the table to be affected

PK_value => Specifies the Primary Key column value to be UPDATEd

return_PK => If TRUE, the Primary Key of the just INSERTed or UPDATEd
    row is returned instead of 1 for success.  Note that after INSERTions,
    determining the PK value that was just INSERTED usually requires a
    second SQL operation (engine specific!) so do not set this flag
    needlessly if speed is important.

  my %rowdata;
  $rowdata{first_name} = "Pikop";
  $rowdata{last_name} = "Andropov";
  my $contact_id = $sbeams->insert_update_row(insert=>1,
    table_name => "contact", rowdata_ref => \%rowdata,
    PK=>"contact_id", return_PK=>1,
    #verbose=>1,
    #testonly=>1
    );

  %rowdata = ();
  $rowdata{phone_number} = "123-456-7890";
  $rowdata{email} = "SpamMeSenseless@hotmail.com";
  my $result = $sbeams->insert_update_row(update=>1,
    table_name => "contact", rowdata_ref => \%rowdata,
    PK=>"contact_id", PK_value=>$contact_id,
    #verbose=>1,
    #testonly=>1
    );


=item * B<executeSQL($sql)>

Given an SQL query in the first parameter as a string, this method
executes the query and returns the return value of the $dbh->do() which
is just a scalar not a resultset.  This method should normally not be
used by ordinary user code.  User code should probably be calling some
functions like insert_update_row() or methods that update indexes or
something like that.

  executeSQL("EXEC sp_flushbuffers");


=item * B<getLastInsertedPK(several key value parameters)>

After insertion of a row into the database into a table with an auto
generated primary key, it is often necessary to retrieve the value of
that identifier for subsequent INSERTs into other tables.  Note that
the method of doing this varies wildly from database engine to engine.
Currently, this has been implemented for MS SQL Server, MySQL, and
PostgreSQL.

table_name => Name of the table for which the key is desired

PK_column_name => Primary key column name that needs to be fetched

  my $contact_id = getLastInsertedPK(table_name=>"contact",
    PK_column_name=>"contact_id");

Note that some databases support functionality where the user can just
say "give me that last auto gen key generated".  Others do not provide
this and a more complex query needs to be executed to determine this.
Thus is is always a good idea to provide the table_name and PK_column_name
if at all possible because some engines need it.  These values are not
required and if you are using SQL Server, you can get away without supplying
these.  But get in the habit of supplying this information for portability.


=item * B<parseConstraint2SQL(several key value parameters)>

Given human-entered constraint, convert it to a SQL "AND" clause with some
suitable checking to make sure the user is not trying to enter something
bogus.

constraint_column => Column name that the constraint affects

constraint_type => Data type that the text string should be converted to.
This can be one of:

  int             A single integer

  flexible_int    A flexible constraint integer like "55", ">55", "<55",
                  ">=55", "<=55", "between 55 and 60", "55+-2"

  flexible_float  A flexible constraint floating number with options as
                  above like "55.22 +- 0.10", etc.

  int_list        A comma-separated list of integers like "3,+4,-5, 6"

  plain_text      Plain unparsed text put within "LIKE ''".  Any single
                  quotes in the string are converted to two.

constraint_name => Friendly name for the constraint for error messages

constraint_value => Text that the user typed in to be parsed

verbose => Set to 1 for additional debugging output


=item * B<buildOptionList($sql,$selected_option,$method_options)>

Given an SQL query in the first parameter as a string, this method
issues the query and prints a <SELECT> list using the first and second
column.  Some additional options allows list boxes or scrolled lists.
This method does things the manual way and should probably be replaced
with use of CGI.pm popup_menu() and scrolled_list() methods.

$sql => SQL query returning two columns, the values and labels of the list

$selected_option => the value of the selected option or a comma-separated list
of selcted options

$method_options => one or flags as a string (ew).  At present, only
MULTIOPTIONLIST is supported.  It allows multiple options to be selected.


=item * B<getRecordStatusOptions($selected_option)>

Print a <SELECT> list of the standard record status options.  Set
$selected_option to make one the selected option.


=item * B<DisplayQueryResult(several key value parameters)>

This method executies the supplied SQL query and prints the result as
an HTML table.  The resultset can also be returned via the reference
parameter resultset_ref.  This should probably be updated to use the
more granular methods that follow.  Parameters:

sql_query => SQL query that will yield the resultset to display
url_cols_ref => a reference to a URL columns hash to be passed to ShowTable
hidden_cols_ref => a reference to a hash containing hidden columns
row_color_scheme_ref => reference to a row color scheme structure
printable_table => set to 1 if the table should be suitable for printing
max_widths => hash of maximum widths
resultset_ref = reference to a resultset structure that gets returned


=item * B<fetchNextRow>


=item * B<fetchNextRowOld>


=item * B<decodeDataType>


=item * B<fetchResultSet>


=item * B<displayResultSet>


=item * B<displayResultSetControls>


=item * B<readResultSet>


=item * B<writeResultSet>


=item * B<returnNextRow>


=item * B<processTableDisplayControls>


=item * B<convertSingletoTwoQuotes>




=back

=head2 BUGS

Please send bug reports to the author

=head2 AUTHOR

Eric Deutsch <edeutsch@systemsbiology.org>

=head2 SEE ALSO

SBEAMS::Connection

=cut

