package SBEAMS::Ontology::DBInterface;

###############################################################################
# Program     : SBEAMS::Ontology::DBInterface
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This is part of the SBEAMS::Ontology module which handles
#               general communication with the database.
#
###############################################################################


use strict;
use vars qw(@ERRORS);
use CGI::Carp qw(fatalsToBrowser croak);
use DBI;



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
# 
###############################################################################

# Add stuff as appropriate




###############################################################################

1;

__END__
###############################################################################
###############################################################################
###############################################################################
