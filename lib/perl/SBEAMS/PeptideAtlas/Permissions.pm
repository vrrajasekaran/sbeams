package SBEAMS::PeptideAtlas::Permissions;

###############################################################################
# Program     : SBEAMS::PeptideAtlas::Permissions
# Author      : Nichole King <nking@systemsbiology.org>
#
# Description : This is part of the SBEAMS::WebInterface module which handles
#               checks user project privileges.  Useful in conjunction
#               with HTMLPrinter to tailor a skin (navbar options) for
#               a project.
###############################################################################

use 5.008;

use strict;

use vars qw(@ERRORS $q @EXPORT @EXPORT_OK);
use CGI::Carp qw(fatalsToBrowser croak);
use Exporter;
our @ISA = qw( Exporter );

use SBEAMS::Connection::Log;
use SBEAMS::Connection::Authenticator qw( $q );
use SBEAMS::Connection::Settings;
use SBEAMS::PeptideAtlas::Tables;
use SBEAMS::Connection::Tables;

my $log = SBEAMS::Connection::Log->new();

##our $VERSION = '0.20'; can get this from Settings::get_sbeams_version


# Preloaded methods go here.

###############################################################################
# Constructor
###############################################################################
#sub new 
#{
#    my $this = shift;
#    my $class = ref($this) || $this;
#    my $self = {};
#    bless $self, $class;
#    return($self);
#}


###############################################################################
# Utility routine, checks if current user is 'guest' user.
# FIXME: make id lookup dynamic
###############################################################################
sub isPAGuestUser {

  my $self = shift;

  my $sbeams = $self->getSBEAMS();

  my $currID =  $sbeams->getCurrent_contact_id();

  if ( !defined $currID ) {

      return undef;

  } elsif ( $currID == 107 ) {

      return 1;

  } else {

      return 0;

  }

}


###############################################################################
# Utility routine, checks if current project is yeast development.
# Returns 1 if true, 0 if false.
###############################################################################
sub isYeastPA
{

    my $self = shift ;

    my $sbeams = $self->getSBEAMS();
 
    my %args = @_;

    my $project_id = $args{'project_id'} || $sbeams->getCurrent_project_id();

    if ( !defined $project_id ) 
    {
        return undef;

    } elsif ($project_id == 491 ) 
    {
        return 1;

    } else {

        return 0;
    }

}



###############################################################################
# Utility routine, gets current project id, and checks that it's
# accessible to user.  If yes, returns project id, else returns 0.
###############################################################################
sub getProjectID
{

    my $self = shift ;

    my $sbeams = $self->getSBEAMS();
 
    my %args = @_;

    my $atlas_build_name = $args{'atlas_build_name'} || '';

    my $atlas_build_id = $args{'atlas_build_id'} || '';

    my $sql='';

    if ($atlas_build_name)
    {
        $sql = qq~
            SELECT project_id
            FROM $TBAT_ATLAS_BUILD
            WHERE atlas_build_name = '$atlas_build_name'
            ~;
    } elsif ( $atlas_build_id )
    {
        $sql = qq~
            SELECT project_id
            FROM $TBAT_ATLAS_BUILD
            WHERE atlas_build_id = '$atlas_build_id'
            ~;
    }

    if ($sql)
    {
        my ($project_id) = $sbeams->selectOneColumn($sql) or
          die "\nERROR: Unable to find the project_id"
          . " with $sql\n\n";

        ## check that project is accessible:
        if ( $sbeams->isProjectAccessible( project_id => $project_id ) )
        {

            return $project_id;

        } else
        {

            return 0;

        }

    } else
    {
        return 0;
    }

}



###############################################################################
# isProjectAccessible
###############################################################################
#sub isProjectAccessible{
#  my $self = shift || croak("parameter self not passed");
#  my %args = @_;
#
#  ## Decode Arguments
#  my $project_id = $args{'project_id'} || $self->getCurrent_project_id();
#
#  my @accessible_projects = $self->getAccessibleProjects();
#  foreach my $id (@accessible_projects) {
#        if ($id == $project_id) {
#          return 1;
#        }
#  }
#  return 0;
#}



###############################################################################
# prntVar
###############################################################################
sub prntVar
{

  my ($str, $val) = @_;

  print "$str = $val\n";

}



###############################################################################
# getCurrentAtlasBuildID
###############################################################################
sub getCurrentAtlasBuildID {
  my $METHOD_NAME = 'getCurrentAtlasBuildID';
  my $self = shift || die("ERROR[$METHOD_NAME]: parameter self not passed");
  my %args = @_;

  #### Decode the argument list
  my $parameters_ref = $args{'parameters_ref'}
   || die "ERROR[$METHOD_NAME]: parameters_ref not passed";
  my %parameters = %{$parameters_ref};
  my $sbeams = $self->getSBEAMS();


  #### Extract what was specified as a parameter
  my $atlas_build_id = $parameters{'atlas_build_id'};
  my $atlas_build_name = $parameters{'atlas_build_name'};


  #### If atlas_build_id was supplied
  if ($atlas_build_id) {
    #### we're fine, this is exactly what we want

  #### Else if atlas_build_name was supplied
  } elsif ($atlas_build_name) {

    #### Build atlas_build_name constraint
    my $atlas_build_name_clause = $sbeams->parseConstraint2SQL(
      constraint_column=>"atlas_build_name",
      constraint_type=>"plain_text",
      constraint_name=>"Atlas Build Name",
      constraint_value=>$parameters{atlas_build_name} );
    return if ($atlas_build_name_clause eq '-1');

    #### Fetch the id based on the name
    my $sql = qq~
      SELECT atlas_build_id
        FROM $TBAT_ATLAS_BUILD
       WHERE 1=1
         $atlas_build_name_clause
         AND record_status != 'D'
    ~;
    my @rows = $sbeams->selectOneColumn($sql);


    #### Check that we got only one result or squawk
    if (scalar(@rows) == 0) {
      print "ERROR[$METHOD_NAME]: No atlas_build_id's found for ".
	"'$atlas_build_name'<BR>\n";
      return(-1);

    } elsif (scalar(@rows) > 1) {
      print "ERROR[$METHOD_NAME]: Too many atlas_build_id's found for ".
	"'$atlas_build_name'<BR>\n";
      return(-1);

    } else {
      $atlas_build_id = $rows[0];
    }

  #### Otherwise try to get it from the session cookie
  } else {
    $atlas_build_id = $sbeams->getSessionAttribute(
      key => 'PeptideAtlas_atlas_build_id',
    );

  }


  #### If we still don't have an atlas_build_id, guess!
  unless ($atlas_build_id) {
    my $organism_name = $sbeams->getSessionAttribute(
      key => 'PeptideAtlas_organism_name',
    );

    my $default_atlas_build_name_clause;
    if ($organism_name) {
      $default_atlas_build_name_clause =
        "  AND O.organism_name = '$organism_name'\n";
    } else {
      $default_atlas_build_name_clause =
        "  AND O.organism_name IS NULL\n";
    }

    my $sql = qq~
        SELECT atlas_build_id
          FROM $TBAT_DEFAULT_ATLAS_BUILD DAB
          LEFT JOIN $TB_ORGANISM O
               ON ( DAB.organism_id = O.organism_id AND O.record_status != 'D')
         WHERE 1=1
           $default_atlas_build_name_clause
           AND DAB.record_status != 'D'
    ~;
    my @rows = $sbeams->selectOneColumn($sql);

    if (scalar(@rows) > 1) {
      die("ERROR: Too may rows returned for $sql");
    }

    if (defined(@rows)) {
      $atlas_build_id = $rows[0];
    }

  }


  #### If we still don't have an atlas_build_id, just assume id 1!
  unless ($atlas_build_id) {
    $atlas_build_id = 1;
  }


  #### Verify that the user is allowed to see this atlas_build_id
  my @accessible_project_ids = $sbeams->getAccessibleProjects();
  my $accessible_project_ids = join( ",", @accessible_project_ids ) || '0';
  my $sql = qq~
      SELECT atlas_build_id
        FROM $TBAT_ATLAS_BUILD AB
       WHERE AB.project_id IN ( $accessible_project_ids )
         AND AB.record_status!='D'
         AND atlas_build_id = '$atlas_build_id'
  ~;
  my @rows = $sbeams->selectOneColumn($sql);

  #### If not, stop here
  unless (scalar(@rows) == 1 && $rows[0] eq $atlas_build_id) {
    print "<BR>ERROR: You are not permitted to access atlas_build_id ".
      "'$atlas_build_id' with your current credentials.  You may need to ".
      "login with your username and password.  Click on the LOGIN link at ".
      "left.<BR>\n";
    return(-1);
  }


  #### Test if the current session already has this atlas_build_id, and if
  #### not, then set it
  my $cached_atlas_build_id = $sbeams->getSessionAttribute(
      key => 'PeptideAtlas_atlas_build_id',
    );

  if ($cached_atlas_build_id != $atlas_build_id) {
    $sbeams->setSessionAttribute(
      key => 'PeptideAtlas_atlas_build_id',
      value => $atlas_build_id,
    );
  }

  return($atlas_build_id);

} # end getCurrentAtlasBuildID



###############################################################################
1;
__END__
###############################################################################
###############################################################################
###############################################################################


# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Permissions - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Permissions;
  blah blah blah

=head1 ABSTRACT

  This should be the abstract for Permissions.
  The abstract is used when making PPD (Perl Package Description) files.
  If you don't want an ABSTRACT you should also edit Makefile.PL to
  remove the ABSTRACT_FROM option.

=head1 DESCRIPTION

Stub documentation for Permissions, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Nichole King, E<lt>nking@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 by Institute for Systems Biology	 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
