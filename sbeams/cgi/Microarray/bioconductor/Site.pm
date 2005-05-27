package Site;

use FindBin;
use lib "$FindBin::Bin/../../../lib/perl";

use SBEAMS::Connection::Settings;
use SBEAMS::Microarray;
use SBEAMS::Microarray::Settings;
use strict;
my $sbeamsMOD = new SBEAMS::Microarray;

our @ISA    = qw/Exporter/;
our @EXPORT = qw/site_header site_footer
  $BC_UPLOAD_DIR $RESULT_DIR $RESULT_URL $BIOC_URL $SITE_URL $SAMPLE_GROUP_XML
  $ADMIN_EMAIL $R_BINARY $R_LIBS $USE_FRAMES $DEBUG $AFFY_ANNO_PATH
  $JAVA_PATH $JWS_PATH $TOMCAT $KEYSTORE $KEYPASS
  $SH_HEADER $BATCH_SYSTEM %BATCH_ENV $BATCH_BIN $BATCH_ARG
  $MEV_JWS_BASE_DIR $MEV_JWS_BASE_HTML $SHARED_JAVA_DIR $SHARED_JAVA_HTML/;
 
my $base_path = $sbeamsMOD->affy_bioconductor_devlivery_path();

# Name of xml file holding sample group info
our $SAMPLE_GROUP_XML = 'File_sample_groups.xml';

# Upload repository directory
our $BC_UPLOAD_DIR = $base_path;

# Job results directory & web accessible URL
our $RESULT_DIR = $base_path;
our $RESULT_URL = "$CGI_BASE_DIR/Microarray/View_Affy_files.cgi";

# cgi-bin URL and site URL
our $BIOC_URL = "$CGI_BASE_DIR/Microarray/bioconductor";

# Admin e-mail
#our $ADMIN_EMAIL = 'pmoss@systemsbiology.org';
our $ADMIN_EMAIL = 'bmarzolf@systemsbiology.org';

# Location of R binary & R libraries
our $R_BINARY = "/tools/bin/R";
our $R_LIBS   = "/net/arrays/Affymetrix/bioconductor/library";

# Location of Annotation file from affymetrix for chip you will be using
our $AFFY_ANNO_PATH = "/net/arrays/Affymetrix/library_files";

#Java Path
our $JAVA_PATH = "/usr/java/j2sdk1.4";
#our $JWS_PATH  = "/local/tomcat/webapps/microarray";
#our $TOMCAT    = "http://db:8080/microarray";
our $KEYSTORE  = "/users/pmoss/myKeystore";
our $KEYPASS   = "test01";

#MEV (Multipule experiment viewer from TIGR) Info

our $MEV_JWS_BASE_DIR = "$PHYSICAL_BASE_DIR/tmp/Microarray/Make_MEV_jws_files/jws";
our $MEV_JWS_BASE_HTML   = "$SERVER_BASE_DIR$HTML_BASE_DIR/tmp/Microarray/Make_MEV_jws_files/jws";
our $SHARED_JAVA_DIR  = "$PHYSICAL_BASE_DIR/usr/java/shared";
our $SHARED_JAVA_HTML = "$SERVER_BASE_DIR$HTML_BASE_DIR/usr/java/share/MEV";

# Use frames for showing results
our $USE_FRAMES = 0;

# Turn on debugging output
our $DEBUG = 0;

# Append commands to the top of shell scripts (environment variables, etc.)
our $SH_HEADER = <<'END';
export PATH=$PATH:/usr/sbin:/usr/local/bin
END

# Batch system to use (fork, sge, pbs)
our $BATCH_SYSTEM = "pbs";

# Batch system environment variables
our %BATCH_ENV = ( SGE_ROOT => "/path/to/sge" );

# Batch system binary directory
our $BATCH_BIN = "sudo -u arraybot /usr/local/bin";

# Batch system additional job submission arguments
our $BATCH_ARG = "";

#### Subroutine: site_header
# Print out leading HTML
####
sub site_header {
	my ($title) = @_;

	print <<END;
<div style="text-align: center">
<a href="upload.cgi?_tab=1">Upload Files</a> |
<a href="upload.cgi?_tab=2" >View Normalized Data</a> |
<a href="upload.cgi?_tab=3">View Experimental results</a> |
</div>
END
}

#### Subroutine: site_footer
# Print out lagging HTML
####
sub site_footer {

	print <<END;
</body>
</html>
END
}

1;
