package SBEAMS::Connection::DBInterface;

###############################################################################
# Program     : SBEAMS::Connection::DBInterface
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This is part of the SBEAMS::Connection module which handles
#               general communication with the database.
#
# SBEAMS is Copyright (C) 2000-2005 Institute for Systems Biology
# This program is governed by the terms of the GNU General Public License (GPL)
# version 2 as published by the Free Software Foundation.  It is provided
# WITHOUT ANY WARRANTY.  See the full description of GPL terms in the
# LICENSE file distributed with this software.
#
###############################################################################


use strict;
use vars qw(@ERRORS $dbh $sth $q $resultset_ref $rs_params_ref
            $SORT_COLUMN $SORT_TYPE $timing_info
           );
use CGI::Carp qw(fatalsToBrowser croak);
use DBI;
use File::Basename;
use POSIX;
use Data::Dumper;
use URI::Escape;
use Storable;
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval );

use GD::Graph::bars;
use GD::Graph::xypoints;



#use Data::ShowTableTest;
use Data::ShowTable;

use SBEAMS::Connection::Authenticator qw( $q );
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::DBConnector;
use SBEAMS::Connection::Tables;
use SBEAMS::Connection::DataTable;
use SBEAMS::Connection::Log;
use SBEAMS::Connection::TableInfo;
use SBEAMS::Connection::Utilities;

my $log = SBEAMS::Connection::Log->new();

use constant DATA_READER => 40;
use constant DATA_WRITER => 30;


###############################################################################
# Global variables
###############################################################################


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
# This is kind of an old and krusty method that really needs updating.
# It has fallen in disprepair and doesn't follow the rest of the conventions
# that have evolved.  Nonetheless, it sort of works, so leave it for now.
# It is really only used by ManageTable
#
# All INSERT, UPDATE, DELETE SQL commands initiated by the user should be
# delivered here first so that all permission checking and logging of the
# commands takes place.
###############################################################################
sub applySqlChange {
    my $self = shift || croak("parameter self not passed");
    my %args = @_;
    my $SUB_NAME = "applySqlChange";

    my $sql_query = $args{'SQL_statement'}
      || die("ERROR: $SUB_NAME: Parameter SQL_statement not passed");
    my $current_contact_id = $args{'current_contact_id'}
       || die("ERROR: $SUB_NAME: Parameter current_contact_id not passed");
    my $table_name = $args{'table_name'}
      || die("ERROR: $SUB_NAME: Parameter table_name not passed");
    my $record_identifier = $args{'record_identifier'}
       || die("ERROR: $SUB_NAME: Parameter record_identifier not passed");
    my $PK_COLUMN_NAME = $args{'PK_column_name'} || '';
    my $parent_project_id = $args{'parent_project_id'} || '';

    #### Define variables to hold the final results
    my $result = "CODE ERROR";
    my $returned_PK;
    @ERRORS = ();

    #### Get the names of all the privilege levels
    my %level_names = $self->selectTwoColumnHash(
      "SELECT privilege_id,name FROM $TB_PRIVILEGE WHERE record_status!='D'"
    );

    # Got annoyed by non-informative errors.  get_best_permission() gives a 
    # permission of 9999 if the privilege can't be found.  This is a temporary
    # patch for that
    $level_names{9999} ||= 'NONE';


    #### Privilege that the work_group has over a table_group
    my $table_group_privilege_id;

    #### Privilege that the user has within a work_group
    my $user_work_group_privilege_id;

    #### Privilege that the user has given himself in the user_context
    my $user_context_privilege_id;

    #### Privilege that the user has for the relevant project
    my $project_privilege_id = '';


    #### Translate the table handle to the database table name
    my ($DB_TABLE_NAME) = $self->returnTableInfo($table_name,"DB_TABLE_NAME");


    # Extract the first word, hopefully INSERT, UPDATE, or DELETE
    $sql_query =~ /\s*(\w*)/;
    my $sql_action = uc($1);
    unless ($sql_action =~ /^INSERT$|^UPDATE$|^DELETE$/) {
      die("ERROR: $SUB_NAME: Unrecognized action $sql_action");
    }


    #### Get the current work_group information
    my $current_work_group_id = $self->getCurrent_work_group_id();
    my $current_work_group_name = $self->getCurrent_work_group_name();


    #### Generate a query to check table/group/user level permissions
    my $check_privilege_query = qq~
	SELECT UC.contact_id,UC.work_group_id,TGS.table_group,
		TGS.privilege_id,UWG.privilege_id,UC.privilege_id
	  FROM $TB_TABLE_GROUP_SECURITY TGS
	  LEFT JOIN $TB_USER_CONTEXT UC
	       ON ( UC.contact_id = '$current_contact_id' )
  	  LEFT JOIN $TB_TABLE_PROPERTY TP
               ON ( TGS.table_group = TP.table_group )
	  LEFT JOIN $TB_USER_WORK_GROUP UWG
	       ON ( TGS.work_group_id = UWG.work_group_id )
	 WHERE TGS.work_group_id='$current_work_group_id'
	   AND TP.table_name = '$table_name'
	   AND UWG.contact_id = '$current_contact_id'
	   AND TGS.record_status != 'D'
	   AND UC.record_status != 'D'
	   AND UWG.record_status != 'D'
    ~;

    #### Execute the query and gather the results
    my @rows = $self->selectSeveralColumns($check_privilege_query);
    my $n_rows = scalar(@rows);
    #push(@ERRORS, "<PRE>$check_privilege_query\n\n</PRE>");
    #push(@ERRORS, "Returned Permissions:");

    #### Loop over the returned rows, extracting results, possibly debugging
    for (my $row=0; $row<$n_rows; $row++) {
      my @row = @{$rows[$row]};
      #push(@ERRORS, "---> ".join(" | ",@row));
      $table_group_privilege_id = $row[3];
      $user_work_group_privilege_id = $row[4];
      $user_context_privilege_id = $row[5];
    }

    #### If no rows came back, the table/work_group relationship is not defined
    if ($n_rows == 0) {
      push(@ERRORS, "The privilege of your current work group ".
	   "($current_work_group_name) is not defined for this table. Try ".
	   "going back and switching to a more appropriate group."
	  );
      $result = "DENIED";
    }


    #### Don't know how to handle multiple rows yet
    if ($n_rows > 1) {
      push(@ERRORS, "Multiple permissions were found, and I don't know what
        to do.  Please contact <B>edeutsch</B> about this error");
      $result = "DENIED";
    }


    #### Also get the best permission this user has for this project_id
    #### if appropriate/available for this table
    if ($parent_project_id) {
      $project_privilege_id = $self->get_best_permission(
        project_id => $parent_project_id,
      );
    }

    #### Set the privilege_id to none
    my $privilege_id=50;

    #### If there's a table_group privilege, use that
    if ($table_group_privilege_id > 0) {
      $privilege_id = $table_group_privilege_id;
    }

    #### If there's a user_work_group privilege and it's worse than the
    #### so-far determined privilege, then drop to that
    if (defined($user_work_group_privilege_id) &&
        $user_work_group_privilege_id > $privilege_id) {
      $privilege_id = $user_work_group_privilege_id;
    }

    #### If there's a user_context privilege and it's worse than the
    #### so-far determined privilege, then drop to that
    if (defined($user_context_privilege_id) &&
        $user_context_privilege_id > $privilege_id) {
      $privilege_id = $user_context_privilege_id;
    }


    my ($privilege_name) = $level_names{$privilege_id}
      || die("ERROR: $SUB_NAME: Unrecognized privilege_id '$privilege_id'");


    #### Configure a hash for action suggestions
    my %remedies = ();

    # Allow exception for rowprivate
    my $rprivate =  $self->isRowprivate( $DB_TABLE_NAME );
    if ( $rprivate ) {
      $log->info( "Allowing exception for rowprivate data" );
      $result = "SUCCESSFUL";
    }

    #### If the user only has data_reader or worse, deny them
    if ( $privilege_id >= DATA_READER && !$rprivate ) {

      push(@ERRORS, "As part of the current work group, you only have ".
       "privilege '($privilege_name)' for this ".
	     "table and are not permitted to write to it.");
      $remedies{find_another_group} = 1;
      $result = "DENIED";


    #### Otherwise if this is an INSERT, then go ahead and execute
    } elsif ($sql_action eq "INSERT") {

      #### If project privileges are relevant and the user doesn't
      #### even have data_writer privilege in the project, then DENY
      if ($project_privilege_id && $project_privilege_id > 30) {
	push(@ERRORS, "This record belongs to a project that you ".
	     "only have a privilege level '".
	     $level_names{$project_privilege_id}."' under.  See below."
	    );
	$remedies{talk_to_project_admin} = $parent_project_id;
        $result = "DENIED";

      #### Else permission okay, so go ahead and execute
      } else {
#	$self->executeSQL($sql_query);
	$result = "SUCCESSFUL";

	#### Determine what the last inserted autogen key was
	$returned_PK = $self->getLastInsertedPK(
          table_name=>$table_name,
          PK_column_name=>$PK_COLUMN_NAME
        );
      }


    #### Otherwise if this an UPDATE or DELETE
    } elsif ($sql_action =~ /^UPDATE$|^DELETE$/) {

      #### Get modified_by, group_owner, status of record to be affected
      my $check_permission_query = qq~
        SELECT created_by_id,modified_by_id,owner_group_id,record_status
          FROM $DB_TABLE_NAME
         WHERE $record_identifier
      ~;
      my @rows = $self->selectSeveralColumns($check_permission_query);
      my ($created_by_id,$modified_by_id,$owner_group_id,$record_status) =
	@{$rows[0]};


      #### Start with the assumption of DENIED
      my $permission="DENIED";


      #### If the user is an owner (original or latest) of a record
      if ( $modified_by_id == $current_contact_id
	   || $created_by_id == $current_contact_id ) {

	#### If project permissions are relevant
        if ($project_privilege_id) {

	  #### If the user has at least data_writer in the project, then okay
	  if ($project_privilege_id <= 30) {
	    $permission = "ALLOWED";

	  #### Else deny them.  Presumably they once had privilege but now
	  #### have lost it, so even though they own the records, the project
	  #### administrators have seen fit to disallow them access
	  } else {
	    push(@ERRORS,"You do not have write privilege under this ".
		 "project.  See below.");
	    $remedies{talk_to_project_admin} = $parent_project_id;
	    $permission = "DENIED";
	  }

	#### Else if project permissions not relevant, then ALLOW pending
	#### some obscure checks for Locking
	} else {

	  #### Check if Locked
	  if ($record_status eq "L") {

	    #### If we're the last modifier, okay
	    if ($modified_by_id == $current_contact_id) {
	      $permission="ALLOWED";

	    #### Else, even if we created it, we've been Locked out
	    } else {
	      push(@ERRORS,"This record is Locked by ".
		   $self->getUsername($modified_by_id).".  Please see ".
		   "him or her to allow you access or alter it.");
	      $permission="DENIED";
	    }

	  #### Else if not Locked, then ALLOW
	  } else {
	    $permission="ALLOWED";
	  }

	}


      #### Else if the record is Locked, then DENY
      } elsif ($record_status eq 'L') {
	push(@ERRORS,"This record is Locked by ".
	     $self->getUsername($modified_by_id).".  Please see ".
	     "him or her to allow you access or alter it.");
	$permission="DENIED";


      #### Else if the record is Modifiable, then ALLOW to any data_writer
      } elsif ($record_status eq 'M') {
	$permission="ALLOWED";


      #### Else if not the owner and has Normal record_status, then more logic
      } else {

	#### If project permissions are relevant
        if ($project_privilege_id) {

	  #### If the user has at least data_modifier in the project, then okay
	  if ($project_privilege_id <= 20) {
	    $permission = "ALLOWED";

	  } elsif ($project_privilege_id <= 25
		   && ($owner_group_id == $current_work_group_id)) {
	    $permission = "ALLOWED";

	  } else {
	    push(@ERRORS,"You do not have sufficient privilege to modify ".
		 "this record.  See the project owner/admin to fix.");
	    $permission = "DENIED";

	  }

	#### Else project permissions are no relevant, so just use regular
	} else {

	  #### If the user has at least modifier in the project, then okay
	  if ($privilege_id <= 20) {
	    $permission = "ALLOWED";

	  #### Else if group_modifier and the current and record group match
	  } elsif ($project_privilege_id <= 25
		   && ($owner_group_id == $current_work_group_id)) {
	    $permission = "ALLOWED";

	  #### Otherwise the user is out of luck
	  } else {
	    push(@ERRORS,"You do not have sufficient under this ".
		 "project.  See below.");
	    $remedies{talk_to_project_admin} = $parent_project_id;
	    $permission = "DENIED";

	  }

	}

      }


      #### If after all this, we've ALLOWED the change, do it
      if ($permission eq "ALLOWED") {
#$self->executeSQL($sql_query);
        $result = "SUCCESSFUL";

      #### Else if it's not allowed, try to determine why not
      } else {
        unshift(@ERRORS,"You do not have sufficient privilege to ".
		"$sql_action this record.");

	unshift(@ERRORS,"PLEASE NOTE that SBEAMS has recently suffered an ".
		"update to its security model.  If you encounter this ".
		"message in error, please send a polite message to ".
		"edeutsch and he will try to get it fixed.");

        push(@ERRORS,"Your table-level privilege is $privilege_name.");

        push(@ERRORS,"Your project-level privilege is ".
	     $level_names{$project_privilege_id})
	  if ($parent_project_id);

	unless ( $modified_by_id == $current_contact_id
		 || $created_by_id == $current_contact_id ) {
	  push(@ERRORS,"You are not an owner of this record.");
	}

        push(@ERRORS, "The group owner of this record ($owner_group_id) ".
	     "is not the same as your current working group ".
	     "($current_work_group_id = [$current_work_group_name]).")
          if ($owner_group_id != $current_work_group_id);

        push(@ERRORS, "This record is Locked.") if ($record_status eq 'L');

	if ($remedies{find_another_group}) {
          push(@ERRORS,"Perhaps you should be ${sql_action}ing this record ".
	       "under a different group.  To do so, click [BACK] and then ".
	       "select a different group using the pull-down menu at the ".
	       "top of the screen."
	      );
	}

	if ($remedies{talk_to_project_admin}) {
	  my $sql = qq~
	    SELECT project_tag,P.name,username,first_name,last_name
	      FROM $TB_PROJECT P
	     INNER JOIN $TB_CONTACT C ON ( P.PI_contact_id = C.contact_id )
	     INNER JOIN $TB_USER_LOGIN UL
	           ON ( P.PI_contact_id = UL.contact_id )
	     WHERE P.project_id = '$parent_project_id'
	  ~;
	  my @rows = $self->selectSeveralColumns($sql);
	  my ($project_tag,$project_name,$username,$first_name,$last_name) =
	    @{$rows[0]};

	  $sql = qq~
	    SELECT username,first_name,last_name
	      FROM $TB_USER_PROJECT_PERMISSION GPP
	     INNER JOIN $TB_CONTACT C ON ( GPP.contact_id = C.contact_id )
	     INNER JOIN $TB_USER_LOGIN UL ON ( GPP.contact_id = UL.contact_id )
	     WHERE GPP.privilege_id = 10
	       AND GPP.project_id = '$parent_project_id'
	       AND GPP.record_status != 'D'
	  ~;
	  @rows = $self->selectSeveralColumns($sql);

	  my $project_admins = '';
	  if (@rows) {
	    $project_admins = "You may also get access from one of those ".
	      "with administrator privilege for this project: ";
	    foreach my $row (@rows) {
	      $project_admins .= "$row->[0] ($row->[1] $row->[2]),";
	    }
	    chop($project_admins);
	  }

          push(@ERRORS,"The record you are trying To ${sql_action} ".
	       "belongs to the $project_tag ($project_name) project, which ".
	       "is owned by $username ($first_name $last_name).  Please ".
	       "contact him or her and request that you be granted access ".
	       "to this project with greater privilege. $project_admins"
	      );
	}

        $result = "DENIED";
      }

    }

    # Still in testing mode, don't want to execute/log these twice...
    return( result => $result, tPriv => $privilege_id, pPriv => $project_privilege_id );

}

#+
# Checks through all registered rowprivate tables, returns 1 if 
# any of them match passed table, else returns 0.
#-
sub isRowprivate {
    my $self = shift || croak("parameter self not passed");
    my $table = shift;
    return 0 unless $table;
    my ( $base ) =  $table =~ /\.([a-zA-Z_]+)$/;
    my @rows = $self->selectOneColumn( <<"    END" );
    SELECT table_name FROM $TB_TABLE_PROPERTY 
    WHERE table_group = 'rowprivate'
    END
    for ( @rows ) {
      return 1 if $_ =~ /$base/i;
    }
    return 0;
}

#+
#
#-
sub applySQLChange {
    my $self = shift || croak("parameter self not passed");
    my %args = @_;

    my $subname = 'applySQLChange';

    # FIXME temporarily running both old and new versions of applySqlChange to
    # ensure a smooth transition.  New version is definitive as of 01-25-2005.
    my %asc_old = $self->applySqlChange ( %args );


    # Check for required parameters.
    for(qw( SQL_statement current_contact_id table_name record_identifier )){
      die( "Error: $subname: Parameter $_ not passed" ) unless $args{$_};
    }

    # Get the names of all the privilege levels
    my %level_names = $self->selectTwoColumnHash(
      "SELECT privilege_id,name FROM $TB_PRIVILEGE WHERE record_status!='D'"
    );
    # get_best_permission() gives default permission of 9999.  Can't
    # put this in $TB_PRIV 'cause it would show up in select lists.  Doh!
    $level_names{9999} ||= 'NONE';


    # Make necessary argument calculations/transforms

    # Grep 'action' from SQL query - Ugh!  Ugh!  Ugh!
    ( $args{action} ) = $args{SQL_statement} =~ /\s*(\w*)/;
    unless ($args{action} =~ /^INSERT$|^UPDATE$|^DELETE$|^SELECT$/i) {
      die("ERROR: $subname: Unrecognized action $args{action}");
    }
    $args{dbtable} = $self->returnTableInfo($args{table_name},"DB_TABLE_NAME");
    $args{contact_id} = $args{current_contact_id} || $self->getCurrent_contact_id();
    $args{pk_column_name} = $args{PK_column_name};
    ( $args{pk_value} = $args{record_identifier} ) =~ s/.*=//;
    $args{project_id} = $self->getCurrent_project_id();
    $args{work_group_id} = $self->getCurrent_work_group_id();

    # Defaults to restrictive permissions
    my $pPriv = '';
    my $tPriv = 50;
    my $status = 'DENIED';

    # Assumes (as does original) that this has already been determined and cached.
    if ( $args{parent_project_id} && $args{action} !~ /^INSERT?/i ) {
      $pPriv = $self->calculateProjectPermission( %args );
    }
    $tPriv = $self->calculateTablePermission( %args );

    # A better privilege may be legitimately afforded via membership in a group
    # other than the current one.  Check on this.
    my $work_groups_ref = $self->getTableGroups( %args, privilege => 10000 );
    my $bestpriv = $self->getBestGroupPermission( $work_groups_ref );
    $tPriv = ( $bestpriv < $tPriv ) ? $bestpriv : $tPriv;

    
    # At this point, INSERT depends solely on table permission
    if ( $args{action} =~ /^INSERT$/i && $tPriv <= DATA_READER ) {
      $status = 'SUCCESSFUL';
    # Update/Delete use project permission if possible, else use table
    } elsif ( $args{action} =~ /^UPDATE$|^DELETE$/i ) {
      if ( $pPriv ) {
        $status = 'SUCCESSFUL' if $pPriv <= DATA_WRITER;
      } else {
        $status = 'SUCCESSFUL' if $tPriv <= DATA_WRITER;
      }
    }

    # DEBUG testing block
    if ( %asc_old ) {
      if ( $asc_old{result} ne $status ||
        $pPriv != $asc_old{pPriv} ||
        $tPriv != $asc_old{tPriv} ) {
        $log->error( <<"        END" );
        
        NEW: result => $status\tpPriv => $pPriv\t tPriv=>$tPriv
        OLD: result => $asc_old{result}\tpPriv => $asc_old{pPriv}\ttPriv=>$asc_old{tPriv}

        END
      }
    }
    
    # Go ahead and execute the query if it passed muster.
    my $pk = '';
    if ( $status eq 'SUCCESSFUL' ) {
    	$self->executeSQL($args{SQL_statement});
      $pk = $self->getLastInsertedPK( table_name=>$args{db_table},
                                      PK_column_name=>$args{PK_column_name} ) if $args{action} =~ /^INSERT$/i;
    }

    # Log the result and the query itself 
    my $escQuery = $self->convertSingletoTwoQuotes($args{SQL_statement});
    my $logSQL =<<"    END";
    INSERT INTO $TB_SQL_COMMAND_LOG (created_by_id,result,sql_command)
    VALUES ($args{contact_id},'$status','$escQuery')
    END
    $self->executeSQL($logSQL);

    my @errors;
    if ( $status ne 'SUCCESSFUL' ) {
      @errors = ( "$args{action} into $args{dbtable} failed.", 
                  "Your table permission on this table is $tPriv"
               );
      push @errors, "Your project permission on this record is $pPriv" if $pPriv;
    }

    #### Return the results
    return ($status,$pk, @errors);
} # End applySQLChange


sub getDbTableName {
  my $self = shift;
  my $name = shift;

  $dbh = $self->getDBHandle();

  my $dbname = $dbh->selectrow_array( <<"  END" );
  SELECT db_table_name
  FROM $TB_TABLE_PROPERTY
  WHERE table_name = '$name'
  END

  my $sql =<<"  END";
  SELECT db_table_name
  FROM $TB_TABLE_PROPERTY
  WHERE table_name = '$name'
  END

  return eval "\"$dbname\"";
} # End getDbTableName


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

    #### Convert the SQL dialect if necessary
    $sql = $self->translateSQL(sql=>$sql);

    my $sth = $dbh->prepare($sql) or croak $dbh->errstr;

    my $rv  = $sth->execute; # or croak $dbh->errstr;
    unless( $rv ) {
      $log->error( "Error executing SQL:\n $sql" );
      $log->printStack( 'error' );
      croak $dbh->errstr;
    }

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

	
    #### Convert the SQL dialect if necessary
    $sql = $self->translateSQL(sql=>$sql);

    #### FIX ME replace with $dbh->selectall_arrayref ?????
    my $sth = $dbh->prepare($sql) or confess($dbh->errstr);
    my $rv  = $sth->execute or confess($dbh->errstr);

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

    #### Convert the SQL dialect if necessary
    $sql = $self->translateSQL(sql=>$sql);

    my ($sth, $rv);
    eval {
      $sth = $dbh->prepare($sql) or croak $dbh->errstr;
      $rv  = $sth->execute or croak $dbh->errstr;
    };
    if ( $@ ) {
      $log->error( "Error running SQL: $sql\n $@" );
      croak( $@ );
    }

    while (my $columns = $sth->fetchrow_hashref) {
        push(@rows,$columns);
    }

    $sth->finish;

    return @rows;

} # end selectHashArray

###############################################################################
# selectTwoColumnHashref
#
# Given a SQL statement which returns exactly two columns, return reference to
# a hash where key is column 0 and value is column 1.
# 
###############################################################################
sub selectTwoColumnHashref {
    my $self = shift || croak("parameter self not passed");
    my $sql = shift || croak("parameter sql not passed");

    my %hash;

    #### Get the database handle
    $dbh = $self->getDBHandle();

    #### Convert the SQL dialect if necessary
    $sql = $self->translateSQL(sql=>$sql);

    my ($sth, $rv);
    eval {
      $sth = $dbh->prepare($sql) or croak $dbh->errstr;
      $rv  = $sth->execute or croak $dbh->errstr;
    };
    if ( $@ ) {
      $log->error( "Error running SQL: $sql\n $@" );
      croak( $@ );
    }

    while (my @row = $sth->fetchrow_array()) {
        $hash{$row[0]} = $row[1];
    }

    $sth->finish;

    return \%hash;
}

###############################################################################
# selectTwoColumnHash
#
# Given a SQL statement which returns exactly two columns, return a hash
# containing the results of that query.
###############################################################################
sub selectTwoColumnHash {
    my $self = shift || croak("parameter self not passed");
    my $sql = shift || croak("parameter sql not passed");

    my %hash;

    #### Get the database handle
    $dbh = $self->getDBHandle();

    #### Convert the SQL dialect if necessary
    $sql = $self->translateSQL(sql=>$sql);

    my $sth = $dbh->prepare("$sql") or croak $dbh->errstr;
    my $rv  = $sth->execute or croak $dbh->errstr;

    while (my @row = $sth->fetchrow_array) {
        $hash{$row[0]} = $row[1];
    }

    $sth->finish;

    return %hash;

}


###############################################################################
# translateSQL
#
# Given an SQL statement in one dialect of SQL, translate to the current
# dialect of SQL
###############################################################################
use Regexp::Common qw /delimited balanced/; # needed by translateSQL for mysql
use re 'eval'; # needed by Regexp::Common::balanced
sub translateSQL{
  my $self = shift || croak("parameter self not passed");
  my %args = @_;

  #### Process the arguments list
  my $sql = $args{'sql'} || croak "parameter sql missing";

  my $DBType = $self->getDBType() || "";
  return $sql if ($DBType =~ /MS SQL Server/i);

  my $new_statement = $sql;

  #### Conversion syntax from MS SQL Server to PostgreSQL
  if ($DBType =~ /PostgreSQL/i) {

    #### Real naive and stupid so far...
    #print "Content-type: text/html\n\nLooking at $sql<BR><BR>\n";
    if ($new_statement =~ /\+/) {
      $new_statement =~ s/\+/||/g;
    }


  #### Conversion syntax from MS SQL Server to MySQL
  } elsif ($DBType =~ /mysql/i) {

    #### Loop through each of the SELECT statements in the SQL
    while( $new_statement =~ /(SELECT)+\s+(.+?)\s+(FROM|INTO)+/ig ){

      #### Extract the column list
      my $list = $2;
      next if $list eq '*';

      #### Get the start and end of the column list
      my ($start,$end) = ($-[2],$+[2]);

      #### Perform the necessary conversion for various functions
      $list = convert_functions($list);
      #### Perform the necessary conversion for string concatentation syntax
      $list = convert_concatenation($list);

      #### Update the statement with the new syntax and
      #### since we are modifying $new_statement in place then we need
      #### to update its 'pos' for the pattern match to work under /g
      substr($new_statement,$start,$end-$start) = $list;
      pos($new_statement) = $start + length $list;

    }

  }
	
  return $new_statement;

} # endtranslateSQL



###############################################################################
# convert_concatenation
#
# Convert any SQL catenation operators into the MySQL CONCAT() function syntax
###############################################################################
sub convert_concatenation {
  my $select_list = shift;

  #### Separate out functions and quoted text segments
  my @words = split( /(\w+\s*$RE{balanced}{-parens=>'()'}|$RE{delimited}{-delim=>"'"}|RE{delimited}{-delim=>'"'})/, $select_list);
#  print "0-->", @words;

  my @new;
  for (@words){
    # split on ',' to get the columns (where not quoted or part of a function)
    if ( /^[\"\']/ || /^\w+\s?\(/ ){
      push @new, $_;
    } else {
      s/^\s?,//;
      s/,\s?$//;
      push @new, split(/,/,$_);
    }
  }
  #print "1-->",join(';',@new);

  #### Join fragments that are a part of a concatenation or aliases
  for (my $i = 0; $i < @new; $i++){

    if( $new[$i] =~ /^\s?\+/ ){
      $new[$i-1] .= $new[$i];
      splice @new, $i, 1;
      $i -= 2;
      next;
    }

    if( $new[$i] =~ /\+\s?$/ ){
      $new[$i] .= $new[$i+1];
      splice @new, $i+1, 1;
      $i--;
      next;
    }

    if( $new[$i] =~ /^\s?AS\s+$/i ){
      $new[$i] .= $new[$i+1];
      splice @new, $i+1,1;
      $i--;
      next;
    }

    if( $new[$i] =~ /\s+AS\s?$/i ){
      $new[$i] .= $new[$i+1];
      splice @new, $i+1, 1;
      $i--;
      next;

    }

  }
  #print "2-->",join(';',@new);


  #### Convert concatenation operator to concat function
  for (@new){
    if ( /\+/ ) {
      my @items = split(/\+/,$_);
      $_ = "CONCAT(" . join(",",@items) . ")";
    }	
  }
  #print "3-->",join(';',@new);


  #### Assemble final SQL
  my $retval;
  for (my $i = 0; $i < @new; $i++){
    $retval .= $new[$i];
    if ( $i < $#new &&  $new[$i+1] !~ /^\s?AS\s+/ ) {
      $retval .= ",";
    }
  }

  return $retval;

} # end convert_concatenation



###############################################################################
# convert_functions
#
# Convert SQL Server functions to MySQL functions
###############################################################################
sub convert_functions {
  my $select_list = shift;
  my @ops;

  #### At the moment only convert the STR function (its the only one used).
  while ( $select_list =~ /(\W)?STR\(([\w\.]+),(\d+),(\d+)\)/ig ){
    my %opt;
    $opt{start} = $-[0];
    $opt{end} = $+[0];
    $opt{replace} =  "$1FORMAT($2,$4)";
    push @ops, \%opt;
  }

  for my $opt (@ops){
    substr($select_list,$opt->{start},$opt->{end} - $opt->{start}) =
      $opt->{replace};
  }

  return $select_list;	

} # end convert_functions



###############################################################################
# buildLimitClause
#
# Build a LIMIT clause for a SELECT query so that only N number of rows
# are returned.  The syntax varies wildly between database engines
###############################################################################
sub buildLimitClause {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;
  my $SUB_NAME = 'buildLimitClause';

  #### Process the arguments list
  my $row_limit = $args{'row_limit'};


  #### Define a hash to return
  my $return_hash;
  $return_hash->{top_clause} = '';
  $return_hash->{trailing_limit_clause} = '';


  #### If no row_limit was provided, just return empty strings in the hash
  return $return_hash unless (defined($row_limit) && $row_limit gt '');


  #### Get the type of database we have
  my $DBType = $self->getDBType() || "";


  #### Populate the hash with whatever is appropriate for this type of engine
  if ($DBType =~ /MS SQL Server/i) {
    $return_hash->{top_clause} = "TOP $row_limit";

  } elsif ($DBType =~ /MySQL/i) {
    $return_hash->{trailing_limit_clause} = "LIMIT $row_limit";

  } elsif ($DBType =~ /PostgreSQL/i) {
    $return_hash->{trailing_limit_clause} = "LIMIT $row_limit";

  } elsif ($DBType =~ /DB2/i) {
    $return_hash->{trailing_limit_clause} = "FETCH FIRST $row_limit ROWS ONLY";

  } else {
    die("ERROR[$SUB_NAME]: Unrecognized database type");
  }


  return $return_hash;

} # end buildLimitClause


###############################################################################
# insert_update_row: deprecated in favor of updateOrInsertRow
###############################################################################
sub insert_update_row {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;

  $self->updateOrInsertRow(@_);

}


###############################################################################
# updateOrInsertRow
#
# This method builds either an INSERT or UPDATE SQL statement based on the
# supplied parameters and executes the statement.
###############################################################################
sub updateOrInsertRow {
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
  my $return_error = $args{'return_error'} || '';
  my $add_audit_parameters = $args{'add_audit_parameters'} || 0;


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


  #### If add_audit_parameters is enabled, add those columns 
  if ($add_audit_parameters) {
    if ($insert) {
      $rowdata_ref->{date_created}='CURRENT_TIMESTAMP';
      $rowdata_ref->{created_by_id}=$self->getCurrent_contact_id();
      $rowdata_ref->{owner_group_id}=$self->getCurrent_work_group_id();
      $rowdata_ref->{record_status}='N';
    }

    $rowdata_ref->{date_modified}='CURRENT_TIMESTAMP';
    $rowdata_ref->{modified_by_id}=$self->getCurrent_contact_id();
  }


  #### Loops over each passed rowdata element, building the query
  while ( ($key,$value) = each %{$rowdata_ref} ) {

    #### If quoted identifiers is set, then quote the key
    $key = '"'.$key.'"' if ($quoted_identifiers);

    #### If $value is a reference, assume it's a reference to a hash and
    #### extract the {value} key value.  This is because of Xerces.
    $value = $value->{value} if (ref($value));


    #### If the value is undef, then change it to NULL
    $value = 'NULL' unless (defined($value));

    print "KEY VAL	$key = $value\n" if ($verbose > 0);

    #### Add the key as the column name
    $column_list .= "$key,";

    #### Enquote and add the value as the column value
    $value = $self->convertSingletoTwoQuotes($value);
    if (uc($value) eq "CURRENT_TIMESTAMP" || uc($value) eq "NULL") {
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
  #### Could also imagine allowing parameter binding as an option
  #### for database engines that support it instead of sending
  #### the full text SQL statement.  This should then support
  #### cached statement handles for multiple bindings per prepare.
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
    #print "Not actually executing SQL...\n";

    #### If the user asked for the PK to be returned, make a random one up
    if ($return_PK) {
      return int(rand()*10000);

    #### Otherwise, just return a 1
    } else {
      return 1;
    }
  }


  #### Execute the SQL
  my $result = $self->executeSQL(sql=>$sql,return_error=>$return_error);


  #### If executeSQL() did not report success, return
  return $result unless ($result);


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
    my $SUB_NAME = "executeSQL";


    #### Allow old-style single argument
    my $n_params = scalar @_;
    my %args;
    die("parameter sql not passed") unless ($n_params >= 1);
    #### If the old-style single argument exists, create args hash with it
    if ($n_params == 1) {
      $args{sql} = shift;
    } else {
      %args = @_;
    }


    #### Decode the argument list
    my $sql = $args{'sql'} || die("parameter sql not passed");
    my $return_error = $args{'return_error'} || '';

    #print "Content-type: text/html\n\n$sql\n\n";
    #### Get the database handle
    $dbh = $self->getDBHandle();

    #### Prepare the query
    my $sth = $dbh->prepare($sql);
    my $rows;

    #### If the prepare() succeeds, execute
    if ($sth) {

      my $rows = '';
      eval {
           $rows  = $sth->execute();
           };
      if ( $@ ) {
        $log->error( "Caught error: $@" );
        $log->error( "DBI errorstring is $DBI::errstr" );
      }

      if ($rows) {
        if (ref($return_error)) {
          $$return_error = '';
        }
        return $rows;
      } elsif ($return_error) {
        if (ref($return_error)) {
          $$return_error = $dbh->errstr;
        }
        return 0;
      } else {
        $log->error( "Error on execute DBI errorstring is $DBI::errstr" );
        die("ERROR on SQL execute():\n$sql\n\n".$dbh->errstr);
      }

    #### If the prepare() fails
    } elsif ($return_error) {
      if (ref($return_error)) {
        $$return_error = $dbh->errstr;
      }
      return 0;
    } else {
      die("ERROR on SQL prepare(): ".$dbh->errstr);
    }


    #### Return the number of rows affected, or some other non-0 result
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
      #### 13 characters to form the automatic SEQUENCE.  Might be fixed later?
      my $sequence_name;
      if (0) {
        my $table_name_tmp = substr($table_name,0,13);
        my $PK_column_name_tmp = substr($PK_column_name,0,13);
        $sequence_name = "${table_name_tmp}_${PK_column_name_tmp}_seq";

      #### To avoid possible complications with this, SBEAMS now just creates
      #### SEQUENCEs explicitly and simply truncates them at the PostgreSQL
      #### 7.1 limit of 31 characters.  I hope this will be lifted sometime
      } else {
        $sequence_name = "seq_${table_name}_${PK_column_name}";
        $sequence_name = substr($sequence_name,0,31);
      }

      $sql = "SELECT currval('$sequence_name')"

    #### Complain bitterly if we don't recognize the RDBMS type
    } else {
      croak "ERROR[$subName]: Unable to determine DBType\n\n";
    }


    #### Get value and return it
    my ($returned_PK) = $self->selectOneColumn($sql);
    return $returned_PK;

}



###############################################################################
# deleteRecordsAndChildren
###############################################################################
sub deleteRecordsAndChildren {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;

  my $table_name = $args{'table_name'} || die("table_name not passed");
  my $table_child_relationship = $args{'table_child_relationship'}
    || die("table_child_relationship not passed");
  my $table_PK_column_names = $args{'table_PK_column_names'};
  my $delete_PKs = $args{'delete_PKs'} || die("delete_PKs not passed");
  my $delete_batch = $args{'delete_batch'} || 0;
  my $VERBOSE = $args{'verbose'} || 0;
  my $DATABASE = $args{'database'} || '';
  my $QUIET = $args{'quiet'} || 0;
  my $TESTONLY = $args{'testonly'} || 0;
  my $keep_parent_record = $args{'keep_parent_record'} || 0;

  print "  Entering deleteRecordsAndChildren\n\n" if ($VERBOSE > 1);

  #### Define and redereference PK column names
  my %table_PK_column_names = ();
  if (defined($table_PK_column_names)) {
    %table_PK_column_names = %{$table_PK_column_names};
  }


  #### If there are child tables, process them first
  if (defined($table_child_relationship->{$table_name})) {

    my @sub_tables = split(",",$table_child_relationship->{$table_name});
    foreach my $element (@sub_tables) {
      if ($element =~ /^([\w_\-\d]+)\(([A-Z]+)\)$/) {
        my $child_table_name = $1;
	my $child_type = $2;
        print "  Processing child $child_table_name ($child_type)\n\n"
          if ($VERBOSE > 1);

        #### If it's a plain child, determine my PKs and recurse requesting
        #### all references be deleted
        if ($child_type eq 'C') {

  	  #### Get the number of records to delete and set the first and last
  	  my $n_ids = scalar(@{$delete_PKs});
  	  my $first_element = 0;
  	  my $last_element = $n_ids - 1;

  	  #### If the user requested to delete in batches, possibly
          #### reduce the last
  	  if ($delete_batch && $n_ids > $delete_batch) {
  	    $last_element = $delete_batch - 1;
  	  }

  	  #### While there are still records to delete, do it
  	  while ($first_element < $n_ids) {
  	    #### Get the records to delete in this batch
  	    my @ids = @{$delete_PKs};
  	    @ids = @ids[$first_element..$last_element];

	    my $child_PK = $table_PK_column_names{$child_table_name} ||
	      "${child_table_name}_id";
	    my $parent_PK = $table_PK_column_names{$table_name} ||
	      "${table_name}_id";

  	    my $sql = "
  	      SELECT $child_PK
  	      FROM ${DATABASE}$child_table_name
  	      WHERE $parent_PK IN (".join(",",@ids).")
  	    ";

  	    print "$sql\n\n" if ($VERBOSE > 1);
            print "SELECTING children of $table_name ".
              "(batch $first_element / $n_ids)\n"
  	      if ($VERBOSE);

  	    my @child_PKs = $self->selectOneColumn($sql);

  	    if (scalar(@child_PKs) > 0) {
  	      print "Recursing to delete $child_table_name\n\n"
                if ($VERBOSE > 1);
  	      my $result = $self->deleteRecordsAndChildren(
  		table_name => $child_table_name,
  		table_child_relationship => $table_child_relationship,
                table_PK_column_names => $table_PK_column_names,
  		delete_PKs => \@child_PKs,
  		delete_batch => $delete_batch,
  		database => $DATABASE,
  		verbose => $VERBOSE,
  		quiet => $QUIET,
  		testonly => $TESTONLY,
  	      );
            } else {
              print "  None.\n" if ($VERBOSE);
            }

  	    #### Update the first and last batch block pointers if relevant
  	    last unless ($delete_batch);
  	    $first_element += $delete_batch;
  	    $last_element += $delete_batch;
  	    $last_element = $n_ids - 1 if ($last_element > $n_ids - 1);

	  }

        #### If the relationship is an Associative unique child, delete
	} elsif ($child_type eq 'A') {

          #### Get the child table name ids to be deleted
          my $child_PK = $table_PK_column_names{$child_table_name} ||
            "${child_table_name}_id";
          my $parent_PK = $table_PK_column_names{$table_name} ||
            "${table_name}_id";
	  my $sql = "
	    SELECT $child_PK
            FROM ${DATABASE}$table_name
            WHERE $parent_PK IN (".join(",",@{$delete_PKs}).")
            AND $child_PK IS NOT NULL
          ";
	  print "$sql\n\n" if ($VERBOSE > 1);
	  print "SELECT #2 with ",scalar(@{$delete_PKs})," element IN\n\n"
            if ($VERBOSE);
          my @child_PKs = $self->selectOneColumn($sql);

          #### Delete them
	  if (scalar(@child_PKs) > 0) {
  	    print "Recursing to delete $child_table_name\n" if ($VERBOSE);
            my $result = $self->deleteRecordsAndChildren(
              table_name => $child_table_name,
              table_child_relationship => $table_child_relationship,
              table_PK_column_names => $table_PK_column_names,
              delete_PKs => \@child_PKs,
              delete_batch => $delete_batch,
              database => $DATABASE,
              verbose => $VERBOSE,
              quiet => $QUIET,
              testonly => $TESTONLY,
            );
	  }


        #### If the relationship is a KeyLess Child, just delete by parent key
	} elsif ($child_type eq 'PKLC') {
	  
	   #### Get the number of records to delete and set the first and last
  	  my $n_ids = scalar(@{$delete_PKs});
  	  my $first_element = 0;
  	  my $last_element = $n_ids - 1;

  	  #### If the user requested to delete in batches, possibly
          #### reduce the last
  	  if ($delete_batch && $n_ids > $delete_batch) {
  	    $last_element = $delete_batch - 1;
  	  }

  	  #### While there are still records to delete, do it
  	  while ($first_element < $n_ids) {
  	    #### Get the records to delete in this batch
  	    my @ids = @{$delete_PKs};
  	    @ids = @ids[$first_element..$last_element];
	  
	  
      	  #### Create the SQL and do the DELETE
          my $parent_PK = $table_PK_column_names{$table_name} ||
            "${table_name}_id";
      	  my $sql = "DELETE FROM ${DATABASE}$child_table_name ".
            "WHERE $parent_PK IN (".join(",",@ids).")";
      	  print "$sql\n\n" if ($VERBOSE > 1);
      	  print "  DELETING FROM PKLC_2 $child_table_name by $parent_PK NUMBER OF RECORDS:" .scalar(@ids) ."\n"
      	    if ($VERBOSE);
      	  print "." unless ($QUIET || $VERBOSE);
      	  $self->executeSQL($sql) unless ($TESTONLY);

	  #### Update the first and last batch block pointers if relevant
  	    last unless ($delete_batch);
  	    $first_element += $delete_batch;
  	    $last_element += $delete_batch;
  	    $last_element = $n_ids - 1 if ($last_element > $n_ids - 1);
	  
	  }
        #### Otherwise there was a parsing error or an unimplemented type
        } else {
          die("ERROR: Unrecognized child type '$child_type'");
        }


      } else {
        die("ERROR: Unable to parse relationship '$element'");
      }

    }

  }


  #### All children should be gone we hope, so finally delete these records
  unless ($keep_parent_record) {

     #### Get the number of records to delete and set the first and last
     my $n_ids = scalar(@{$delete_PKs});
     my $first_element = 0;
     my $last_element = $n_ids - 1;

     #### If the user requested to delete in batches, possibly reduce the last
     if ($delete_batch && $n_ids > $delete_batch) {
       $last_element = $delete_batch - 1;
     }

     #### While there are still records to delete, do it
     while ($first_element < $n_ids) {
       #### Get the records to delete in this batch
       my @ids = @{$delete_PKs};
       @ids = @ids[$first_element..$last_element];

       #### Create the SQL and do the DELETE
       my $parent_PK = $table_PK_column_names{$table_name} ||
         "${table_name}_id";
       my $sql = "DELETE FROM ${DATABASE}$table_name WHERE $parent_PK IN (".
         join(",",@ids).")";
       print "$sql\n\n" if ($VERBOSE > 1);
       print "  DELETING FROM $table_name (batch $first_element / $n_ids)\n"
         if ($VERBOSE);
       print "." unless ($QUIET || $VERBOSE);
       $self->executeSQL($sql) unless ($TESTONLY);

       #### Update the first and last batch block pointers if relevant
       last unless ($delete_batch);
       $first_element += $delete_batch;
       $last_element += $delete_batch;
       $last_element = $n_ids - 1 if ($last_element > $n_ids - 1);
     }
  } #end delete Parent Record and PKs

  return 1;

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
  my $constraint_NOT_flag = $args{'constraint_NOT_flag'} || '';
  my $verbose = $args{'verbose'} || 0;


  #### Make sure the NOT flag is either NOT or nothing
  $constraint_NOT_flag = '' unless ($constraint_NOT_flag eq 'NOT');


  #### Strip leading and trailing whitespace
  return '' unless (defined($constraint_value));
  $constraint_value =~ s/^\s+//;
  $constraint_value =~ s/\s+$//;


  #### If no value was provided, simply return an empty string
  #### Don't return is the value is "0" because that may be a value
  return '' if ($constraint_value eq "");


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
    } elsif ($constraint_value =~ /^(not )*between\s+[\d]+\s+and\s+[\d]+$/i) {
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
    if ($constraint_value =~ /^(not )*between\s+[\d\.\-\+]+\s+and\s+[\d\.\-\+]+$/i) {
      return "   AND $constraint_column $constraint_value";
    } elsif ($constraint_value =~ /^(\-*[\d\.]+)\s*\+\-\s*([\d\.]+)$/i) {
      my $lower = $1 - $2;
      my $upper = $1 + $2;
      return "   AND $constraint_column BETWEEN $lower AND $upper";
    } elsif ($constraint_value =~ /^\s*[><=][=]*\s*[\d\.eE\-\+]+\s*$/) {
      return "   AND $constraint_column $constraint_value";
    } elsif ($constraint_value =~ /^[\d\.eE\-\+]+$/) {
      return "   AND $constraint_column = $constraint_value";
    } else {
      print "<H4>Cannot parse $constraint_name constraint ".
        "'$constraint_value'!  Check syntax.</H4>\n\n";
      return -1;
    }
  }


  #### Parse type int_list: a list of integers like "+1, 2,-3"
  if ($constraint_type eq "int_list") {
    print "Parsing int_list $constraint_name<BR>\n" if ($verbose);
    if ($constraint_value =~ /^[\+\-\d,\s]+$/ ) {
      return "   AND $constraint_column IN ( $constraint_value )";
    } else {
      print "<H4>Cannot parse $constraint_name constraint ".
        "'$constraint_value'!  Check syntax.</H4>\n\n";
      return -1;
    }
  }


  #### Parse type plain_text: a plain, unquoted bit of text
  #if ($constraint_type eq "plain_text") {
  #  print "Parsing plain_text $constraint_name<BR>\n" if ($verbose);
  #  print "constraint_value = $constraint_value<BR>\n" if ($verbose);
  #
  #  #### Convert any ' marks to '' to appear okay within the strings
  #  $constraint_value = $self->convertSingletoTwoQuotes($constraint_value);
  #
  #  #### Bad word checking here has been disabled because the string will be
  #  #### quoted, so there shouldn't be a way to put in dangerous SQL...
  #  #if ($constraint_value =~ /SELECT|TRUNCATE|DROP|DELETE|FROM|GRANT/i) {}
  #
  #  my $tmp = $constraint_NOT_flag;
  #  $constraint_NOT_flag .= ' ' if ($constraint_NOT_flag);
  #  return "   AND $constraint_column ${tmp}LIKE '$constraint_value'";
  #}


  #### Parse type plain_text: a semicolon separated list that uses
  #### LIKEs and can thus contain wildcards
  if ($constraint_type eq "plain_text") {
    print "Parsing plain_text $constraint_name<BR>\n" if ($verbose);
    my @items = split(";",$constraint_value);
    my $constraint_string = '';

    #### Loop over all items, building constraint list
    my $combiner = '';
    foreach my $element (@items) {

      #### Allow individual negations
      my $is_negated = 0;
      if (substr($element,0,1) eq '!') {
	$element = substr($element,1,9999);
	$is_negated = 1;
      }

      #### Enquote the string
      my $quoted_element = "'".$self->convertSingletoTwoQuotes($element)."'";

      #### Configure the NOT flag
      my $use_NOT_flag = $constraint_NOT_flag;
      if ($is_negated) {
	#### Switch the sense of the NOT flag
	if ($use_NOT_flag) {
	  $use_NOT_flag = '';
	} else {
	  $use_NOT_flag = 'NOT';
	}
	#### Switch the sense of the combiner
	if ($combiner =~ /OR/) {
	  $combiner =~ s/OR/AND/;
	} else {
	  $combiner =~ s/AND/OR/;
	}
      }
      my $NOT_flag = $use_NOT_flag;
      $NOT_flag .= ' ' if ($use_NOT_flag);

      #### Build the constraint string
      $constraint_string .= "${combiner}$constraint_column ".
        "${NOT_flag}LIKE $quoted_element";
      $combiner = "\n               OR ";
      $combiner = "\n               AND " if ($constraint_NOT_flag);
    }

    #### Put final constraint string into parens
    return "   AND ( $constraint_string\n             )";
  }


  #### Parse type text_list: a list of strings separated by commas
  if ($constraint_type eq "text_list") {
    print "Parsing text_list $constraint_name<BR>\n" if ($verbose);
    my @tmplist = split(",",$constraint_value);
    my $constraint_string = '';
    foreach my $element (@tmplist) {
      $constraint_string .= "'".$self->convertSingletoTwoQuotes($element)."',";
    }
    chop($constraint_string);  # Remove last comma

    my $tmp = $constraint_NOT_flag;
    #$constraint_NOT_flag .= ' ' if ($constraint_NOT_flag);
    $tmp .= ' ' if ($constraint_NOT_flag);
    return "   AND $constraint_column ${tmp}IN ( $constraint_string )";
  }


  die "ERROR: unrecognized constraint_type!";

}


###############################################################################
# translateOptionValue
#
# arg SQL query as passed to buildOptionList
# arg VALUE(s) to match
#
# Given an SQL query which defines two columns (value and name), and a
# value for which a match is desired.  If a match is found, return name, 
# else return empty string ''
###############################################################################
sub translateOptionValue {
    my $self = shift;
    my $query = shift;
    my @values = @_;

    # No values?
    return '' if !scalar( @values );

    # For lots of values, hash lookup is far faster
    my %values;
    for( @values ) { $values{$_}++ } 

    # Get hash with option list names keyed by values
    $query = $self->translateSQL(sql=>$query);
    my %options = $self->selectTwoColumnHash( $query );

    my $match = '';
 
    for( keys( %values ) ) {
    # writing as array grep since we'll have to handle multiselects
    $match .= "$options{$_} " if $options{$_};
    } # end while

    return $match;
} # End translateOptionValue

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
    my $selected_option = shift || '';
    my $method_options = shift || '';
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

    #### Convert the SQL dialect if necessary
    $sql_query = $self->translateSQL(sql=>$sql_query); 
      
    ##for debugging:
    ##$self->display_sql(sql=>$sql_query);
    my $options="";
    my $sth = $dbh->prepare("$sql_query") or croak $dbh->errstr;
    my $rv  = $sth->execute;
    unless( $rv ) {
      $log->printStack();
      $log->error( "DBI ERR:\n" . $dbh->errstr . "\nSQL: $sql_query" );
      croak $dbh->errstr;  
    }

    while (my @row = $sth->fetchrow_array) {
        $selected_flag="";
	if ($selected_options{$row[0]}) {
	  $selected_flag=" SELECTED";
	  delete($selected_options{$row[0]});
	}
        $options .= qq!<OPTION$selected_flag VALUE="$row[0]">$row[1]\n!;
    } # end while

    $sth->finish;

    #### Look through the list of requested id's and delete any that
    #### weren't in the list of available options
    my @valid_options = ();
    my $invalid_option_present = 0;
    foreach my $id (@tmp) {
      if ($selected_options{$id}) {
	$invalid_option_present = 1;
      } else {
	push(@valid_options,$id);
      }
    }
    #### If there were some invalid options, then append the list of valid
    #### ones.  This is an ugly hack. FIXME
    if ($invalid_option_present) {
      $options .= "<!--".join(',',@valid_options)."-->\n";
    }

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

    #### Convert the SQL dialect if necessary
    $sql_query = $self->translateSQL(sql=>$sql_query);

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
       # $precisions[$i],"<BR>\n";
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
  if (defined($flag) && $flag == 1) {
    #print "Test if rewindable: yes<BR>\n";
    return 1;
  }

  #### If flag > 1, then really do the rewind
  if (defined($flag) && $flag > 1) {
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

    my %typelist = ( 1=>"varchar", 4=>"int", 2=>"numeric", 6=>"float", #7=>"real",
      11=>"date",-1=>"text" );
    my ($i,$type,$newtype);
    my @types = @{$types_ref};
    my @newtypes;

    for ($i = 0; $i <= $#types; $i++) {
      $type = $types[$i];
      $newtype = $typelist{$type} || $type;
      push(@newtypes,$newtype);
      
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


    #### Update timing info
    $timing_info->{send_query} = [gettimeofday()];


    #### Convert the SQL dialect if necessary
    $sql_query = $self->translateSQL(sql=>$sql_query);

    #### Execute the query
    $sth = $dbh->prepare("$sql_query") ||
      croak("Unable to prepare query:\n".$dbh->errstr);
    my $rv  = $sth->execute ||
      croak("Unable to execute query: $sql_query \n".$dbh->errstr);


    #### Update timing info
    $timing_info->{begin_resultset} = [gettimeofday()];


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


    #### Update timing info
    $timing_info->{finished_resultset} = [gettimeofday()];


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
    my $base_url = $args{'base_url'} || '';
    my $query_parameters_ref = $args{'query_parameters_ref'};
    my $cytoscape = $args{'cytoscape'} || undef;

    # Improved formatting capacity, DSC 2005-08-09
    my $no_escape = $args{no_escape} || 0;
    my $nowrap = ( $args{nowrap} ) ? ' NOWRAP' : '';

    my $resort_url = '';
    if ($base_url) {
      my $separator = '?';
      $separator = '&' if ($base_url =~ /\?/);
      $resort_url="$base_url${separator}apply_action=VIEWRESULTSET&".
          "rs_set_name=$rs_params_ref->{set_name}";
    }


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
 
    #### If the command to re-sort was passed, do it now
    if (defined($rs_params_ref->{rs_resort_column}) &&
	$rs_params_ref->{rs_resort_column} gt '') {

      #### Put the column number and type into global variables to be
      #### used by the sort-decision subroutines
      $SORT_COLUMN = $rs_params_ref->{rs_resort_column};
      $SORT_TYPE = $rs_params_ref->{rs_resort_type} || 'ASC';

      #### Define the datatypes that get sorted numerically
      my @sorted_rows;
      my %numerical_types = ('int'=>1,'float'=>1);
      my $do_numerical_sort = 0;
      $do_numerical_sort = 1 if ($numerical_types{$types_ref->[$SORT_COLUMN]});

      #### If it's not a numerical column, have a look at it anyway
      #### to see if they're all numbers
      unless ($do_numerical_sort) {
        $do_numerical_sort = $self->isResultsetColumnNumerical(
          data_ref => $resultset_ref->{data_ref},
          column_index => $SORT_COLUMN,
        );
      }

      if ($do_numerical_sort) {
        @sorted_rows = sort resultsetNumerically
          @{$resultset_ref->{data_ref}};

      #### Otherwise, sort them alphabetically
      } else {
        @sorted_rows = sort resultsetByCharacter
          @{$resultset_ref->{data_ref}};
      }

      #### Put the re-sorted rows into the resultset
      $resultset_ref->{data_ref} = \@sorted_rows;

      #### Write the resultset back out to the same file.  Need to do
      #### this so that the user can page through the re-sorted resultset
      $self->writeResultSet(resultset_file_ref=>\$rs_params_ref->{set_name},
        resultset_ref=>$resultset_ref,
        query_parameters_ref=>$query_parameters_ref);
    }


    #### Make some adjustments to the default column width settings
    my @precisions = @{$resultset_ref->{precisions_list_ref}};
    my $i;
    for ($i = 0; $i <= $#precisions; $i++) {
      #### Set the width to negative (variable)
      $precisions[$i] = (-1) * $precisions[$i] - 10;

      #### Override the width if the user specified it
      $precisions[$i] = $max_widths_ref->{$sth->{NAME}->[$i]}
        if ($max_widths_ref->{$sth->{NAME}->[$i]});

      #### Set the precision to 20 for dates (2001-01-01 00:00:01)
      $precisions[$i] = 20 if ($types_ref->[$i] =~ /date/i);

      #### Print for debugging
    #  print $column_titles_ref->[$i],"(",$types_ref->[$i],"): ",
    #    $precisions[$i],"<BR>\n";
    }


    #### If the desired output format is TSV-like, dump out the data that way
    if ($self->output_mode() =~ /tsv|csv|excel/) {
      my @row;

      #### If the invocation_mode is http, provide a header
      my $delimiter = "\t";
      my $header = "Content-type: text/tab-separated-values\n\n";

      if ($self->invocation_mode() eq 'http') {
        if ($self->output_mode() =~ /tsv/) {
          $header = "Content-type: text/tab-separated-values\n\n";
          $delimiter = "\t";
        } elsif ($self->output_mode() =~ /csv/) {
          $header = "Content-type: text/comma-separated-values\n\n";
          $delimiter = ",";
        } elsif ($self->output_mode() =~ /excel/) {
          $header = "Content-type: application/excel\n\n";
          $delimiter = "\t";
		}
      }

      print $header if ($self->invocation_mode() eq 'http');


      #### Set a very high page size if using defaults
      $resultset_ref->{page_size} = 1000000
        if ($rs_params_ref->{default_values} eq 'YES');

      #### Get the hidden column hash
      my %hidden_cols;
      %hidden_cols = %{$hidden_cols_ref} if ($hidden_cols_ref);

      #### Make tools for finding unacceptable columns to output
      #### The following are removed:
      #### 1) Hidden Columns if output_mode is tsv | csv | excel and does not contain 'full'
      #### 2) if the data starts with '[' 
      ####    NOTE: only the first column is used for thiS!
      my @no_print_columns;
      my @all_columns = @{$resultset_ref->{column_list_ref}};

#         my @first_data_col = @{@{$resultset_ref->{data_ref}}[0]};
	  #### Look at FIRST data column to identify potential links
#	  for (my $column = 0; $column < $#first_data_col; $column++) {
#		if ($first_data_col[$column] =~ /^\s*\[/ && 
#			$self->output_mode() !~ /http|full/) {
#		  $no_print_columns[$column] = 1;
#		}
#	  }
#	  undef @first_data_col;

      #### Convert to a delimiter-safe format
      my @output_row = ();

	  ## If output_mode is tsvfull, append URL column for each column with a hyperlink
	  my @tsvfull_urls = ();
	  my %tsvfull_url_column_number = ();
	  my @tsvfull_column_headers = ();

      for (my $column = 0; $column < scalar(@all_columns); $column++){
	  #### If this column's already been flagged for removal, continue;
		next if ($no_print_columns[$column]);

		my $datum = $all_columns[$column];

		#### Flag Columns to REMOVAL from printing. 
		if ($self->output_mode() eq 'tsv' || $self->output_mode() eq 'csv' ||
            $self->output_mode() eq 'excel') {
		  if ($hidden_cols{$datum}) {
			$no_print_columns[$column] = 1;
			next;
		  } else {
			$no_print_columns[$column] = 0;
		  }
		}

		if ($self->output_mode() eq 'tsvfull') {
		  if ($url_cols_ref->{$column_titles_ref->[$column]}) {
			my $link = $url_cols_ref->{$column_titles_ref->[$column]};
			$tsvfull_url_column_number{$link} = $column;
			push (@tsvfull_urls, $link);
			my $url_column_title = $datum."_URL";
			push(@tsvfull_column_headers, $url_column_title);
		  }
		}

		if ($datum =~ /[\t,\"]/) {
		  $datum =~ s/\t/ /g if ($self->output_mode() =~ /tsv/);
		  $datum =~ s/\"/""/g;
		  $datum = "\"$datum\"";
		}
		push(@output_row,$datum);
	  }
	  push (@output_row, @tsvfull_column_headers);
      print join($delimiter,@output_row),"\n";

      #### Print out individual data rows, removing any flagged columns
      while (@row = returnNextRow()) {
        @output_row = ();

		for (my $column = 0; $column < scalar(@row); $column++){
		  my $datum = $row[$column];
		  next if ( defined $no_print_columns[$column] && $no_print_columns[$column] == 1);
          if ( defined $datum && $datum =~ /[\t,\",\n]/) {
            $datum =~ s/\t/ /g if ($self->output_mode()  =~ /tsv/);

            # Substitute stray \n characters, Mantis bug 0000046
            $datum =~ s/\r?\n/\\n/g if ($self->output_mode() =~ /tsv|csv/);
            $datum =~ s/\"/""/g;
            $datum = "\"$datum\"";
          }
          push(@output_row,$datum);
        }

		if ($self->output_mode() eq 'tsvfull') {
		  foreach my $tsvfull_url (@tsvfull_urls) {
			my $temp_url = $tsvfull_url;
			my $linked_column_number = $tsvfull_url_column_number{$temp_url};
			$temp_url =~ s/\%(\d+)V/$row[$1]/g;
			$temp_url =~ s/\%V/$row[$linked_column_number]/g;
			push (@output_row, $temp_url);
		  }
		}
		
        @output_row = map  { ( defined $_ ) ? $_ : '' } @output_row; 
        print join($delimiter,@output_row),"\n";

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
          $element =~ s/\s/_/g;			#added to remove any white space in attributes tags pmoss 7.30.04
	  $value = $row[$i];
          $value =~ s/</&lt;/g;			#replace <
	  $value =~ s/>/&gt;/g;			#replace >
	  $value =~ s/\"/\'/g;
          $value =~ s/&/&amp;/g;
          print "    $element=\"$value\"\n";
          $i++;
        }
        print "  />\n";
      }
      print "</resultset>\n";
      return;
    }


    #### If the desired output format is Cytoscape, prepare a temp directory
    #### for the files and return the jnlp xml
   
    if ($self->output_mode() eq 'cytoscape' && defined($cytoscape)) {
      if ( ! -d "$PHYSICAL_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/" &&
      		$cytoscape->{cytoscape_type} ne 'cytoscape_ps') {
	mkdir("$PHYSICAL_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/") ||
	  die("ERROR: Unable to mkdir $PHYSICAL_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/");
      }

      my $identifier = $rs_params_ref->{'set_name'} || 'unknown';
      if ( ! -d "$PHYSICAL_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/$identifier" &&
      		 $cytoscape->{cytoscape_type} ne 'cytoscape_ps') {
	mkdir("$PHYSICAL_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/$identifier") ||
	  die("ERROR: Unable to mkdir $PHYSICAL_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/$identifier");
      }

      #select the out folder, Currently must deside if this a Immunostain/SummarizeStains or Microarray/GetExpression session to
      #launch the ps_cyctoscape flavor 
	my $out_folder = "";
  	if (defined $cytoscape->{cytoscape_type} && $cytoscape->{cytoscape_type} eq 'cytoscape_ps'){
		$out_folder = "$PHYSICAL_BASE_DIR/tmp/Microarray/GetExpression/jws/$identifier";
	}else{
		$out_folder = "$PHYSICAL_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/$identifier";
	}
     
      my $template = $cytoscape->{template};
      system("/bin/cp -p $PHYSICAL_BASE_DIR/lib/cytoscape/$SBEAMS_SUBDIR/$template/* $out_folder/");
      
        
      foreach my $file (keys %{$cytoscape->{files}}) {
	my $outfile = "$out_folder/$file";
	
	open(OUTFILE,">$outfile") || die("ERROR: Unable to open file $outfile");
	foreach my $line ( @{$cytoscape->{files}->{$file}} ) {
	  print OUTFILE "$line\n" if (defined($line));
	}
	close(OUTFILE);

      }

 
      #### Make the data.jar
      system("( cd $out_folder/ ; /usr/bin/make >& make.out )");

      ##Redirect to the gaggle version of cytoscape if we need to
      if(defined $cytoscape->{cytoscape_type} && $cytoscape->{cytoscape_type} eq 'cytoscape_ps'){
      
	my $url = "$HTML_BASE_DIR/tmp/Microarray/GetExpression/jws/$identifier/index.html";
	
	print $q->redirect("$url");
      
      }
      
      #### If the invocation_mode is http, provide a header
      if ($self->invocation_mode() eq 'http') {
        print "Content-type: application/x-java-jnlp-file\n\n";
      }

     
      #### Update the jnlp file with the latest information
     	 my $infile = "$PHYSICAL_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/$identifier/cytoscape.jnlp";
     	 open(INFILE,$infile) || die("ERROR: Unable to open $infile");
     	my $buffer = '';
     	 while (my $line = <INFILE>) {
		if ($line =~ /codebase=/) {
		  $line =~ s~codebase=\".+\"~codebase="$SERVER_BASE_DIR/$HTML_BASE_DIR/tmp/Immunostain/SummarizeStains/jws/$identifier"~;
		}elsif($line =~ /CYTOSCAPE_JAR_HOOK/){
			$line =~ s~CYTOSCAPE_JAR_HOOK~$SERVER_BASE_DIR/$HTML_BASE_DIR/usr/java/share/Cytoscape/cytoscape_1.0.jar~;
		}
		
		$buffer .= $line;
     	 }
      	close(INFILE);
      	open(OUTFILE,">$infile") || die("ERROR: Unable to open $infile for writing");
      	print OUTFILE $buffer;
      	close(OUTFILE);
    
      #### Send the jnlp xml
      print $buffer;
     
     

     
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
        THformats=>["BGCOLOR=".$row_color_scheme_ref->{header_background} . $nowrap],
        TDformats=>['NOWRAP'],
        no_escape => $no_escape
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
        THformats=>["BGCOLOR=".$row_color_scheme_ref->{header_background} . $nowrap],
        TDformats=>\@TDformats,
        row_color_scheme=>$row_color_scheme_ref,
        base_url=>$base_url,
        image_dir=>"$HTML_BASE_DIR/images",
        resort_url=>$resort_url,
        no_escape => $no_escape
      };

    }


    #### finish up
    print "\n";

    return 1;


} # end displayResultSet


###############################################################################
# isResultsetColumnNumerical
#
# A simple test to see if the specified column can be treated numerically
###############################################################################
sub isResultsetColumnNumerical {
  my $self = shift;
  my %args = @_;

  #### Process the arguments list
  my $data_ref = $args{'data_ref'};
  my $column_index = $args{'column_index'};

  die("column_index not passed") unless defined($column_index);
  die("data_ref not passed") unless defined($data_ref);

  #### Loop though all elements to see if they're all consistent with
  #### Being numerical
  foreach my $element (@{$data_ref}) {
    next if ($element->[$column_index] =~ /^[0-9\.\+\-e\s]*$/);
    return 0;
  }

  return 1;

}



###############################################################################
# resultsetByCharacter
#
# Sorting function to sort resultsets
###############################################################################
sub resultsetByCharacter {

  if ($SORT_TYPE eq 'ASC') {
    return lc($a->[$SORT_COLUMN]) cmp lc($b->[$SORT_COLUMN]);
  } else {
    return lc($b->[$SORT_COLUMN]) cmp lc($a->[$SORT_COLUMN]);
  }

}



###############################################################################
# resultsetNumerically
#
# Sorting function to sort resultsets
###############################################################################
sub resultsetNumerically {

  if ($SORT_TYPE eq 'ASC') {
    return $a->[$SORT_COLUMN] <=> $b->[$SORT_COLUMN];
  } else {
    return $b->[$SORT_COLUMN] <=> $a->[$SORT_COLUMN];
  }

}



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
    my $cytoscape = $args{'cytoscape'} || undef;

    my %rs_params = %{$rs_params_ref};
    my %parameters = %{$query_parameters_ref};


    #### Start form
    my $BR = "\n";
    if ($self->output_mode() eq 'html') {
      $BR = "<BR>\n";
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

    my $row_limit = $parameters{row_limit} || 1000000;
    if ( $row_limit == scalar(@{$resultset_ref->{data_ref}}) ) {
      if ($self->output_mode() eq 'html') {
        print "&nbsp;&nbsp;(<font color=red>WARNING: </font>Resultset ".
	  "truncated at $row_limit rows. ".
	  "Increase row limit to see more.)\n";
      } else {
        print "WARNING: Resultset ".
	  "truncated at $row_limit rows. ".
	  "Increase row limit to see more.)\n";
      }
    }



    #### If the output mode is not html, then finish here
    if ($self->output_mode() ne 'html') {
      $self->displayTimingInfo();
      return;
    }


    #### Determine the URL separator
    my $separator = '?';
    $separator = '&' if ($base_url =~ /\?/);


    #### Provide links to the other pages of the dataset
    print "<BR>Result Page \n";
    $i=0;
    my $nrowsminus = $nrows - 1 if ($nrows > 0);
    my $npages = int($nrowsminus / $rs_params{page_size}) + 1;
    for ($i=0; $i<$npages; $i++) {
      my $pg = $i+1;

      if ( ( $i % 50 ) == 0 ) {
          print "<BR>";
      }

      if ($i == $rs_params{page_number}) {
        print "[<font color=red>$pg</font>] \n";
      } else {
        print "<A HREF=\"$base_url${separator}apply_action=VIEWRESULTSET&".
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
    my @output_modes = (
      ['excel','xls','Excel'],
      ['xml','xml','XML'],
      ['tsv','tsv','TSV'],
      ['csv','csv','CSV'],
    );

    #### If we have Cytoscape information, add that
    if (defined($cytoscape)) {
     push(@output_modes,
	   ['cytoscape','jnlp','Cytoscape'],
	);
      
    }


    print "<BR>Download ResultSet in Format: \n";
    my $first_flag = 1;

    #### Loop over each mode, building the URL to get this dataset
    foreach my $output_mode_ref (@output_modes ) {
      my $output_mode = $output_mode_ref->[0];
      my $output_mode_ext = $output_mode_ref->[1];
      my $output_mode_name = $output_mode_ref->[2];
      my $url_prefix = "$base_url${separator}";
      $url_prefix =~ s/\?/\/$rs_params{set_name}\.$output_mode_ext\?/;
      print ",\n" unless ($first_flag);
      $first_flag = 0;
      print "<A HREF=\"${url_prefix}apply_action=VIEWRESULTSET&rs_set_name=$rs_params{set_name}&rs_page_size=1000000&output_mode=$output_mode\">$output_mode_name</A>";
    }


    #### For certain types of resultsets, we'll allow a cytoscape trigger
    my $cytoscape_url_prefix = "$CYTOSCAPE_URL/sbeams";
    my $cytotest_url_prefix = "http://hazel.systemsbiology.net:8080/cytoscape/sbeamsTest";
    my $current_username = $self->getCurrent_username();
    if ($resultset_ref->{column_list_ref}->[0] eq 'interaction_id') {
      print "<BR>\n<A HREF=\"${cytoscape_url_prefix}?m=interactions&rs=$rs_params{set_name}\">[View this Resultset with Cytoscape]</A>";
      #print "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"${cytoscape_url_prefix}?m=NIDA&rs=$rs_params{set_name}\">[NIDA]</A>";
      #print "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"${cytotest_url_prefix}?m=interactions&rs=$rs_params{set_name}\">[test]</A>";
    } elsif ($resultset_ref->{column_list_ref}->[0] eq 'Bait' ||
             $resultset_ref->{column_list_ref}->[1] eq 'Bait') {
      print "<BR>\n<A HREF=\"${cytoscape_url_prefix}?m=agingras&rs=$rs_params{set_name}\">[View this Resultset with Cytoscape]</A>";
    } elsif ($resultset_ref->{column_list_ref}->[0] eq 'condition_name' || $FindBin::Script =~ /GetExpression/) {
      print "<BR>\n<A HREF=\"http://db.systemsbiology.net/cytoscape/sbeamsTest?microarray_resultset=$rs_params{set_name}&action=Cytoscape+test&m=merge&username=$current_username\">[View this Resultset with Cytoscape]</A>";
      #print "<BR>\n<A HREF=\"${cytoscape_url_prefix}?m=microarray&rs=$rs_params{set_name}\">[View this Resultset with Cytoscape]</A>";
      #print "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<A HREF=\"${cytotest_url_prefix}?m=microarray&rs=$rs_params{set_name}\">[test]</A>";
    } elsif ($resultset_ref->{column_list_ref}->[0] eq 'prophet number') {
      print "<BR>\n<A HREF=\"${cytoscape_url_prefix}?m=rchen&rs=$rs_params{set_name}\">[View this Resultset with Cytoscape]</A>";
    } elsif ($resultset_ref->{column_list_ref}->[0] eq 'Systematic') {
      print "<BR>\n<A HREF=\"${cytoscape_url_prefix}?m=blin&rs=$rs_params{set_name}\">[View this Resultset with Cytoscape]</A>";
    } elsif ($resultset_ref->{column_hash_ref}->{biosequence_accession}) {
      print "<BR>\n<A HREF=\"${cytoscape_url_prefix}?m=generic&rs=$rs_params{set_name}\">[View this Resultset with Cytoscape]</A>";
    }


    #### If this resulset has a name, show it and the date is was created
    if (defined($rs_params_ref->{cached_resultset_id})) {
      print qq~
        <BR><A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=cached_resultset&cached_resultset_id=$rs_params_ref->{cached_resultset_id}">[Annotate this Resultset]</A>
        Name: '$rs_params_ref->{resultset_name}'
        ($rs_params_ref->{date_created})
      ~;
    }

    print "\n<BR>\n";


    #### Supply URLs to get back to this resultset or redo this query
    my $pg = $rs_params{page_number}+1;
    my $param_string = "";
    while ( ($key,$value) = each %{$query_parameters_ref} ) {
      if ($value gt '' && $key ne 'TABLE_NAME') {
        $param_string .= "&" if ($param_string);
        $value = uri_escape($value);
	$value =~ s/\+/\%2b/g;
        $param_string .= "$key=$value";
      }
    }


    #### If there are plotting parameters set, include those
    my $plot_params = '';
    foreach my $param_name ('rs_plot_type','rs_columnA','rs_columnB') {
      if ($rs_params{$param_name}) {
        $plot_params .= "&$param_name=".$rs_params{$param_name};
      }
    }


    #### Display the URLs to reaccess these data
    if ($base_url =~ /ManageTable/) {
      $param_string = "${separator}$param_string" if ($param_string);
    } else {
      $param_string = "${separator}$param_string" if ($param_string);
      $param_string .= "&apply_action=QUERY";
    }


    #### Strip out login information if it's there!
    foreach my $stripword ( qw ( password username login force_login ) ) {
      $param_string =~ s/([\?\&])$stripword=.+?[\&]/$1/;
      $param_string =~ s/[\?\&]$stripword=.+$//;
    }

    my $reexec_url = "${base_url}${param_string}"; 
    my $recall_url = "$base_url${separator}apply_action=VIEWRESULTSET&" .
                     "rs_set_name=$rs_params{set_name}&rs_page_size" .
                     "=$rs_params{page_size}&rs_page_number=$pg$plot_params";
    
    my $url_base = $SERVER_BASE_DIR . $CGI_BASE_DIR;
    
    my $reexec_key = $self->setShortURL( $reexec_url );
    my $recall_key = $self->setShortURL( $recall_url );


    print qq~
      <BR>
      <NOBR>URL to
      <A HREF=\"$recall_url\"> recall this result set</A>: ${url_base}/shortURL?key=$recall_key
      </NOBR>

      <BR>
      <NOBR>URL to
      <A HREF=\"$reexec_url\"> re-execute this query</A>: ${url_base}/shortURL?key=$reexec_key
      </NOBR>
      <BR>
    ~;

    $self->displayTimingInfo();

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
# displayResultSetPlot
#
# Displays a plot of data based on the information in the ResultSet
###############################################################################
sub displayResultSetPlot {
    my $self = shift;
    my %args = @_;


    #### If the output mode is not html, do not make plot
    if ($self->output_mode() ne 'html') {
      return;
    }


    my ($i,$element,$key,$value,$line,$result,$sql);

    #### Process the arguments list
    my $resultset_ref = $args{'resultset_ref'};
    $rs_params_ref = $args{'rs_params_ref'};
    my $query_parameters_ref = $args{'query_parameters_ref'};
    my $column_titles_ref = $args{'column_titles_ref'};
    my $base_url = $args{'base_url'};

    my %rs_params = %{$rs_params_ref};
    my %parameters = %{$query_parameters_ref};

    #print "here1<BR>rs_plot_type=$rs_params{rs_plot_type}<BR>rs_columnA=$rs_params{rs_columnA}\n";
    #### If there is not a specific request to make a plot, then return
    #unless ($rs_params{rs_plot_type} && $rs_params{rs_columnA} gt "") {
    #  return;
    #}


    #### Start form
    my $BR = "\n";
    if ($self->output_mode() eq 'html') {
      $BR = "<BR>\n";
      print qq~<BR><BR>
      <TABLE WIDTH="680" BORDER=0>
      <FORM METHOD="POST">
      ~;
    }


    #### If rs_columnA,B is defined, extract it
    my $column_info;
    foreach my $column_index ( 'A','B' ) {
      $column_info->{$column_index}->{name} = '';
      $column_info->{$column_index}->{data} = ();
      if (defined($rs_params{"rs_column$column_index"}) &&
	  $rs_params{"rs_column$column_index"} gt '') {
        foreach my $element (@{$resultset_ref->{data_ref}}) {
          my $value = $element->[$rs_params{"rs_column$column_index"}];
          if ($value =~ /([\d\.\-\+]+)/) {
            $value = $1;
          } else {
            $value = '';
          }
          push(@{$column_info->{$column_index}->{data}},$value);
        }
        $column_info->{$column_index}->{name} = 
          $column_titles_ref->[$rs_params{"rs_column$column_index"}] ||
          $resultset_ref->{column_list_ref}->[$rs_params{"rs_column$column_index"}];
      }
    }


    #### Create a temp file name to write to
    my $tmpfile = "plot.$$.@{[time]}.png";
    #print "Writing PNG to: $PHYSICAL_BASE_DIR/images/tmp/$tmpfile\n";


    #### Make the plot
    my $graph;
    my @data;


    #### If the plot_type is histogram, plot it
    if (defined($rs_params{rs_plot_type}) &&
	$rs_params{rs_plot_type} eq 'histogram') {
      $result = $self->histogram(
        data_array_ref=>$column_info->{A}->{data},
      );

      if ($result->{result} eq 'SUCCESS') {

        #### Populate a data structure to plot
        @data = (
          $result->{xaxis_disp},
          $result->{yaxis},
        );

        #### Create the histogram canvas
        $graph = GD::Graph::bars->new(640, 500);

        #### Set the various plot parameters
        $graph->set(
            x_label           => $column_info->{A}->{name},
            y_label           => 'Count',
            title             => "Histogram of ".$column_info->{A}->{name},
            x_tick_length     => -4,
            axis_space        => 6,
            x_label_position  => 0.5,
            y_min_value       => 0,
            x_halfstep_shift  => 0,
        );

      } else {
        print "ERROR: Unable to calculate histogram for column ".
          $rs_params{rs_columnA};
        $result = undef;
      }


    #### If the plot_type is xypoints, plot it
    } elsif (defined($rs_params{rs_plot_type}) &&
	     $rs_params{rs_plot_type} eq 'xypoints') {

      #### Populate a data structure to plot
      @data = (
        $column_info->{A}->{data},
        $column_info->{B}->{data},
      );
      #### Create the histogram canvas
      $graph = GD::Graph::xypoints->new(640, 500);

      #### Set the various plot parameters
      $graph->set(
          x_label           => $column_info->{A}->{name},
          y_label           => $column_info->{B}->{name},
          title             => "Plot of ".$column_info->{B}->{name}." vs ".
                               $column_info->{A}->{name},
          long_ticks        => 0,
          marker_size       => 2,
          x_label_position  => 0.5,
      );

      #### Define result for later
      $result = { result=>'SUCCESS' } ;

    #### Else we don't know what to do with this one yet
    }


    #### Generate the plot and store to a file
    if (defined($result)) {
      my $gd = $graph->plot(\@data);
      open(IMG, ">$PHYSICAL_BASE_DIR/images/tmp/$tmpfile") or die $!;
      binmode IMG;
      print IMG $gd->png;
      close IMG;
    }


    #### Provide the link to the image
    my $imgsrcbuffer = '&nbsp;';
    $imgsrcbuffer = "<IMG SRC=\"$HTML_BASE_DIR/images/tmp/$tmpfile\">"
      if (defined($result));
    if ($self->output_mode() eq 'html') {
      print qq~
        <TR><TD COLSPAN="2">$imgsrcbuffer
        </TD></TR>
        <TD VALIGN="TOP" WIDTH="50%">
        <INPUT TYPE="hidden" NAME="rs_set_name" VALUE="$rs_params{set_name}">
        <TABLE>
        <TR><TD BGCOLOR="#E0E0E0">Plot Type</TD><TD>
        <SELECT NAME="rs_plot_type">
      ~;

    }

    my %plot_type_names = (
      'histogram'=>'Histogram of Column A',
      'xypoints'=>'Scatterplot B vs A',
    );

    foreach $element ('histogram','xypoints') {
      my $selected_flag = '';
      my $option_name = $plot_type_names{$element} || $element;
      $selected_flag = 'SELECTED'
	if (defined($rs_params{rs_plot_type}) &&
	    $element eq $rs_params{rs_plot_type});
      print "<option $selected_flag VALUE=\"$element\">$option_name\n";
    }

    print "</SELECT></TD></TR>";

    foreach my $column_index ( 'A','B' ) {
      print qq~
        <TR><TD BGCOLOR="#E0E0E0">Column $column_index</TD>
        <TD><SELECT NAME="rs_column$column_index">
      ~;

      #### Create a list box for selecting columnA
      $i=0;
      foreach $element (@{$column_titles_ref}) {
        my $selected_flag = '';
        $selected_flag = 'SELECTED'
          if (defined($rs_params{"rs_column$column_index"}) &&
	      $i == $rs_params{"rs_column$column_index"});
        print "<option $selected_flag VALUE=\"$i\">$element\n";
        $i++;
      }
      print "</SELECT></TD></TR>\n";
    }


    print qq~
      <TR><TD></TD><TD>
      <INPUT TYPE="submit" NAME="apply_action" VALUE="VIEWRESULTSET">
      </TD></TR></TABLE>
      </TD><TD>
      <TABLE>
    ~;


    foreach my $element (@{$result->{ordered_statistics}}) {
      print "<TR><TD BGCOLOR=#E0E0E0>$element</TD><TD>$result->{$element}</TD></TR>\n";
    }


    print qq~
      </TABLE>
      </TD></TR>
      </TABLE>
    ~;


    #### Finish the form
    if ($self->output_mode() eq 'html') {
      print qq~
        </FORM>
        </TABLE>
      ~;
    }


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


} # end displayResultSetPlot

#+
# Routine to cache url in database
# arg:     url to convert, required
# ret:     8 character url key
#-
sub setShortURL {
  my $self = shift;
  my $url = shift;
  $url = $self->convertSingletoTwoQuotes( $url );

  # Does this url already have a short_url?
  my  ( $url_key ) = $self->selectOneColumn( <<"  END" );
  SELECT url_key FROM $TB_SHORT_URL
  WHERE url LIKE '$url'
  END
  # return existing key
  return( $url_key ) if $url_key;

  # There should really be no duplicates, but just in case...
  for( my $i = 0; $i < 10; $i++ ) {
    $url_key = $self->getRandomString( num_chars => 8, 
                                       char_set  => [ 'a'..'z', 0..9 ] );

    my $dup = $self->selectOneColumn( <<"    END" );
    SELECT url_id FROM $TB_SHORT_URL
    WHERE url_key = '$url_key'
    END
    last unless $dup
  }
  $log->error( "No unique url_key in 10 attempts, investigate" ) unless $url_key;

  
# Insert URL into database
  my $uid = $self->updateOrInsertRow( insert => 1,
                                      update => 0,
                                      return_PK => 1,
                                      table_name => $TB_SHORT_URL,
                                      rowdata_ref => { URL     => $url,
                                                       URL_KEY => $url_key }
                                     );
# return key value
  return $url_key;
}


#+
# Routine to return pseudo-random string of characters
#
# narg: num_chars   Optional, length of character string, def = 8.
# narg: char_set    Optional, character set to use passed as array reference,
#                   def = ( 'A'-'Z', 'a'-'z', 0-9, !, @, #, $, %, ^, &, *, ? )
# ret:              Random string of specified length comprised of elements of 
#                   character set.
#-
sub getRandomString {
  my $self =  shift;
  my %args = @_;

  # Use passed number of chars or 8
  $args{num_chars} ||= 8;

  # Use passed char set if any, else use default a-z, A-Z, 0-9
  my @chars = ( ref( $args{char_set} ) eq 'ARRAY' ) ?  @{$args{char_set}} :
                         ( 'A'..'Z', 'a'..'z', 0..9, qw( ! @ $ % ^ & * ? ) );

  # Thank you perl cookbook... 
  my $rstring = join( "", @chars[ map {rand @chars} ( 1..$args{num_chars} ) ]);
  
  return( $rstring );

}
###############################################################################
# displayTimingInfo
#
# Display some statistics related to query times
###############################################################################
sub displayTimingInfo {
  my $self = shift;
  my %args = @_;

  #### Process the arguments list


  #### Determine the type of line break to use
  my $BR = "\n";
  if ($self->output_mode() eq 'html') {
    $BR = "<BR>\n";
  }


  if (defined($timing_info->{send_query}) &&
      defined($timing_info->{begin_resultset})) {
    printf("Query Time: %8.2f s$BR",tv_interval(
      $timing_info->{send_query},$timing_info->{begin_resultset}));
  }

  return;

  #### The following are almost always near 0 except for very large
  #### resultsets
  if (defined($timing_info->{begin_resultset}) &&
      defined($timing_info->{finished_resultset})) {
    printf("Fetch Resultset: %8.2f s$BR",tv_interval(
      $timing_info->{begin_resultset},$timing_info->{finished_resultset}));
  }

  if (defined($timing_info->{begin_write_resultset}) &&
      defined($timing_info->{finished_write_resultset})) {
    printf("Cache Resultset: %8.2f s$BR",tv_interval(
      $timing_info->{begin_write_resultset},
      $timing_info->{finished_write_resultset}));
  }

  return

} # end displayTimingInfo



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
  my @desired_params = ('rs_set_name','rs_page_size','rs_page_number',
    'rs_resort_column','rs_resort_type');


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
  unless (defined($rs_params{page_size}) && $rs_params{page_size} > 0) {
    $rs_params{page_size} = 50;
    $rs_params{default_values} = 'YES';
  }

  unless (defined($rs_params{page_number}) && $rs_params{page_number} > 0) {
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
    my $resultset_params_ref = $args{'resultset_params_ref'};
    my $column_titles_ref = $args{'column_titles_ref'};


    #### Update timing info
    $timing_info->{begin_resultset} = [gettimeofday()];


    #### Read in the query parameters
    my $infile = "$RESULTSET_DIR/${resultset_file}.params";
    open(INFILE,"$infile") || die "Cannot open $infile\n";
    my $indata = "";
    while (<INFILE>) { $indata .= $_; }
    close(INFILE);


    #### eval the dump
    my $VAR1;
    eval $indata;
    %{$query_parameters_ref} = %{$VAR1};

    #### If columns titles are there, extract them
    if (exists($query_parameters_ref->{'__column_titles'})) {
      @{$column_titles_ref} = @{$query_parameters_ref->{'__column_titles'}};
    }


    #### Read in the resultset
    $infile = "$RESULTSET_DIR/${resultset_file}.resultset";
    %{$resultset_ref} = %{retrieve($infile)};


    #### This also works but is quite slow
    #$indata = "";
    #open(INFILE,"$infile") || die "Cannot open $infile\n";
    #while (<INFILE>) { $indata .= $_; }
    #close(INFILE);
    #### eval the dump
    #eval $indata;
    #%{$resultset_ref} = %{$VAR1};


    #### Read in the various parameters from cached_resultset
    my $sql = qq~
      SELECT cached_resultset_id,resultset_name,date_created
        FROM $TB_CACHED_RESULTSET
       WHERE cache_descriptor = '$resultset_file'
    ~;
    my @row = $self->selectSeveralColumns($sql);

    if (scalar(@row)) {
      $resultset_params_ref->{cached_resultset_id} = $row[0]->[0];
      $resultset_params_ref->{resultset_name} = $row[0]->[1];
      $resultset_params_ref->{date_created} = $row[0]->[2];
    }

    #### Update timing info
    $timing_info->{finished_resultset} = [gettimeofday()];


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
    my $resultset_params_ref = $args{'resultset_params_ref'};
    my $file_prefix = $args{'file_prefix'} || 'query_';
    my $query_name = $args{'query_name'} || '';
    my $column_titles_ref = $args{'column_titles_ref'};


    #### If a filename was not provided, create one
    my $is_new_resultset = 0;
    if ($$resultset_file_ref eq "SETME") {
      $is_new_resultset = 1;
      my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
      my $timestr = strftime("%Y%m%d-%H%M%S",$sec,$min,$hour,$mday,$mon,$year);
      $$resultset_file_ref = $file_prefix . $self->getCurrent_username() .
        "_" . $timestr;
    }
    my $resultset_file = $$resultset_file_ref;


    #### Update timing info
    $timing_info->{begin_write_resultset} = [gettimeofday()];


    #### Prepare a special hash to work around a Dumper bug or feature
    my $temp_hash_ref;
    while ( my ($key,$value) = each %{$query_parameters_ref} ) {
      if ( substr($value,0,1) eq '%' ) {
        $temp_hash_ref->{$key} = '%'.$value;
      } else {
        $temp_hash_ref->{$key} = $value;
      }
    }
    #print "<PRE>cellcompconst=".
    #  $query_parameters_ref->{cellular_component_constraint}."=\n</PRE>";


    #### Add the column title list to the hash
    if (defined($column_titles_ref)) {
      $temp_hash_ref->{'__column_titles'} = $column_titles_ref;
    }


    #### Write out the query parameters
    my $outfile = "$RESULTSET_DIR/${resultset_file}.params";
    open(OUTFILE,">$outfile") || die "Cannot open $outfile\n";
    printf OUTFILE Data::Dumper->Dump( [$temp_hash_ref] );
    close(OUTFILE);



    #### Write out the resultset
    $outfile = "$RESULTSET_DIR/${resultset_file}.resultset";
    store($resultset_ref,$outfile);


    #### If this is a new resultset and we were provided a query_name,
    #### write a record for it in cached_resultset
    if ($is_new_resultset && $query_name) {
      my %rowdata = (
	contact_id=>$self->getCurrent_contact_id(),
        query_name=>$query_name,
        cache_descriptor=>$resultset_file,
      );
      my $cached_resultset_id = $self->updateOrInsertRow(
        insert=>1,
        table_name=>$TB_CACHED_RESULTSET,
        rowdata_ref=>\%rowdata,
        PK_name=>'cached_resultset_id',
        return_PK=>1,
        add_audit_parameters=>1,
      );

      #### Fill in some information about this resultset
      $resultset_params_ref->{cached_resultset_id} = $cached_resultset_id;
      $resultset_params_ref->{resultset_name} = '';
      my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
      my $timestr = strftime("%Y%m%d-%H%M%S",$sec,$min,$hour,$mday,$mon,$year);
      $resultset_params_ref->{date_created} = $timestr;

    }


    #### This also works but is dog slow
    #open(OUTFILE,">$outfile") || die "Cannot open $outfile\n";
    #$Data::Dumper::Indent = 0;
    #printf OUTFILE Data::Dumper->Dump( [$resultset_ref] );
    #close(OUTFILE);


    #### Update timing info
    $timing_info->{finished_write_resultset} = [gettimeofday()];


    return 1;


} # end writeResultSet


###############################################################################
# returnNextRow called by ShowTable
###############################################################################
sub returnNextRow {
  my $flag = shift @_;
  #print "Entering returnNextRow (flag = $flag)...<BR>\n";
  
  # had problems with undefined flag...
  $flag ||= 0;

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

    if ($self->output_mode() eq 'html') {
      print qq!
        <BR><HR SIZE=5 NOSHADE><BR>
        <FORM METHOD="post">
            <SELECT NAME="detail_level">
              <OPTION$basic_flag VALUE="BASIC">BASIC
              <OPTION$full_flag VALUE="FULL">FULL
            </SELECT>
        <B>WHERE</B><INPUT TYPE="text" NAME="where_clause"
                     VALUE="$where_clause" SIZE=25>
        <INPUT TYPE="hidden" NAME="TABLE_NAME" VALUE="$TABLE_NAME">
        <INPUT TYPE="submit" NAME="redisplay" VALUE="DISPLAY"><P>
      !;
    }

    #### Removed from form Deutsch 2002-11-20
    #<TD><IMG SRC="$HTML_BASE_DIR/images/space.gif" WIDTH="20" HEIGHT="1"></TD><TD COLSPAN=4>

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
# the command line or ...?) into the %parameters hash
###############################################################################
sub parse_input_parameters {
  my $self = shift;
  my %args = @_;


  #### Process the arguments list
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


  #### Resolve all the parameters from the command line if any
  my %cmdln_parameters;
  foreach $element (@ARGV) {
    if ( ($key,$value) = split("=",$element) ) {
      my $tmp = $value;
      $tmp = '' unless (defined($tmp));
      print "$key = '$tmp'<BR>\n";
      $cmdln_parameters{$key} = $value;
      $ref_parameters->{$key} = $value;
      $n_cmdln_params_found++;
    } else {
      print "ERROR: Unable to parse '$element'\n";
      return;
    }
  }


  #### Resolve all the parameters from the CGI interface if any
  my %CGI_parameters;
  foreach $element ($q->param()) {

    #### Extract as an array and remove any leading or trailing blank items
    my @tmparray = $q->param($element);
    if (scalar(@tmparray) > 1) {
      pop @tmparray unless ($tmparray[$#tmparray] gt '');
      shift @tmparray unless ($tmparray[0] gt '');
    }
    #### Convert to a comma separated list
    $value = join(",",@tmparray);

    #print "$element = '$value'<BR>\n";
    $CGI_parameters{$element} = $value;
    $ref_parameters->{$element} = $value;
    $n_CGI_params_found++;
  }


  #### Add a set of standard set of input options
  my @columns = @{$ref_columns};
  if ($add_standard_params eq 'YES') {
    push(@columns,'apply_action','action','output_mode','TABLE_NAME',
      'QUERY_NAME','navigation_bar');
  }


  #### Read the form values for each of the desired parameters
  foreach $element (@columns) {

    #### If a desired parameter was not found, perhaps we should set it to
    #### a blank?
    #my $value = $parameters_ref->{$element};
    #$parameters_ref->{$element} = ''
    #  unless (defined($value) && $value gt '');

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


  #### Due to ambiguity between action and apply_action, map the latter
  #print "Content-type: text/html\n\n";
  #print "action = ",$ref_parameters->{action},"<BR>\n";
  #print "apply_action = ",$ref_parameters->{apply_action},"<BR>\n";
  if (defined($ref_parameters->{apply_action}) &&
      $ref_parameters->{apply_action} gt '' &&
      (!defined($ref_parameters->{action}) || 
       !($ref_parameters->{action} gt ''))) {
    $ref_parameters->{action} = $ref_parameters->{apply_action};
  }


  return $n_params_found;

} # end parse_input_parameters



###############################################################################
# processStandardParameters
#
# Look for and process and standard input parameters that preset the state
# of the user before the request is handled
###############################################################################
sub processStandardParameters {
  my $self = shift;
  my %args = @_;


  #### Process the arguments list
  my $ref_parameters = $args{'parameters_ref'};


  #### Define some generic varibles
  my ($i,$element,$key,$value,$line,$result,$sql);

  #### If there's a parameter to set the current default project
  if (defined($ref_parameters->{set_current_project_id}) &&
      $ref_parameters->{set_current_project_id} gt '') {
    my $set_current_project_id = $ref_parameters->{set_current_project_id};
    if ($set_current_project_id > 0) {
      $self->setCurrent_project_id(
        set_to_project_id=>$set_current_project_id);
    }
  }

  if (defined($ref_parameters->{set_current_work_group}) &&
      $ref_parameters->{set_current_work_group}) {
    my $set_current_work_group = $ref_parameters->{set_current_work_group};
		$self->setCurrent_work_group(
      set_to_work_group=>"$set_current_work_group",
		  permitted_work_groups_ref=>" ",
			permanent=>1);
  }


} # end processStandardParameters



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
  my $allow_NOT_flags = $args{'allow_NOT_flags'};
  my $onSubmit = $args{onSubmit} || '';


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
    if (defined($optionlist_query) && $optionlist_query gt '') {
      #print "<font color=\"red\">$column_name</font><BR><PRE>$optionlist_query</PRE><BR>\n";
      $optionlist_queries{$column_name}=$optionlist_query;
    }
    if ($input_type eq "file") {
      $file_upload_flag = "ENCTYPE=\"multipart/form-data\"";
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
      <FORM METHOD="post" ACTION="$PROGRAM_FILE_NAME" NAME="MainForm" $file_upload_flag $onSubmit>
      <TABLE BORDER=0>
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
              s/\$contact_id/$current_contact_id/g;
        } else {
          $optionlist_queries{$element} =~
              s/\$contact_id/$parameters{contact_id}/g;
        }
      }


      # If "$accessible_project_ids" appears in the SQL optionlist query,
      # then substitute it with a call to that function
      if ( $optionlist_queries{$element} =~ /\$accessible_project_ids/ ) {
	my @accessible_project_ids = $self->getAccessibleProjects();
	my $accessible_project_id_list = join(',',@accessible_project_ids);
	$accessible_project_id_list = '-1'
          unless ($accessible_project_id_list gt '');
        $optionlist_queries{$element} =~
          s/\$accessible_project_ids/$accessible_project_id_list/g;
      }


      # If "$project_id" appears in the SQL optionlist query, then substitute
      # that with either a value of $parameters{project_id} if it is not
      # empty, or otherwise replace with the $current_project_id
      if ( $optionlist_queries{$element} =~ /\$project_id/ ) {
        if ( $parameters{"project_id"} eq "" ) {
          my $current_project_id = $self->getCurrent_project_id();
          $optionlist_queries{$element} =~
              s/\$project_id/$current_project_id/g;
        } else {
          $optionlist_queries{$element} =~
              s/\$project_id/$parameters{project_id}/g;
        }
      }


      # If "$parameters{xxx}" appears in the SQL optionlist query,
      # then substitute that with either a value of $parameters{xxx}
      while ( $optionlist_queries{$element} =~ /\$parameters\{(\w+)\}/ ) {
        my $tmp = $parameters{$1};
        if (defined($tmp) && $tmp gt '') {
	  unless ($tmp =~ /^[\d,]+$/) {
	    my @tmp = split(',',$tmp);
	    $tmp = '';
	    foreach my $tmp_element (@tmp) {
	      $tmp .= "'$tmp_element',";
	    }
	    chop($tmp);
	  }
	} else {
          $tmp = "''";
	}

        $optionlist_queries{$element} =~
          s/\$parameters{$1}/$tmp/g;
      }


      #### Evaluate the $TBxxxxx table name variables if in the query
      if ( $optionlist_queries{$element} =~ /\$TB/ ) {
        my $tmp = $optionlist_queries{$element};
        
        #### If there are any double quotes, need to escape them first
        $tmp =~ s/\"/\\\"/g;
         $optionlist_queries{$element} = $self->evalSQL($tmp);
     #   $optionlist_queries{$element} = main::evalSQL($tmp);
	unless ($optionlist_queries{$element}) {
	  print "<font color=\"red\">ERROR: SQL for field '$element' fails to resolve embedded \$TB table name variable(s)</font><BR><PRE>$tmp</PRE><BR>\n";
      
      
	}

      }


      #### Set the MULTIOPTIONLIST flag if this is a multi-select list
      my $method_options;
      $method_options = "MULTIOPTIONLIST"
        if ($input_types{$element} eq "multioptionlist");

      # Build the option list
      #print "<font color=\"red\">$element</font><BR><PRE>$optionlist_queries{$element}</PRE><BR>\n";
      $optionlists{$element}=$self->buildOptionList(
         $optionlist_queries{$element},$parameters{$element},$method_options);

      #### If the user sent some invalid options, reset the list to the
      #### valid list.  This is a hack because buildOptionList() API is poor
      if ($optionlists{$element} =~ /\<\!\-\-(.*)\-\-\>/) {
	$parameters_ref->{$element} = $1;
      }

  }

  # Add CSS and javascript for popup column_text info (if configured).
  print $self->getPopupDHTML();

  #### Now loop through again and write the HTML
  foreach $row (@columns_data) {
    my @row = @{$row};
    my ($column_name,$column_title,$is_required,$input_type,$input_length,
        $is_data_column,$is_display_column,$column_text,
        $optionlist_query,$onChange) = @row;
    $onChange = '' unless (defined($onChange));


    #### Set the JavaScript onChange string if supplied
    if ($onChange gt '') {
      $onChange = " onChange=\"$onChange\"";
    }


    #### Set the NOT_clause if allowed
    my $NOT_clause = '';
    if ($allow_NOT_flags) {
      my $NOT_flag = '';
      $NOT_flag = 'CHECKED' if ($parameters{"NOT_$column_name"} eq 'NOT');
      $NOT_clause = qq~NOT<INPUT TYPE="checkbox" NAME="NOT_$column_name"
         VALUE="NOT" $NOT_flag>~;
    }


    #### If the action included the phrase HIDE, don't print all the options
    if ( defined $apply_action && $apply_action =~ /HIDE/i) {
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
                     && $is_display_column eq '2') ||
           $is_display_column eq 'N'
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


    # FIXME 'static conditional' for image link column text
    # Should/could be replaced by a user-configuration option
    use constant LINKHELP => 1; 
    if ( LINKHELP ) {
      $column_text = linkToColumnText( $column_text, $column_name, $TABLE_NAME );
    }


    #### Write the parameter name, in red if required
    if ($is_required eq "N") {
      print qq!
        <TR><TD><B>$column_title:</B></TD>
            <TD BGCOLOR="E0E0E0">$column_text</TD>
              !;
    } else {
      print qq!
        <TR><TD><B><font color=red>$column_title:</font></B></TD>
            <TD BGCOLOR="E0E0E0">$column_text</TD>
              !;
    }


    if ($input_type eq "text") {
      print qq!
        <TD>$NOT_clause<INPUT TYPE="$input_type" NAME="$column_name"
         VALUE="$parameters{$column_name}" SIZE=$input_length $onChange></TD>
      !;
    }

    if ($input_type eq "file") {
      print qq!
        <TD><INPUT TYPE="$input_type" NAME="$column_name"
         VALUE="$parameters{$column_name}" SIZE=$input_length $onChange>!;
      if ($parameters{$column_name}) {
        print qq!<A HREF="$DATA_DIR/$parameters{$column_name}">[view&nbsp;file]</A>
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
      print qq~
        <TD COLSPAN=2><TEXTAREA NAME="$column_name" rows=$input_length
          cols=80>$parameters{$column_name}</TEXTAREA></TD>
      ~;
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
        <TD>$NOT_clause<SELECT NAME="$column_name" MULTIPLE SIZE=$input_length $onChange>
        $optionlists{$column_name}
        <OPTION VALUE=""></OPTION>
        </SELECT></TD>
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


    print "</TR>\n";

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

  my $pad = '&nbsp;' x 6;

  #### Show the QUERY, REFRESH, and Reset buttons
  print qq~
      <INPUT TYPE="hidden" NAME="set_current_work_group" VALUE="">
      <INPUT TYPE="hidden" NAME="set_current_project_id" VALUE="">
      <INPUT TYPE="hidden" NAME="QUERY_NAME" VALUE="$TABLE_NAME">
      <INPUT TYPE="hidden" NAME="apply_action_hidden" VALUE="">
      <TR><TD COLSPAN=3>
      $pad <INPUT TYPE="submit" NAME="action" VALUE="QUERY">
      $pad <INPUT TYPE="submit" NAME="action" VALUE="REFRESH">
      $pad <INPUT TYPE="reset"  VALUE="Reset">
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
           $element->[1] AS "$element->[0]"~;
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

  my $source_array_ref = $args{'source_array_ref'};

  my $source_file = $args{'source_file'};
  my $delimiter = $args{'delimiter'} || "\t";
  my $comment_char = $args{'comment_char'};
  my $skip_lines = $args{'skip_lines'} || 0;

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
  my $dest_PK_name = $args{'dest_PK_name'} || $args{'dest_PK'} || '';

  my $update = $args{'update'} || 0;

  my $update_keys_ref = $args{'update_keys_ref'};

  my $verbose = $args{'verbose'} || 0;
  my $testonly = $args{'testonly'} || 0;
  my $add_audit_parameters = $args{'add_audit_parameters'} || 0;


  #### Verify that we only go one input source
  my $n_defined_sources = 0;
  foreach my $test_parameter ($sql,$source_array_ref,$source_file) {
    $n_defined_sources += (defined($test_parameter) and $test_parameter gt '');
  }
  unless ($n_defined_sources == 1) {
    die ("Exactly one of sql, source_file, source_array_ref must be passed");
  }


  #### Define standard variables
  my ($i,$element,$key,$value,$line,$result);
  my @rows;


  #### Get data from source
  #### Execute source query if sql is set
  if ($sql) {
    print "\n  Getting data from source...";
    @rows = $src_conn->selectSeveralColumns($sql);
  }


  #### Read from file if source_file is set
  if ($source_file) {
    print "\n  Loading data from file...";
    @rows = $self->importTSVFile(source_file=>$source_file,
      delimiter=>$delimiter,
      skip_lines=>$skip_lines,
      comment_char=>$comment_char);
  }


  #### Use the $source_array_ref if it is set
  if ($source_array_ref) {
    @rows = @{$source_array_ref};
  }


  #### Define some stuff
  my %rowdata;
  my $row;
  
  my $line_br = '';
  if ($self->output_mode() eq 'html') {
  	$line_br = '<br>';
  }else{
  	$line_br = "\n";
  } 
  
  my $total_row_count = scalar @rows;		#setup counter to watch the inserts or updates proceed
  my $number_inserts_per_dot = int($total_row_count/100);
  my $load_info = "v-- 0 %".  (" " x 23) . "Number of inserts per dot = " . (sprintf("% 4d", $number_inserts_per_dot)) . (" " x 24) . "100 % done --v $line_br";
  my $load_gauge = "|" . ("." x 98) . "|$line_br";
  my $row_count = 0;
    
  #### Loop over each row of input data
  print "$line_br  Loading data into destination$line_br";
  print "$load_info$load_gauge" if $total_row_count > 100;
  foreach $row (@rows) {
    %rowdata = ();

    while ( ($key,$value) = each %{$column_map_ref} ) {
      #### See if we have a scalar, turn it into an array
      my @refs_for_one_column;
      my $ref_type = ref($value);
      if ($ref_type eq "ARRAY") {
	@refs_for_one_column = @{$value};
      }else {
	#### treat as scalar by default
	push @refs_for_one_column, $value;
      }
      
      #### Loop over all fields mapped to this column
      foreach $value (@refs_for_one_column) {
      
        if (defined($row->[$key]) || defined($transform_map_ref->{$key})) {

	  #### If there's a mapping for this column
	  if (defined($transform_map_ref->{$key})) {
	    my $current_value = $row->[$key];

	    #### Only in a special case, If the value is empty, then ignore it
	    #### FIXME
	    if (0) {
	      next unless ($current_value gt '');
	    }

	    #### Determine if we need to remap this column and if so, do it
	    my $map_ref = $transform_map_ref->{$key};
	    my $mapped_value;
	    #### If the mapping is a simple hash
	    if ($map_ref =~ /HASH/) {
	      $mapped_value = $map_ref->{$current_value};
	    } elsif ($map_ref =~ /CODE/) {
	      $mapped_value = &$map_ref($current_value);
	    } else {
	      print "Unknown mapping type ",$map_ref,"\n";
	    }

	    #### If the mapping produced a result
	    if (defined($mapped_value)) {
	      $rowdata{$value} = $mapped_value;
	      $row->[$key] = $mapped_value;
		
	      #### Else complain and leave as NULL
	    } else {
	      print "\nWARNING: Unable to transform column ".$key.
		  " having value '".$current_value."'\n";
	    }

	    #### Otherwise use as is
  	  } else {
	    $rowdata{$value} = $row->[$key];
  	  }

        } else {
	    #print "WARNING: Column $key undefined!\n";
	}
      }
    }


    #### If there's no data, squawk and move on
    unless (%rowdata) {
      print "\nWARNING: row contains no data.   Nothing to do.\n";
      next;
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
        my $contraint_value = $self->convertSingletoTwoQuotes($row->[$value]);
        #### If the constraint value is empty, allow either NULL or empty
        if ($contraint_value gt '') {
          push(@constraints,"$key = '$contraint_value'");
        } else {
          push(@constraints,"($key = '' OR $key IS NULL)");
	}
      }

      if (@constraints) {
        $constraints_str = join(" AND ",@constraints);
        $sql = qq~
          SELECT $dest_PK_name
            FROM $table_name
           WHERE $constraints_str
        ~;

        #print $sql;
        if ($verbose > 1) {
          print "Finding PK with: $sql";
        }
        my @results = $self->selectOneColumn($sql);
	
        #### If there is one matching record
        if (scalar(@results) == 1) {

          $result = $dest_conn->updateOrInsertRow(update=>1,
            table_name=>$table_name,
            rowdata_ref=>\%rowdata,
            PK=>$dest_PK_name,PK_value=>$results[0],
            return_PK=>$return_PK,
            verbose=>$verbose,
            testonly=>$testonly,
            add_audit_parameters=>$add_audit_parameters,
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

      $result = $dest_conn->updateOrInsertRow(insert=>1,
  	table_name=>$table_name,
  	rowdata_ref=>\%rowdata,
  	PK=>$dest_PK_name,return_PK=>$return_PK,
        verbose=>$verbose,
        testonly=>$testonly,
        add_audit_parameters=>$add_audit_parameters,
      );
    }

    if ( $row_count == $number_inserts_per_dot){			#change the print style of the dots.  Should print out 100 dots for the whole run
    	print "." ;
       $row_count = 0;
    }elsif ($total_row_count < 100){
    	print ".";
    }
    
    $row_count ++;

    if ($dest_PK_name && $result) {
      $newkey_map_ref->{$row->[$src_PK_column]} = $result;
      #print $row->[$src_PK_column],"=",$result," ";
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
    #### Perl rudely doesn't keep trailing empty columns, so this little
    #### hack adds a dummy column and then pops it off.  NASTY!
    $line .= "${delimiter}XXX";
    my @splitline = split(/$delimiter/,$line);
    pop(@splitline);

    #### Decode the enquoted values if any
    my $n_columns = @splitline;
    for ($i=0; $i<$n_columns; $i++) {
      if ($splitline[$i] =~ /^\"(.*)\"$/) {
        $splitline[$i] = $1;
        #### Then two double quotes in this context means a single one
        $splitline[$i] =~ s/\"\"/\"/g;
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


  #### Check to see whether this person is at the local facility
  #### If not, then restrict to groups to which they belong.
  #### This needs much better permissions control.  FIXME.
  my $current_contact_id = $self->getCurrent_contact_id();
  my $sql = qq ~
    SELECT is_at_local_facility
      FROM $TB_CONTACT
     WHERE contact_id = '$current_contact_id'
       AND record_status != 'D'
  ~;
  my (@rows) = $self->selectOneColumn($sql);

  #### If the user is not a local user, then restrict the modules
  if (scalar(@rows) != 1 || ( $rows[0] ne 'Y' && $self->getSite() eq 'ISB' ) ) {

    #### Get the groups that this user belongs to
    my $sql = qq ~
      SELECT WG.work_group_name,WG.work_group_id
        FROM $TB_WORK_GROUP WG
       INNER JOIN $TB_USER_WORK_GROUP UWG
             ON ( WG.work_group_id = UWG.work_group_id )
       WHERE UWG.contact_id = '$current_contact_id'
         AND WG.record_status != 'D'
         AND UWG.record_status != 'D'
    ~;
    my %work_groups = $self->selectTwoColumnHash($sql);

    #### Make a copy of all the modules and clear real @modules
    my @all_modules = ( @modules );
    @modules = ();

    #### Loop over all the modules, only keeping the ones for which the
    #### current user has access (i.e. belongs to one of the groups
    #### associated with the module)
    foreach my $module (@all_modules) {
#			print STDERR "$module\n";
      if (exists($work_groups{"${module}_user"}) ||
          exists($work_groups{"${module}_admin"}) ||
          exists($work_groups{"${module}_readonly"})) {
        push(@modules,$module);
      }
    }
    push(@modules,'Tools');

  }


  #### Return the resulting list of available modules
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
# printRecentResultsets- prints HTML TABLE of recent resultsets
###############################################################################
sub printRecentResultsets {
  my $self = shift || croak("parameter self not passed");
  my $html = $self->getRecentResultsets( @_ );
  print $html;
  }

sub getRecentResultsets {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;
  my $SUB_NAME = "getRecentResultsets";

  #### Decode the argument list
  my $verbose = $args{'verbose'} || 0;
  my $max_rows = $args{'max_rows'} || 5;


  #### Define standard variables
  my ($sql, @rows);
  my $current_contact_id = $self->getCurrent_contact_id();

  my $html;    # Content Accumulator

  #### Get information about the most recent resultsets
  $sql = qq~
    SELECT cached_resultset_id,resultset_name,query_name,cache_descriptor,
           date_created
      FROM $TB_CACHED_RESULTSET
     WHERE contact_id = '$current_contact_id'
       AND record_status != 'D'
       AND query_name LIKE '$SBEAMS_SUBDIR\%'
     ORDER BY date_created DESC
  ~;
  @rows = $self->selectSeveralColumns($sql);

  #### If there's something interesting to show, show a glimpse
  if (scalar(@rows)) {
    if ($SBEAMS_SUBDIR) {
      $html .= qq~
	<H1>Recent Query Resultsets within the $SBEAMS_SUBDIR Module:</H1>
	<TABLE BORDER=0>
      ~;
    } else {
      $html .= qq~
	<H1>Recent SBEAMS query resultsets:</H1>
	<TABLE BORDER=0>
      ~;
    }


    #### Find all the resultsets with names/annotations
    my $html_buffer = '';
    my $output_counter = 0;
    foreach my $row (@rows) {
      my $resultset_name = $row->[1];
      my $query_name = $row->[2];
      my $cache_descriptor = $row->[3];
      my $date_created = $row->[4];
      if (defined($resultset_name) && $output_counter < 5) {
        $html_buffer .= qq~
	  <TR><TD></TD><TD><IMG SRC="$HTML_BASE_DIR/images/space.gif" WIDTH="20" HEIGHT="1"></TD><TD NOWRAP>-&nbsp;<A HREF="$CGI_BASE_DIR/$query_name?action=VIEWRESULTSET&rs_set_name=$cache_descriptor">[View]</A>&nbsp;&nbsp;&nbsp;&nbsp;<font color="green">$resultset_name:</font></TD>
	  <TD NOWRAP>&nbsp;&nbsp;&nbsp;$query_name</A></TD>
	  <TD NOWRAP>&nbsp;&nbsp;&nbsp;($date_created)</TD></TR>
        ~;
        $output_counter++;
      }
    }

    #### If there were any, print them
    if ($output_counter) {
      $html .= qq~
	<TR><TD><IMG SRC="$HTML_BASE_DIR/images/space.gif" WIDTH="20" HEIGHT="1"></TD><TD COLSPAN=4>Most recent named resultsets:</TD></TR>
	$html_buffer
      ~;
    }


    #### Find all the resultsets without names/annotations
    $html_buffer = '';
    $output_counter = 0;
    foreach my $row (@rows) {
      my $resultset_name = $row->[1];
      my $query_name = $row->[2];
      my $cache_descriptor = $row->[3];
      my $date_created = $row->[4];
      if (!defined($resultset_name) && $output_counter < 5) {
        $html_buffer .= qq~
	  <TR><TD></TD><TD><IMG SRC="$HTML_BASE_DIR/images/space.gif" WIDTH="20" HEIGHT="1"></TD><TD NOWRAP>-&nbsp;<A HREF="$CGI_BASE_DIR/$query_name?action=VIEWRESULTSET&rs_set_name=$cache_descriptor">[View]</A>&nbsp;&nbsp;&nbsp;&nbsp;<font color="green">(unnamed)</font></TD>
	  <TD NOWRAP>&nbsp;&nbsp;&nbsp;$query_name</TD>
	  <TD NOWRAP>&nbsp;&nbsp;&nbsp;($date_created)</A></TD></TR>
        ~;
        $output_counter++;
      }
    }


    #### If there were any, print them
    if ($output_counter) {
      $html .= qq~
	<TR><TD><IMG SRC="$HTML_BASE_DIR/images/space.gif" WIDTH="20" HEIGHT="1"></TD><TD COLSPAN=4>Most recent unnamed resultsets:</TD></TR>
	$html_buffer
      ~;
    }

    $html .= qq~
      <TR><TD></TD><TD COLSPAN=4><A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=cached_resultset">[View all resultsets]</A></TD></TR>
      </TABLE>
    ~;

  }

  return $html || $self->makeInfoText( '&nbsp;&nbsp; No resultsets available' );

} #end printRecentResultsets

#+
# GetDataFromModules
#
# named arg projects required arrayref of project_ids
# named arg modules required arrayref of module names
# returns hashref keyed by project_id to hashref of module->link information.
sub getDataFromModules {
  my $this = shift;
  my %args = @_;
  for ( qw( projects modules ) ) {
    unless( $args{$_} ) {
      $log->warn( "Missing or empty parameter $_" );
      return undef;
    }
  }
  my $subdir = $this->getSBEAMS_SUBDIR();
  
  # Prune list of modules to the ones we know support this functionality 
  my @supp = qw( Microarray Proteomics ProteinStructure Immunostain 
                 Cytometry Interactions Inkjet PeptideAtlas );

  my @valid_mods;
  for my $mod ( @{$args{modules}} ) {
    $mod = ucfirst( $mod );
    push @valid_mods, $mod if grep /$mod/, @supp;
  }

  my %sbeams;
  
  # Loop through remaining modules, instantiate those
  # that we can
  my $mod_index = $#valid_mods;

  # Note: hash is reversed so that we can splice out entries by index 
  for my $mod ( reverse(@valid_mods) ) {
    my $class = 'SBEAMS::' . $mod;
    eval "require $class";
    if ( $@ ) { # We got an eval error
      $log->warn( $@ );
      splice( @valid_mods, $mod_index, 1 );
    } else {
      $sbeams{$mod} = eval "$class->new()"; 
    }
    $mod_index--;
  }
  # Reset the subdir to cached value.
  $this->setSBEAMS_SUBDIR( $subdir );
  

  my %mod_data;
# Commented out Benchmark code, but left for testing in case of performance
# issues.
#  use Benchmark;
#  my $t0 = new Benchmark;

  # loop through sbeams objects, 
  for my $mod ( @valid_mods ) {
    next unless $sbeams{$mod};
    $sbeams{$mod}->setSBEAMS($this) || die "Doh";
    $mod_data{$mod} = $sbeams{$mod}->getProjectData( projects => $args{projects} );
#    my $t1 = new Benchmark;
#    $log->debug( "Fetch of data (" . scalar( @{$args{projects}} ) . " projects) from $mod took " . timestr(timediff( $t1, $t0 )) );
#    $t0 = $t1;

  }

  # Return reference to data structure
  return ( \@valid_mods, \%mod_data );

  
}

###############################################################################
# printProjectsYouOwn- prints HTML TABLE that contains all projects you own
###############################################################################
sub printProjectsYouOwn {
  my $self = shift || croak("parameter self not passed");
  print $self->getProjectsYouOwn( @_ );
}

  
sub getProjectsYouOwn {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;
  my $SUB_NAME = "getProjectsYouOwn";

  #### Decode the argument list
  my $verbose = $args{'verbose'} || 0;
  my $current_contact_id = $self->getCurrent_contact_id();
  
  #### Get all the projects owned by the user
  my $sql =<<"  END_SQL";
	SELECT project_id,project_tag,P.name, P.description
	  FROM $TB_PROJECT P
	 WHERE PI_contact_id = '$current_contact_id'
	   AND record_status != 'D'
	 ORDER BY name ASC
  END_SQL
  
  my @rows = $self->selectSeveralColumns($sql);
  my @projects;
  for my $row ( @rows ) {
    push @projects, $row->[0];
  }

  # From this point on, need to know if we're fetching module data
  # Default is to show data from all modules
  my $getmods = 1;
  my @modules;

  if ( $args{mod_data} ) {
    if ( ref( $args{mod_data} ) eq 'ARRAY' ) {
      @modules = @{$args{mod_data}};
    } elsif ( $args{mod_data} eq 'None' ) {
      $getmods = 0;
    } else {
      @modules = $self->getModules();
    }
  } else {
    @modules = $self->getModules();
  }

  my $modules = [];
  my $mdata = {};

  if ( $getmods ) {
    ( $modules, $mdata ) = $self->getDataFromModules( projects => \@projects,
                                                      modules => \@modules );
  }
  my $mod_data_css = '';

  my @mods_with_data = @$modules;
  my %project_mod_data; # Holds data for each project
  my %project_mod_count; # Holds max number of mods with data for any projectID
  # For each module that has some data, add CSS link and set project_mod value
  for my $mod ( @mods_with_data ) {
    $mod_data_css .= $self->getModuleButton( $mod );
    for my $proj ( keys(%{$mdata->{$mod}}) ) {
      $project_mod_data{$proj} ||= [];
      push @{$project_mod_data{$proj}}, $mdata->{$mod}->{$proj};
      $project_mod_count{$proj}++;
    }
  }

  # Calculate the highest number of modules that any one project has data in.
  my $max_mods = getMax( values( %project_mod_count ) );

  # Really only matters if that number is > 1.
  my $extra_mods = $max_mods - 1;

  # Create table for data display 
  my $ptable = SBEAMS::Connection::DataTable->new(BORDER => 0 , WIDTH => '40%');

  my @headings = qw( ID Name Description );

  if ( $getmods ) {
    my $pad = '&nbsp;' x (20 * ( $max_mods - 1) );
    push @headings, "Available Data $pad";
  }

  $ptable->addRow( \@headings );
  $ptable->setHeaderAttr( BOLD => 1, UNDERLINE => 1 );

  my $num_data_mods = scalar(@mods_with_data); 

  my $numcols = 3 + $num_data_mods;
  $ptable->setColAttr( COLS => [4], ROWS => [1],
                       COLSPAN => $max_mods ) if $getmods && $extra_mods;

  $ptable->addRow( ['None'] ) unless scalar( @rows );

  foreach my $row ( @rows ) {
    $row->[3] =~ s/\s+/ /gm;  # Condense multi-line descriptions
    my $trunc = substr( $row->[3], 0, 40 );
    my $changed = ( $trunc eq $row->[3] ) ? 0 : 1;
    $trunc .= '...' if $changed;

    $row->[3] = "<SPAN TITLE='$row->[3]'> $trunc </SPAN>";
    $row->[2] =<<"    END_LINK";
    <SPAN TITLE='Switch to the $row->[2] ($row->[1]) project' class=popup>
    <A HREF=main.cgi?set_current_project_id=$row->[0] >$row->[2]
    </A></SPAN>
    END_LINK
    my @display_row = ( "$row->[0] &nbsp;", $row->[2], $row->[3] );
    push @display_row, @{$project_mod_data{$row->[0]}} if $getmods && $project_mod_data{$row->[0]};
    
    $ptable->addRow( \@display_row );
  }
  $ptable->setColAttr( COLS => [1..$numcols], ROWS => [ 1.. $ptable->getRowNum() ], 
                       NOWRAP => 1, NOBR => 1, VALIGN => 'CENTER' );

  my $addLink = 'Add a new project';
  if ( $self->isTableWritable( table_name => 'project' ) ) {
    $addLink =<<"    END";
    <BR>
        [<A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=project&ShowEntryForm=1">
          $addLink
        </A>]
    END
  } else {
    $addLink = $self->makeInactiveText( $addLink );
  }

  my $popup_css =<<"  END";
  <STYLE TYPE=text/css>
  .popup
  {
  COLOR: #9F141A;
  CURSOR: help;
  TEXT-DECORATION: none
  }
  </STYLE>
  END

  #### Finish the table
  return( <<"  END_HTML" );
  $popup_css
  $mod_data_css
  <H1>Projects you own:</H1>
  $ptable
  $addLink
  END_HTML

} #end printProjectsYouOwn

sub getMax {
  my @sorted = sort { $b <=> $a } @_;
  return $sorted[0];
}


###############################################################################
# printProjectsYouHaveAccessTo
###############################################################################
sub printProjectsYouHaveAccessTo {
  my $self = shift || croak("parameter self not passed");
  print $self->getProjectsYouHaveAccessTo( @_ );
}

#sub getAccessibleProjectInfo {
sub getProjectsYouHaveAccessTo {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;
  my $SUB_NAME = "getAccessibleProjectInfo";
  my $current_contact_id = $self->getCurrent_contact_id();


  # Fetch the privilege level names and format them
  my %privileges = $self->selectTwoColumnHash(
    "SELECT privilege_id,name FROM $TB_PRIVILEGE WHERE record_status != 'D'"
  );
  $privileges{9999} = "<SPAN TITLE='Viewing info due to Admin workgroup'>&lt;undef&gt;</SPAN>";
  @privileges{keys(%privileges)} = map { "<FONT COLOR=RED>$_</FONT>" } values( %privileges );

  # Get list of accessible projects from approved sbeams routine.
  my @accessible = $self->getAccessibleProjects( privilege_level => DATA_READER );
  my $accessible_projects = join(',', @accessible) || 0;

  # Build SQL to fetch other data
  my $sql =<<"  END_SQL";
  SELECT P.project_id, P.project_tag, P.name, 'desc_placeholder',
         CASE WHEN UL.username IS NULL THEN C.first_name + '_' + C.last_name
              ELSE UL.username END AS username,
         MIN( CASE WHEN UWG.contact_id IS NULL THEN 9999
              ELSE GPP.privilege_id END ) AS "best_group_privilege_id",
         MIN( CASE WHEN P.PI_contact_id = $current_contact_id THEN 10
                   WHEN UPP.privilege_id IS NULL THEN 9999 
                   ELSE UPP.privilege_id END ) AS "best_user_privilege_id"
	  FROM $TB_PROJECT P JOIN $TB_CONTACT C ON ( P.PI_contact_id = C.contact_id )
	  LEFT JOIN $TB_USER_LOGIN UL ON ( P.PI_contact_id = UL.contact_id )
	  LEFT JOIN $TB_USER_PROJECT_PERMISSION UPP
	       ON ( P.project_id = UPP.project_id
	            AND UPP.contact_id='$current_contact_id' )
	  LEFT JOIN $TB_GROUP_PROJECT_PERMISSION GPP
	       ON ( P.project_id = GPP.project_id )
	  LEFT JOIN $TB_PRIVILEGE PRIV
	       ON ( GPP.privilege_id = PRIV.privilege_id )
	  LEFT JOIN $TB_USER_WORK_GROUP UWG
	       ON ( GPP.work_group_id = UWG.work_group_id
	            AND UWG.contact_id='$current_contact_id' )
	  LEFT JOIN $TB_WORK_GROUP WG
	       ON ( UWG.work_group_id = WG.work_group_id )
	 WHERE P.project_id IN ( $accessible_projects )
   GROUP BY P.project_id,P.project_tag,P.name, username, first_name,
            last_name
	 ORDER BY UL.username,P.name
  END_SQL

  my @rows = $self->selectSeveralColumns($sql);

  # Stupid MSSQL can't group by description, awww.  May go away if we don't use desc.
  my $descSQL =<<"  END";
  SELECT description, project_id FROM $TB_PROJECT 
  WHERE project_id IN ( $accessible_projects ) 
  END
  my @desc = $self->selectSeveralColumns( $descSQL );
  my %desc;
  foreach my $desc ( @desc ) {
    $desc{$desc->[1]} = $desc->[0];
  }
  
  # From this point on, need to know if we're fetching module data

  # Default is to show data from all modules
  my $getmods = 1;
  my @modules;

  if ( $args{mod_data} ) {
    if ( ref( $args{mod_data} ) eq 'ARRAY' ) {
      @modules = @{$args{mod_data}};
    } elsif ( $args{mod_data} eq 'None' ) {
      $getmods = 0;
    } else {
      @modules = $self->getModules();
    }
  } else {
    @modules = $self->getModules();
  }

  my $modules = [];
  my $mdata = {};

  if ( $getmods ) {
     ($modules, $mdata) = $self->getDataFromModules( projects => \@accessible, 
                                                     modules => \@modules );
  }
  my $mod_data_css = '';

  my @mods_with_data = @$modules;
  my %project_mod_data; # Holds data for each project
  my %project_mod_count; # Holds max number of mods with data for any projectID

  # For each module that has some data, add CSS link and set project_mod value
  for my $mod ( @mods_with_data ) {
    $mod_data_css .= $self->getModuleButton( $mod );
    for my $proj ( keys(%{$mdata->{$mod}}) ) {
      $project_mod_data{$proj} ||= [];
      push @{$project_mod_data{$proj}}, $mdata->{$mod}->{$proj};
      $project_mod_count{$proj}++;
    }
  }

  
  # Calculate the highest number of modules that any one project has data in.
  my $max_mods = getMax( values( %project_mod_count ) );

  # Really only matters if that number is > 1.
  my $extra_mods = $max_mods - 1;

#  my $num_data_mods = scalar(@mods_with_data); 
  my $numcols = 4 + $getmods;

  my $ptable = SBEAMS::Connection::DataTable->new(BORDER => 0, WIDTH => '40%');

  my @headings = qw( ID Owner Name Privilege );

  if ( $getmods ) {
    my $pad = '&nbsp;' x (20 * ( $max_mods - 1) );
    push @headings, "Available Data $pad";
  }

  $ptable->addRow( \@headings );
  $ptable->setHeaderAttr( BOLD => 1, UNDERLINE => 1 );
  $ptable->addRow( ['None'] ) unless scalar( @rows );

  $ptable->setColAttr( COLS => [5], ROWS => [1],
                       COLSPAN => $max_mods ) if $getmods && $extra_mods;

  # Now loop through and build table
  foreach my $row (@rows) {

    # Format descriptions
    $row->[3] = $desc{$row->[0]};
    $row->[3] =~ s/\s+/ /gm;
    my $trunc = substr( $row->[3], 0, 35 );
    $row->[3] = substr( $trunc, 0, 32 ) . '...' unless $trunc eq $row->[3];

    # Build link from project name
    $trunc = substr( $row->[2], 0, 30 );
    $trunc .= '...' unless $trunc eq $row->[2];

    $row->[2] =<<"    END_LINK";
    <SPAN TITLE='Switch to the $row->[2] ($row->[1]) project' class=popup>
    <A HREF=main.cgi?set_current_project_id=$row->[0] >$trunc
    </A></SPAN>
    END_LINK

    # Calculate the best permission
    my $priv = ( $row->[5] < $row->[6] ) ? $row->[5] : $row->[6];

    $project_mod_data{$row->[0]} ||= '';
    my @display_row = ("$row->[0] &nbsp;", @$row[4,2], "$privileges{$priv} &nbsp;" );
    if ( $getmods && $project_mod_data{$row->[0]} ) {
      push @display_row, @{$project_mod_data{$row->[0]}};
    }
    $ptable->addRow( \@display_row );
  }
  $ptable->setColAttr( COLS => [1..$numcols], ROWS => [ 1.. $ptable->getRowNum() ], 
                       NOWRAP => 1, VALIGN => 'CENTER' );

  my $addLink = 'Add a new project';
  if ( $self->isTableWritable( table_name => 'project' ) ) {
    $addLink =<<"    END";
    <BR>
        [<A HREF="$CGI_BASE_DIR/$SBEAMS_SUBDIR/ManageTable.cgi?TABLE_NAME=project&ShowEntryForm=1">
          $addLink
        </A>]
    END
  } else {
    $addLink = $self->makeInactiveText( $addLink );
  }

  my $popup_css =<<"  END";
  <STYLE TYPE=text/css>
  .fixwidth
  {
    font-family: Verdana, Courier, Arial, sans serif;
  }
  .popup
  {
  COLOR: #9F141A;
  CURSOR: help;
  TEXT-DECORATION: none
  }
  </STYLE>
  END

  #### Finish the table
  return( <<"  END_HTML" );
  <DIV id=fixwidth>
    <FONT type=Courier>
  $popup_css
  $mod_data_css
  <H1>Projects you can access:</H1>
  $ptable
  $addLink
    </FONT>
  </DIV>
  END_HTML

}

sub getProjectsYouHaveAccessTo_deprecated {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;
  my $SUB_NAME = "getProjectsYouHaveAccessTo";

  my $html;  # Content accumulator

  #### Decode the argument list
  my $verbose = $args{'verbose'} || 0;
  my $current_contact_id = $self->getCurrent_contact_id();

  #### Define standard variables
  my ($sql, @rows);

  ##########################################################################
  #### Print out all projects user has access to
  $html .= qq~
	<H1>Projects You Have Access To:</H1>
	<TABLE WIDTH="50%" BORDER=0>
	<TR><TD><IMG SRC="$HTML_BASE_DIR/images/space.gif" WIDTH="20" HEIGHT="1"></TD>
  ~;


  #### Get the privilege level names
  my %privilege_names = $self->selectTwoColumnHash(
    "SELECT privilege_id,name FROM $TB_PRIVILEGE WHERE record_status != 'D'"
  );
  $privilege_names{9999} = "<SPAN TITLE='Viewing info due to Admin workgroup'>&lt;undef&gt;</SPAN>";

  my @accessible = $self->getAccessibleProjects( privilege_level => DATA_READER );
  my $accessible_projects = join ',', @accessible;

  #### Get all the projects user has access to
  $sql = qq~
  SELECT P.project_id,P.project_tag,P.name,
         CASE WHEN UL.username IS NULL THEN C.first_name + '_' + C.last_name
              ELSE UL.username END AS username,
         MIN( CASE WHEN UWG.contact_id IS NULL THEN 9999
              ELSE GPP.privilege_id END ) AS "best_group_privilege_id",
         MIN( CASE WHEN P.PI_contact_id = $current_contact_id THEN 10
              ELSE UPP.privilege_id END ) AS "best_user_privilege_id"
	  FROM $TB_PROJECT P JOIN $TB_CONTACT C ON ( P.PI_contact_id = C.contact_id )
	  LEFT JOIN $TB_USER_LOGIN UL ON ( P.PI_contact_id = UL.contact_id )
	  LEFT JOIN $TB_USER_PROJECT_PERMISSION UPP
	       ON ( P.project_id = UPP.project_id
	            AND UPP.contact_id='$current_contact_id' )
	  LEFT JOIN $TB_GROUP_PROJECT_PERMISSION GPP
	       ON ( P.project_id = GPP.project_id )
	  LEFT JOIN $TB_PRIVILEGE PRIV
	       ON ( GPP.privilege_id = PRIV.privilege_id )
	  LEFT JOIN $TB_USER_WORK_GROUP UWG
	       ON ( GPP.work_group_id = UWG.work_group_id
	            AND UWG.contact_id='$current_contact_id' )
	  LEFT JOIN $TB_WORK_GROUP WG
	       ON ( UWG.work_group_id = WG.work_group_id )
	 WHERE P.project_id IN ( $accessible_projects )
   GROUP BY P.project_id,P.project_tag,P.name, username, first_name, last_name
	 ORDER BY UL.username,P.project_tag
  ~;
  @rows = $self->selectSeveralColumns($sql);

  if (@rows) {
    my $firstflag = 1;
    foreach my $row (@rows) {
      my ($project_id,$project_tag,$project_name,$username,
          $best_group_privilege_id,$best_user_privilege_id) =
        @{$row};
      $html .= "	<TR><TD></TD>" unless ($firstflag);

      #### Select the lowest permission and translate to a name
      $best_group_privilege_id = 9999
        unless (defined($best_group_privilege_id));
      $best_user_privilege_id = 9999
        unless (defined($best_user_privilege_id));
      my $best_privilege_id = $best_group_privilege_id;
      $best_privilege_id = $best_user_privilege_id if
        ($best_user_privilege_id < $best_privilege_id);
      my $privilege_name = $privilege_names{$best_privilege_id} || '???';

      my $proj_brief = substr( $project_name, 0, 30 );
      $proj_brief .= '...' unless $proj_brief eq $project_name;
      $html .=<<"      END";
      <TD><NOBR>- 
       <A HREF='$CGI_BASE_DIR/$SBEAMS_SUBDIR/main.cgi?set_current_project_id=$project_id'
        TITLE='$project_name'>
         $username - $project_tag:
       </A> $proj_brief</NOBR>
      </TD>
      <TD><font color=\"red\">$privilege_name</font>
      </TD></TR>
      END
      $firstflag=0;
    }
  } else {
    $html .= "	<TD WIDTH=\"100%\">NONE</TD></TR>\n";
  }


  #### Finish the table
  $html .= qq~
	</TABLE>
  ~;

  return $html;
}

###############################################################################
# printUserChooser
###############################################################################
sub printUserChooser {
  my $self = shift || croak("parameter self not passed");
  my %args = @_;

  #### Define standard variables
  my $style;
  my ($work_group_sql, $project_sql, @rows);
  my ($work_group_chooser, $project_chooser);


  #### If the output mode is interactive text, switch to text mode
  if ($self->output_mode() eq 'interactive') {
    $style = 'TEXT';

  #### If the output mode is html, then switch to html mode
  }elsif ($self->output_mode() eq 'html') {
    $style = 'HTML';

  #### Otherwise, we're in some data mode and don't want to see this
  }else {
    return;
  }

  #### Find sub directory
  my $subdir = $self->getSBEAMS_SUBDIR();
  $subdir .= "/" if ($subdir);

  #### Get all relevant user information
  my $current_username = $self->getCurrent_username;
  my $current_contact_id = $self->getCurrent_contact_id;
  my $current_work_group_id = $self->getCurrent_work_group_id;
  my $current_work_group_name = $self->getCurrent_work_group_name;
  my $current_project_id = $self->getCurrent_project_id;
  my $current_project_name = $self->getCurrent_project_name;
  my $current_user_context_id = $self->getCurrent_user_context_id;


  #### The guest user should never be presented with this
  if ($current_username eq 'guest') {
    return;
  }


  #### Find out the current URI
  my $submit_string = $ENV{'SCRIPT_URI'."?"} || '';

  #### If we're in HTML mode, print javascript
  if ($style eq "HTML") {
    print qq~

<SCRIPT LANGUAGE="Javascript">
function switchWorkGroup(){
  var chooser = document.userChooser.workGroupChooser;
  var val = chooser.options[chooser.selectedIndex].value;
  if (document.MainForm == null) {
    document.groupChooser.set_current_work_group.value = val;
    document.groupChooser.submit();
  }else {
    document.MainForm.set_current_work_group.value = val;
    if (document.MainForm.apply_action_hidden != null){
      document.MainForm.apply_action_hidden.value = "REFRESH";
    }
    if (document.MainForm.action != null) {
      document.MainForm.action.value = "REFRESH";
    }
    if (document.MainForm.insert_with_template != null) {
      document.MainForm.insert_with_template.value = 0;
    }

    document.MainForm.submit();
  }
}

function switchProject(){
  var chooser = document.userChooser.projectIDChooser;
  var val = chooser.options[chooser.selectedIndex].value;
  if (document.MainForm == null) {
    document.projectChooser.set_current_project_id.value = val;
    document.projectChooser.submit();
  }else {
    document.MainForm.set_current_project_id.value = val;
    if (document.MainForm.apply_action_hidden != null){
      document.MainForm.apply_action_hidden.value = "REFRESH";
    }
    if (document.MainForm.action != null) {
      document.MainForm.action.value = "REFRESH";
    }
    if (document.MainForm.insert_with_template != null) {
      document.MainForm.insert_with_template.value = 0;
    }
    document.MainForm.submit();
  }
}

</SCRIPT>
~;
}
#### Begin Table
  print qq~
  <TABLE>
  <TR>
    <TD>
~;


#### Get work groups and make <SELECT> if we're HTML mode 
  $work_group_sql = qq~
      SELECT WG.work_group_id,WG.work_group_name
      FROM $TB_WORK_GROUP WG
      INNER JOIN $TB_USER_WORK_GROUP UWG ON ( WG.work_group_id=UWG.work_group_id ) 
      WHERE contact_id = '$current_contact_id'
        AND WG.record_status != 'D'
        AND UWG.record_status != 'D'
      ORDER BY WG.work_group_name
      ~;
  @rows = $self->selectSeveralColumns($work_group_sql);

  if ($style eq "HTML") {
    $work_group_chooser = qq~
<SELECT NAME="workGroupChooser" onChange="switchWorkGroup()">
  ~;

    foreach my $row_ref (@rows) {
      my ($work_group_id, $work_group_name) = @{$row_ref};
      if ($work_group_id == $current_work_group_id){
	$work_group_chooser .= qq~
<OPTION SELECTED VALUE="$work_group_name">$work_group_name
        ~;
      }else {
	$work_group_chooser .= qq~
<OPTION VALUE="$work_group_name">$work_group_name
        ~;
      }
    }

    $work_group_chooser .= qq~
</SELECT>
    ~;
  }

  #### Get accessible projects and make <SELECT> if we're in HTML mode
  my $module = $self->getSBEAMS_SUBDIR();
  $module =~ tr/A-Z/a-z/;
  my @project_ids = $self->getAccessibleProjects(module=>"$module");
  my $project_ids_list = join(',',@project_ids) || '-1';
  $project_sql = qq~
    SELECT P.project_id, UL.username+' - '+P.name
      FROM $TB_PROJECT P 
      LEFT JOIN $TB_USER_LOGIN UL ON ( P.PI_contact_id = UL.contact_id )
     WHERE P.project_id IN ( $project_ids_list )
       AND P.record_status != 'D'
       AND UL.record_status != 'D'
     GROUP BY P.project_id, P.name, UL.username
     ORDER BY UL.username, P.name
  ~;

  @rows = $self->selectSeveralColumns($project_sql);
  if ($style eq "HTML") {
    $project_chooser = qq~
<SELECT NAME="projectIDChooser" onChange="switchProject()">
    ~;

    foreach my $row_ref (@rows) {
      my ($project_id, $project_name) = @{$row_ref};
      if ($project_id == $current_project_id) {
	$project_chooser .= qq~
<OPTION SELECTED VALUE="$project_id">$project_name ($project_id)
        ~;
      }else {
	$project_chooser .= qq~
<OPTION VALUE="$project_id">$project_name ($project_id)
        ~;
      }
    }

    $project_chooser .= qq~
</SELECT>
    ~;
  }
	
  my $temp_current_work_group_name = $current_work_group_name;
  if ($current_work_group_name eq "Admin") {
    $temp_current_work_group_name = "<FONT COLOR=red><BLINK>$current_work_group_name</BLINK></FONT>";
  }
  
  #### PRINT HTML ####
  if ($style eq "HTML") {
    print qq~

<FORM NAME="userChooser">
<TABLE WIDTH="100%"  CELLPADDING="0">
<TR>
  <TD NOWRAP>
  <IMG SRC="$HTML_BASE_DIR/images/bullet.gif">Login:&nbsp;&nbsp;<B>$current_username</B> ($current_contact_id)&nbsp;&nbsp;&nbsp;&nbsp;Group:&nbsp;&nbsp;$work_group_chooser
  </TD>
</TR>

<TR>
  <TD NOWRAP>
  <IMG SRC="$HTML_BASE_DIR/images/bullet.gif">Project:$project_chooser
  </TD>
</TR>
</TABLE>
</FORM>
~;

    #### FORM FOR PROJECT CHANGE
    print qq~
<FORM NAME="projectChooser" METHOD="GET" ACTION="$submit_string">
    ~;


    ## PRINT CGI parameters
    my $project_query_string = $ENV{'QUERY_STRING'};
    my @query_parameters = split  /&/, $project_query_string;
    foreach my $temp_param (@query_parameters) {
      $temp_param =~ /(.*)\=(.*)/;
      unless ($1 eq "set_current_project_id" || $1 eq "set_current_work_group"){
	print qq~
<INPUT TYPE="hidden" NAME="$1" VALUE="$2">
          ~;
      }
    }
    print qq~
<INPUT TYPE="hidden" NAME="set_current_project_id">
</FORM>
    ~;

    #### FORM FOR WORK GROUP CHANGE
    print qq~
<FORM NAME="groupChooser" METHOD="GET" ACTION="$submit_string">
    ~;
    ## PRINT CGI parameters
    my $group_query_string = $ENV{'QUERY_STRING'};
    @query_parameters = split  /&/, $group_query_string;
    foreach my $temp_param (@query_parameters) {
      $temp_param =~ /(.*)\=(.*)/;
      unless ($1 eq "set_current_project_id" || $1 eq "set_current_work_group"){
	print qq~
<INPUT TYPE="hidden" NAME="$1" VALUE="$2">
	  ~;
      }
    }
    print qq~
<INPUT TYPE="hidden" NAME="set_current_work_group">
</FORM>
    ~;

    #### End First TD of master TABLE, and begin new TD
    print qq~
</TD>
<TD>
   ~;
    
    ## Suggestion Form
    #print qq~
    #<FORM NAME="suggestionBox" TARGET="_blank" METHOD="POST" ACTION="$HTML_BASE_DIR/cgi/suggestionBox.cgi">
    #<INPUT TYPE="hidden" NAME="action" VALUE="printSuggestionBox">
    #<INPUT TYPE="hidden" NAME="suggestionURL" VALUE="$ENV{'HTTP_REFERER'}">
    #<A HREF="Javascript:document.suggestionBox.submit()"><IMG SRC="$HTML_BASE_DIR/images/sug.jpg" WIDTH="80"></A>
    #</FORM>
    #~;

    #### END master TABLE
    print qq~
</TD>
</TR>
</TABLE>
    ~;								
}

  #### PRINT TEXT ####
  if ($style eq "TEXT") {
    print qq!Current Login: $current_username ($current_contact_id)  Current Group: $current_work_group_name ($current_work_group_id)
	Current Project: $current_project_name ($current_project_id)
	!;
  }
}

###############################################################################
# linkToColumnText: Creates link to popup window with column info text inside
#
# arg column text for display in popup window
# arg column name
# arg table name
# 
###############################################################################
sub linkToColumnText {
  my $text = shift;
  my $col = shift;
  my $tab = shift;
  $text = $q->escapeHTML( $text );
  my $url = "'$HTML_BASE_DIR/cgi/help_popup.cgi?column_name=$col&table_name=$tab'";
  my $link =<<"  END_LINK";
  <SPAN title="$text" class="popup">
  <IMG SRC=$HTML_BASE_DIR/images/greyqmark.gif BORDER=0 ONCLICK="popitup($url);"></SPAN>
  END_LINK
  return $link;
} # End linkToColumnText

###############################################################################
# getPopupDHTML: returns CSS and javascript for popups
#
# returns CSS/javascript in a scalar
# 
###############################################################################
sub getPopupDHTML {
  my $this = shift;
  my %args = ( height => 400, 
               width => 300,
               @_ );

  # add CSS class for popup menu
  my $dhtml =<<"  END_CLASS";
  <STYLE>
  .popup
  {
  COLOR: #9F141A;
  CURSOR: help;
  TEXT-DECORATION: none
  }
  </STYLE>
  END_CLASS

  # add javascript function for popup details
  $dhtml .=<<"  END_JS";
  <SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript">
  <!--
  function popitup(url)
  {
    newwindow=window.open( url ,'helpwin','height=$args{height},width=$args{width},dependent=yes,screenX=5000,screenY=50,scrollbars=yes,resizable=yes');
    if (window.focus) {newwindow.focus()}
    return false;
  }
  // -->
  </SCRIPT>
  END_JS
  return $dhtml;
  } # end getPopupDHTML

#+
# isTaintedSQL
# Checks for db altering keywords in SQL (which presumably shouldn't have one)
#-
sub isTaintedSQL {
  my $self = shift;
  my $sql = shift;

# Can't check vapor
  return undef if !$sql;

  if ( $sql =~ /CREATE|TRUNCATE|DELETE|ALTER|DROP|INSERT|UPDATE|GRANT/i ) {
    return 1;
  }
  return 0;
}


###############################################################################
# addProjectComment
###############################################################################
#sub editAdditionalInformation {
#		my $self = shift || croak("parameter self not passed");
#    my %args = @_;

		#### Define standard variables
#		my $current_project = $self->getCurrent_project_id();
#		my $module = $args{'module'}
#		|| croak("no module specified");
#		my $tag = $args{'tag'}
#		|| croak("no tag specifies");
#		my $text = $args{'text'}
#		|| croak("no text provided");
#		my $update = $args{'update'} || 1;
#		my $remove = $args{'remove'} || 0;
#		my ($sql, @rows, $additional_information);
#		my ($module_information, $tag_information);

		#### Make sure we are only inserting OR updating OR removing
#		unless (($update+$remove) == 1){
#				croak ("can do only one of the following:insert,update,remove");
#		}

		#### Get project additional information from database
#		$sql = qq~
#				SELECT P.additional_information
#				FROM $TB_PROJECT P
#				WHERE P.project_id = $current_project
#				AND P.record_status != 'D'
#				~;
#		@rows = $self->selectOneColumn($sql);
#		$additional_information = $rows[0];

		#### Extract Module--WARNING:this only deals with one set of tags per module
#		if ($additional_information =~ /<$module>(.*)<\/$module>/) {
#				$module_information = $1;
#				if ($module_information !~ /<$tag>(.*)<\/$tag>/ ) {
#						$module_information =~ s(<$module>(.*)</$module>)(<$module><$tag></$tag>$1</$module>);
#				}
				## Put $module_information back into $additional_information
#				$additional_information =~ s(<$module>(.*)</$module>)($module_information);
#		}else {
#				$module_information = "<$module><$tag></$tag></$module>";
#				$additional_information .= $module_information;
#		}

		#### Either insert/update/remove
#		if ($update) {
#				$_information =~ s(<$module>(.*)<$tag>(.*)<\/$tag>(.*)<\/$module>/)(<$module>(.*)<$tag>$tag_information<\/$tag>(.*)<\/$module>/);
#		}elsif ($update) {
#				$additional_information =~ 
		#### insert/update additional_information in the database
#				}


#}




###############################################################################

1;

__END__

###############################################################################
###############################################################################
###############################################################################

=head1 SBEAMS::Connection::DBInterface

SBEAMS Core database interface module

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


=item * B<updateOrInsertRow(several key value parameters)>

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
  my $contact_id = $sbeams->updateOrInsertRow(insert=>1,
    table_name => "contact", rowdata_ref => \%rowdata,
    PK=>"contact_id", return_PK=>1,
    #verbose=>1,
    #testonly=>1
    );

  %rowdata = ();
  $rowdata{phone_number} = "123-456-7890";
  $rowdata{email} = "SpamMeSenseless@hotmail.com";
  my $result = $sbeams->updateOrInsertRow(update=>1,
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
functions like updateOrInsertRow() or methods that update indexes or
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


=item * B<displayQueryResult(several key value parameters)>

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

=item * B<isRowprivate>

=item * B<applySQLChange>

=item * B<getDbTableName>

=item * B<translateSQL>

=item * B<convert_concatenation>

=item * B<convert_functions>

=item * B<buildLimitClause>

=item * B<insert_update_row>

=item * B<deleteRecordsAndChildren>

=item * B<translateOptionValue>

=item * B<isResultsetColumnNumerical>

=item * B<resultsetByCharacter>

=item * B<resultsetNumerically>

=item * B<displayResultSetPlot>

=item * B<displayTimingInfo>

=item * B<parseResultSetParams>

=item * B<parse_input_parameters>

=item * B<processStandardParameters>

=item * B<display_input_form>

=item * B<display_form_buttons>

=item * B<display_sql>

=item * B<build_SQL_columns_list>

=item * B<transferTable>

=item * B<importTSVFile>

=item * B<unix2dosFile>

=item * B<getModules>

=item * B<readModuleFile>

=item * B<printRecentResultsets>

=item * B<getRecentResultsets>

=item * B<printProjectsYouOwn>

=item * B<getProjectsYouOwn>

=item * B<printProjectsYouHaveAccessTo>

=item * B<getProjectsYouHaveAccessTo>

=item * B<printUserChooser>

=item * B<linkToColumnText>

=item * B<getPopupDHTML>

=item * B<isTaintedSQL>



=back

=head2 BUGS

Please send bug reports to the author

=head2 AUTHOR

Eric Deutsch <edeutsch@systemsbiology.org>

=head2 SEE ALSO

SBEAMS::Connection

=cut

