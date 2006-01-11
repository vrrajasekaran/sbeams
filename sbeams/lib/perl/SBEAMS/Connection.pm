package SBEAMS::Connection;

###############################################################################
# Program     : SBEAMS::Connection
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : Perl Module to handle all SBEAMS connection issues, including
#               authentication and DB connections.
#
###############################################################################


use strict;
use vars qw($VERSION @EXPORT @EXPORT_OK $invocation_mode $output_mode 
            $output_stage $table_nest_level);

require Exporter;
use SBEAMS::Connection::Log;

# We import the $q object created in Authenticator
use SBEAMS::Connection::Authenticator qw( $q );

our @ISA =  qw( Exporter );
our $log = SBEAMS::Connection::Log->new();

# Export the log object we created, reexport $q from Authenticator.
@EXPORT_OK = qw( $log $q );

use SBEAMS::Connection::DBConnector;
use SBEAMS::Connection::DBInterface;
use SBEAMS::Connection::HTMLPrinter;
use SBEAMS::Connection::TableInfo;
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::ErrorHandler;
use SBEAMS::Connection::Utilities;
use SBEAMS::Connection::Permissions;

push @ISA, qw(SBEAMS::Connection::Authenticator 
           SBEAMS::Connection::DBConnector
           SBEAMS::Connection::DBInterface 
           SBEAMS::Connection::HTMLPrinter
           SBEAMS::Connection::TableInfo
           SBEAMS::Connection::Settings
           SBEAMS::Connection::ErrorHandler
           SBEAMS::Connection::Utilities
           SBEAMS::Connection::Permissions
           );



###############################################################################
# Global Variables
###############################################################################
$VERSION = '0.02';


###############################################################################
# Constructor
###############################################################################
sub new {

  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};
  bless($self,$class);

  ## register with Connection::ErrorHandler:
  $self->register_sbeams($self);

  return($self);

} # end new


###############################################################################
# Getter/setter for invocation_mode
###############################################################################
sub invocation_mode {
  my $self = shift;
  my $new_value = shift;

  my $METHOD_NAME = "invocation_mode()";

      #### If a new value was supplied, set it
  if ($new_value) {
    die "$METHOD_NAME: Illegal value '$new_value'"
      unless ($new_value eq 'http' || $new_value eq 'user' || $new_value eq 'https');
    $invocation_mode = $new_value;

  #### Otherwise, verify that we have a value or set a blank
  } else {
    #die "$METHOD_NAME: value has not yet been set!"
    $invocation_mode = ""
      unless ($invocation_mode);
  }

  #### Return the current value in either case
  return $invocation_mode;

} # end invocation_mode

#+
# Light-weight accessor
#-
sub get_output_mode {
  return $output_mode || output_mode();
}

###############################################################################
# Getter/setter for output_mode
###############################################################################
sub output_mode {
  my $self = shift;
  my $new_value = shift;

  my $METHOD_NAME = "output_mode()";

  #### If a new value was supplied, set it
  if ($new_value) {
    die "$METHOD_NAME: Illegal value '$new_value'"
      unless ($new_value eq 'html' || $new_value eq 'interactive' ||
              $new_value eq 'tsv' || $new_value eq 'tsvfull' ||
              $new_value eq 'csv' || $new_value eq 'csvfull' ||
              $new_value eq 'xml' ||
              $new_value eq 'cytoscape' ||
              $new_value eq 'boxtable' ||
	      $new_value eq 'excel' || $new_value eq 'excelfull'
      );
    $output_mode = $new_value;

  #### Otherwise, verify that we have a value
  } else {
    unless ($output_mode) {
      print STDERR $self->getStackTrace();
      print "$METHOD_NAME: value has not yet been set!  This should never ".
        "happen, but I will set it to interactive just to see where this ".
        "ends up.  It is almost surely a bug that needs ".
        "to be reported.<BR><BR>\n\n";
      $output_mode = $self->output_mode('interactive');
    }
  }

  #### Return the current value in either case
  return $output_mode;

} # end output_mode


###############################################################################
# Getter/setter for output_stage
###############################################################################
sub output_stage {
  my $self = shift;
  my $new_value = shift;

  my $METHOD_NAME = "output_stage()";

  #### If a new value was supplied, set it
  if ($new_value) {
    die "$METHOD_NAME: Illegal value '$new_value'"
      unless ($new_value eq 'no_header_yet' || $new_value eq 'form_stage' ||
              $new_value eq 'data_stage' || $new_value eq 'footer_complete'
      );
    $output_stage = $new_value;

  #### Otherwise, verify that we have a value
  } else {
    die "$METHOD_NAME: value has not yet been set!"
      unless ($output_stage);
  }

  #### Return the current value in either case
  return $output_stage;

} # end output_stage


###############################################################################
# Getter/setter for table_nest_level
###############################################################################
sub table_nest_level {
  my $self = shift;
  my $new_value = shift;

  my $METHOD_NAME = "table_nest_level()";

  #### If a new value was supplied, set it
  if ($new_value) {
    die "$METHOD_NAME: Illegal value '$new_value'"
      unless ($new_value >= 0);
    $table_nest_level = $new_value;

  #### Otherwise, verify that we have a reasonable value
  } else {
    $table_nest_level = 0 unless ($table_nest_level);
  }

  #### Return the current value in either case
  return $table_nest_level;

} # end table_nest_level







###############################################################################

1;

__END__
###############################################################################
###############################################################################
###############################################################################


=head1 NAME

 SBEAMS::Connection - The SBEAMS Core database connection module

=head1 DESCRIPTION

Handles all SBEAMS connection issues, including authentication and DB 
connections.  

It multiply inherits

    SBEAMS::Connection::Authenticator

    SBEAMS::Connection::DBConnector
    
    SBEAMS::Connection::DBInterface 

    SBEAMS::Connection::HTMLPrinter

    SBEAMS::Connection::TableInfo

    SBEAMS::Connection::Settings

    SBEAMS::Connection::ErrorHandler

    SBEAMS::Connection::Utilities

    SBEAMS::Connection::Permissions


=head2 EXAMPLE USAGE

    ##load Connection modules and create instance:
    use SBEAMS::Connection;
    use SBEAMS::Connection::Settings;
    use SBEAMS::Connection::Tables;

    $sbeams = new SBEAMS::Connection;

    ##load module of interest and create instance:
    use SBEAMS::PeptideAtlas;
    use SBEAMS::PeptideAtlas::Settings;
    use SBEAMS::PeptideAtlas::Tables;

    $sbeamsMOD = new SBEAMS::PeptideAtlas;
    $sbeamsMOD->setSBEAMS($sbeams);
    $sbeams->setSBEAMS_SUBDIR($SBEAMS_SUBDIR);

    ## load CGI module and create instance:
    use CGI;
    $q = new CGI;

    ## authenticate user:
    exit unless ($current_username = $sbeams->Authenticate(
        allow_anonymous_access => 1
    ));


    ## read in parameters passed to script:
    my %parameters;

    my $n_params_found = $sbeams->parse_input_parameters(
        q => $q,
        parameters_ref => \%parameters
    );


    ## perform action or display HTML:
    if ($parameters{action} eq "doThis") {
        doThis();
    } else {
        $sbeamsMOD->display_page_header( navigation_bar => $parameters{navigation_bar});
        handle_request(ref_parameters=>\%parameters);
        $sbeamsMOD->display_page_footer();
    }




=head2 METHODS

=over

=item * B<new>

constructor registers the instance with Connection::ErrorHandler

=item * B<invocation_mode>

get/set method.  expecting values such as
    'http'
    'user' 
    'https'
    ""

=item * B<output_mode>

get/set method.  expecting values such as
   'html' 
   'interactive' 
   'tsv'
   'tsvfull' 
   'csv' 
   'csvfull'
   'xml'
   'cytoscape' 
   'boxtable'
   'excel'
   'excelfull'

output_mode is used by Connection::Authenticator, 
Connection::DBInterface, and Connection::HTMLPrinter
to direct output to html or a tsv formatted file, for example

=item * B<output_stage>

get/set method.  expecting values such as
    'no_header_yet'
    'form_stage'
    'data_stage'
    'footer_complete'


=item * B<table_nest_level>

get/set method.  expecting values >= 0


=back

=head2 BUGS

Please send bug reports to the author

=head2 AUTHOR

Eric Deutsch <edeutsch@systemsbiology.org>

=head2 SEE ALSO

SBEAMS::Connection::Authenticator

SBEAMS::Connection::DBConnector

SBEAMS::Connection::DBInterface

SBEAMS::Connection::HTMLPrinter

SBEAMS::Connection::TableInfo

SBEAMS::Connection::Settings

SBEAMS::Connection::ErrorHandler

SBEAMS::Connection::Utilities

SBEAMS::Connection::Permissions


=cut
