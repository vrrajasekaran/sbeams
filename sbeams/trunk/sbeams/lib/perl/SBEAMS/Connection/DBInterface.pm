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
use vars qw(@ERRORS $dbh $sth $q);
use CGI::Carp qw(fatalsToBrowser croak);
use DBI;


#use lib "/net/db/src/CPAN/Data-ShowTable-3.3a";
#use Data::ShowTableEWD;
use Data::ShowTable;

use SBEAMS::Connection::DBConnector;
use SBEAMS::Connection::Tables;
use SBEAMS::Connection::TableInfo;

$q       = new CGI;


###############################################################################
# Global variables
###############################################################################
$dbh = SBEAMS::Connection::DBConnector::getDBHandle();


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


    my $altered_sql_query = $sql_query;
    $altered_sql_query =~ s/'/"/g;
    my $log_query = qq!
        INSERT INTO $TB_SQL_COMMAND_LOG
               (created_by_id,result,sql_command)
        VALUES ($current_contact_id,'$result','$altered_sql_query')
    !;

    my $sth = $dbh->prepare("$log_query") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;
    $sth->finish;


    return ($result,$returned_PK,@ERRORS);
}


###############################################################################
# SelectOneColumn
#
# Given a SQL statement which returns exactly one column, return an array
# containing the results of that query.
###############################################################################
sub selectOneColumn {
    my $self = shift || croak("parameter self not passed");
    my $sql_query = shift || croak("parameter sql_query not passed");

    my @columns;

    my $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (my @row = $sth->fetchrow_array) {
        push(@columns,$row[0]);
    }

    $sth->finish;

    return @columns;

}


###############################################################################
# selectSeveralColumns
#
# Given a SQL statement which returns one or more columns, return an array
# of references to arrays of the results of each row of that query.
###############################################################################
sub selectSeveralColumns {
    my $self = shift || croak("parameter self not passed");
    my $sql_query = shift || croak("parameter sql_query not passed");

    my @rows;

    #### FIX ME replace with $dbh->selectall_arrayref ?????
    my $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (my @row = $sth->fetchrow_array) {
        push(@rows,\@row);
    }

    $sth->finish;

    return @rows;

}


###############################################################################
# selectHashArray
#
# Given a SQL statement which returns one or more columns, return an array
# of references to hashes of the results of each row of that query.
###############################################################################
sub selectHashArray {
    my $self = shift || croak("parameter self not passed");
    my $sql_query = shift || croak("parameter sql_query not passed");

    my @rows;

    my $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (my $columns = $sth->fetchrow_hashref) {
        push(@rows,$columns);
    }

    $sth->finish;

    return @rows;

}


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
###############################################################################
sub insert_update_row {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;

  #### Decode the argument list
  my $table_name = $args{'table_name'} || die "ERROR: table_name not passed";
  my $rowdata_ref = $args{'rowdata_ref'} || die "ERROR: rowdata_ref not passed";
  my $database_name = $args{'database_name'} || "";
  my $return_PK = $args{'return_PK'} || 0;
  my $verbose = $args{'verbose'} || 0;
  my $testonly = $args{'testonly'} || 0;
  my $insert = $args{'insert'} || 0;
  my $update = $args{'update'} || 0;
  my $PK = $args{'PK'} || "";
  my $PK_value = $args{'PK_value'} || "";


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


  #### Loops over each passed rowdata element, building the query
  while ( ($key,$value) = each %{$rowdata_ref} ) {

    #### If $value is a reference, assume it's a reference to a hash and
    #### extract the {value} key value.  This is because of Xerces.
    $value = $value->{value} if (ref($value));

    print "	$key = $value\n" if ($verbose > 0);

    #### Add the key as the column name
    $column_list .= "$key,";

    #### Enquote and add the value as the column value
    $value =~ s/'/''/g;
    $value_list .= "'$value',";

    #### Put the data in key = value format, too, for UPDATE
    $columnvalue_list .= "$key = '$value',";

  }


  unless ($column_list) {
    print "ERROR: insert_row(): column_list is empty!\n";
    return;
  }


  #### Chop off the final commas
  chop $column_list;
  chop $value_list;
  chop $columnvalue_list;


  #### Build the SQL statement
  my $sql;
  if ($update) {
    $sql = "UPDATE $database_name$table_name SET $columnvalue_list WHERE $PK = '$PK_value'";
  } else {
    $sql = "INSERT INTO $database_name$table_name ( $column_list ) VALUES ( $value_list )";
  }
  print "$sql\n" if ($verbose > 0);


  #### Return if just testing
  return "1" if ($testonly);


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
    my $sql_query = shift || croak("parameter sql_query not passed");

#    my $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
#    my $rv  = $sth->execute or croak $dbh->errstr;

    my $rows = $dbh->do("$sql_query") or croak $dbh->errstr;

    return 0;

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
# fetchNextRow called by ShowHTMLTable
###############################################################################
sub fetchNextRow {
    my $flag = shift @_;
    if ($flag) {return $sth->execute;}  # do a "rewind"
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


###############################################################################
# processTableDisplayControls
#
# Displays and processes a set of crude table display controls
###############################################################################
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
    $full_where_clause =~ s/"/'/g;
    $full_orderby_clause =~ s/"/'/g;

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

1;

__END__
###############################################################################
###############################################################################
###############################################################################

=head1 NAME

SBEAMS::Connection::DBControl - Perl extension for providing common database methods

=head1 SYNOPSIS

  Used as part of this system

    use SBEAMS::Connection;
    $adb = new SBEAMS::Connection;

    $dbh = $adb->getDBHandle();   

    This needs to change!

=head1 DESCRIPTION

    This module is inherited by the SBEAMS::Connection module, 
    although it can be used on its own. Its main function
    is to provide a single set of database methods to be used 
    by all programs included in this application.

=head1 METHODS

=item B<applySqlChange()>

=head1 AUTHOR

Eric Deutsch <edeutsch@systemsbiology.org>

=head1 SEE ALSO

perl(1).

=cut
