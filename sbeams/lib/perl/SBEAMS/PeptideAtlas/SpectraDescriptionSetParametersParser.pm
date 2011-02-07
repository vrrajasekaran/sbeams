package SpectraDescriptionSetParametersParser;
use strict;
use Carp;

use 5.008;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use SpectraDescriptionSetParametersParser ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '5.8';



# Preloaded methods go here.

sub new 
{
    my $class = shift;
    my %args = @_;
    my $self = {};
    $self->{spectrumXML_file} = undef;
    $self->{spectrumXML_schema} = undef;
    $self->{conversion_software_name} = undef;
    $self->{conversion_software_version} = undef;
    $self->{instrument_model_name} = undef;
    bless ($self, $class);
    return $self;
}


sub setSpectrumXML_file
{
    my ($self, $file) = @_;
    croak("missing argument to setSpectrumXML_file") unless defined $file;
    $self->{spectrumXML_file} = $file;
}

sub getSpectrumXML_schema 
{
    my ($self) = @_;
    return $self->{spectrumXML_schema};
}


sub getConversion_software_name
{
    my ($self) = @_;
    return $self->{conversion_software_name};
}


sub getConversion_software_version
{
    my ($self) = @_;
    return $self->{conversion_software_version};
}


sub getInstrument_model_name
{
    my ($self) = @_;
    return $self->{instrument_model_name};
}

sub parse {
  my ($self) = @_;
  croak("missing spectrumXML_file, use setSpectrumXML_file(xx)") if
      !$self->{spectrumXML_file};
  my $infile = $self->{spectrumXML_file};
  #print "infile = $infile\n";

  open(INFILE, "$infile") or die "cannot open $infile for reading ($!)";
  print "Reading $infile...\n";

  my $n_lines = 0;
  while (defined(my $line = <INFILE>) && ($n_lines < 10)) {
    if ($line =~ /<mzML/) {
      close(INFILE) or die "Cannot close $infile";
      $self->parse_mzML();
      return;
    } elsif ($line =~ /<mzXML/) {
      close(INFILE) or die "Cannot close $infile";
      $self->parse_mzXML();
      return;
    }elsif($line =~ /<msRun/){
      close(INFILE) or die "Cannot close $infile";
      $self->parse_mzXML();
      return;
    }
    $n_lines++;
  }
  croak("$infile is neither mzML nor mzXML.\n");
}


sub parse_mzML {
  my ($self) = @_;
#  croak("missing mzML file, use setSpectrumXML_file(xx)")
#     if !$self->{spectrumXML_file};

  my $infile = $self->{spectrumXML_file};
  my $schema = "";
  my $model_name = "";
  my $software_name = "";
  my $software_version = "unknown";  #mzML doesn't seem to provide.

  open(INFILE, "<$infile") or die "cannot open $infile for reading ($!)";

  while ( defined(my $line = <INFILE>)) {

    chomp($line);

    #### Once we get to a run tag, we have all the information
    #### we need, so stop the parsing
    if ($line =~ /<run/) {
      last;
    }

    ## 2010 mzML schema:
    ## xsi:schemaLocation="http://psi.hupo.org/ms/mzml http://psidev.info/files/ms/mzML/xsd/mzML1.1.0.xsd"
    if (($line =~ /<mzML/) &&
        ($line =~ /.+schemaLocation=\".+\/(.+)\/xsd\/(.+)\.xsd\"/ )) {
      $schema = $2;
    }

    if ($line =~ /\<dataProcessing id=\"(\S+)\">/ ) {
      $software_name = $1;
    }
    $software_version = "unknown";

    if ($line =~ /\<instrumentConfiguration id=/ ) {
      ## read the next line, and get model name
      $line = <INFILE>;
      chomp($line);
      $line =~ /<cvParam .* name=\"(.+?)\"/;
      $model_name = $1;
    }
  }

  close(INFILE) or die "Cannot close $infile";
  print "Done\n";

  if ($software_version eq "") {
    carp "[WARN] please edit parser to pick up conversion_software_version for $infile";
  } 
  $self->{conversion_software_version} = $software_version;

  if ($software_name eq "") {
    carp "[WARN] please edit parser to pick up conversion_software_name for $infile";
  }
  $self->{conversion_software_name} = $software_name;

  if ($schema eq "") {
    carp "[WARN] please edit parser to pick up schema for $infile";
  } 
  $self->{spectrumXML_schema} = $schema;
  print "$schema \n";
  if ($model_name eq "") {
    carp "[WARN] please edit parser to pick up instrument_model_name for $infile";
  }
  $self->{instrument_model_name} = $model_name;

  print "schema = $schema\n";
  print "model_name = $model_name\n";
  print "software_name = $software_name\n";
  print "software_version = $software_version\n";

} # End parse method



sub parse_mzXML {
  my ($self) = @_;
  croak("missing mzML file, use setSpectrumXML_file(xx)")
     if !$self->{spectrumXML_file};
  my $infile = $self->{spectrumXML_file};

  my ($schema, $model_name, $software_name, $software_version);

  open(INFILE, "<$infile") or die "cannot open $infile for reading ($!)";
  while ( defined(my $line = <INFILE>)) {

    chomp($line);

    #### Once we get to an msLevel attribute, we have all the information
    #### we need, so stop the parsing
    if ($line =~ /msLevel=/) {
      last;
    }


    ## former MsXML schema:
    ## xsi:schemaLocation="http://sashimi.sourceforge.net/schema/ http://sashimi.sourceforge.net/schema/MsXML.xsd
    if($line =~ /schemaLocation/){
      if ($line =~ /.*\/(\S+.xsd)\"/ ) {
        $schema = $1;
      }
    }
    #if ($line =~ /.+schemaLocation=\".+\/(.+)\/schema_revision\/.*(mz\S+.xsd)\"/ ) {
    #  $schema = $2;
    #}
    #if ($line =~ /.+schemaLocation=\".+\/(.+)\/schema\/(.+)\.xsd\"/ ) {
    #  $schema = $2;
    #}
#        if ($line =~ /\<msManufacturer\scategory=\".+\"\svalue=\"(.+)\"\/\>/)
    if ($line =~ /\<msManufacturer\s+category=\".+\"\s+value=\"(.+)\".*\/\>/) {
      $model_name = ( $model_name ) ? $model_name . " $1" : $1;
    }
    if ($line =~ /\<msModel\s+category=\".+\"\svalue=\"(.+)\"\s*\/\>/) {
      $model_name = ( $model_name ) ? $model_name . " $1" : $1;
    }


    ## former MsXML schema:
    if ($line =~ /\<instrument\smanufacturer=\"(.+)\"/ ) {
      $model_name = $1;

      ## read the next line, and get model name
      $line = <INFILE>;
      chomp($line);
      $line =~ /\s+model=\"(.+)\"/;
      $model_name = $model_name . " $1";
    }


    if ($line =~ /\<software\stype=\"conversion(.+)/ ||
       $line =~ /\<software\stype=\"processing(.+)/ ) {

      # why oh why aren't we using an xml parser?
      my $morecontent = $1;
      if ($morecontent =~ /name\s*=\s*\"(.*?)\"/) {
        $software_name = $1;
      }
      if ($morecontent =~ /version\s*=\s*\"(.*?)\"/) {
        $software_version = $1;
      }

      # Lets not do this unless we have to
      if ( !$software_name || !$software_version ) {
        $line = <INFILE>;
        chomp($line);
        if ($line =~ /.+name=\"(.+)\"/) {
          $software_name = $1;
        } else {
          carp "[WARN] please edit parser to pick up software attributes";
        }

        $line = <INFILE>;
        chomp($line);
        if ($line =~ /.+version=\"(.+)\"/) {
          $software_version = $1;
        }
        last; ## done
      }

    }

  }

  close(INFILE) or die "Cannot close $infile";
  print "Done\n";

  if ($software_version eq "") {
    carp "[WARN] please edit parser to pick up conversion_software_version for $infile";
  } 
  $self->{conversion_software_version} = $software_version;

  if ($software_name eq "") {
    carp "[WARN] please edit parser to pick up conversion_software_name for $infile";
  }
  $self->{conversion_software_name} = $software_name;

  if ($schema eq "") {
    carp "[WARN] please edit parser to pick up schema for $infile";
  } 
  $self->{spectrumXML_schema} = $schema;

  if ($model_name eq "") {
    carp "[WARN] please edit parser to pick up instrument_model_name for $infile";
  }

  $self->{instrument_model_name} = $model_name;
} # End parse method



1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 SpectraDescriptionSetParametersParser


=head1 SYNOPSIS

SpectraDescriptionSetParametersParser does a quick parse
of an mzXML file to get the handful of information needed for
database attributes in PeptideAtlas table spectra_description_set,
and needed for versioning, etc.

USAGE:

use SpectraDescriptionSetParametersParser;

my $spectrum_parser = new SpectraDescriptionSetParametersParser();

$spectrum_parser->setMzXML_file("/path/to/file.mzXML");

$spectrum_parser->parse();

my $mzXML_schema = $spectrum_parser->getMzXML_schema();

my $conversion_software_name = getConversion_software_name();

my $conversion_software_version = getConversion_software_version();



=head1 ABSTRACT

   see above


=head1 DESCRIPTION

  see above

=head2 EXPORT

None by default.



=head1 SEE ALSO


=head1 AUTHOR Nichole King

=head1 COPYRIGHT AND LICENSE


This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
