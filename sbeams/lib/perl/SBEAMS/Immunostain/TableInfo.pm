package SBEAMS::Immunostain::TableInfo;

###############################################################################
# Program     : SBEAMS::Immunostain::TableInfo
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This is part of the SBEAMS::Immunostain module which returns
#               information about various tables.
#
###############################################################################

use strict;
use CGI::Carp qw(fatalsToBrowser croak);

use SBEAMS::Immunostain::Settings;
use SBEAMS::Immunostain::Tables;
use SBEAMS::Connection::Tables;


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
# Return Table Info
#
# Return the required information about the specified Table
###############################################################################
sub returnTableInfo {
    my $self = shift;
    my $table_name = shift || croak("parameter table_name not specified");
    my $info_key = shift || croak("parameter info_key not specified");

    my @row;
    my $sql_query;
    my $result;


###############################################################################
#
# First we have table-specific overrides of the default answers
#
# This is mostly just Queries now.  This should be pushed out into a
# nicely formatted file of queries.
#
###############################################################################
###############################################################################
    if ($table_name eq "blxxxxxx") {

        if ($info_key eq "BASICQuery") {
            return qq~
		SELECT hardware_id,HT.name,make,model,serial_number,uri
		  FROM xxxxxxxx H
		  JOIN xxxxxxxxx HT
		       ON (H.hardware_type_id=HT.hardware_type_id)
		 WHERE H.record_status!='D'
            ~;
        }

        if ($info_key eq "FULLQuery") {
            return qq~
		SELECT H.*
		  FROM xxxxxxx H
		  JOIN xxxxxx HT
		       ON (H.hardware_type_id=HT.hardware_type_id)
		 WHERE H.record_status!='D'
            ~;
        }


    }

	
  if ($table_name eq "IS_assay") {
    if ($info_key eq "BASICQuery") {
      return qq~	
		  SELECT SS.assay_id,project_tag,tissue_type_name,
			specimen_block_name,antibody_name,assay_name,
			assay_description, A.sort_order, organism_name
			FROM $TBIS_ASSAY SS
			LEFT JOIN $TB_PROJECT P ON ( SS.project_id = P.project_id )
			LEFT JOIN $TBIS_SPECIMEN_BLOCK SB
			ON ( SS.specimen_block_id = SB.specimen_block_id )
			LEFT JOIN $TBIS_SPECIMEN S
			ON ( SB.specimen_id = S.specimen_id )
			LEFT JOIN $TB_ORGANISM O
			ON ( S.organism_id = O.organism_id )
			LEFT JOIN $TBIS_TISSUE_TYPE TT
			ON ( S.tissue_type_id = TT.tissue_type_id )
			Left Join $TBIS_ASSAY_CHANNEL AC 
			on (SS.assay_id = AC.assay_id)
			LEFT JOIN $TBIS_ANTIBODY A
			ON ( AC.antibody_id = A.antibody_id )	
			WHERE SS.record_status!='D'	
			ORDER BY SS.assay_id,project_tag,tissue_type_name,specimen_block_name,		
			A.sort_order,A.antibody_name,SS.assay_name
      ~;
      } elsif ( $info_key eq 'hidden_cols' ) {
        return ( sort_order => 1,
                 organism_id => 1 );
    }
  }
	
	if ($table_name eq "IS_assay_image") {
    if ($info_key eq "BASICQuery") {
      return qq~
	    SELECT si.assay_image_id, project_tag, specimen_block_name,
             antibody_name, assay_name, image_name, image_magnification,
             raw_image_file, processed_image_file, annotated_image_file,
             A.sort_order, tissue_type_name, organism_name
		  FROM $TBIS_ASSAY_IMAGE SI
		  LEFT JOIN $TBIS_ASSAY_CHANNEL AC 
			  ON (SI.ASSAY_CHANNEL_ID = AC.ASSAY_CHANNEL_ID)
		  LEFT JOIN $TBIS_ASSAY SS
        ON ( AC.ASSAY_ID = SS.ASSAY_ID )
		  LEFT JOIN $TB_PROJECT P 
        ON ( SS.project_id = P.project_id )
		  LEFT JOIN $TBIS_SPECIMEN_BLOCK SB
		    ON ( SS.specimen_block_id = SB.specimen_block_id )
		  LEFT JOIN $TBIS_SPECIMEN S
		    ON ( SB.specimen_id = S.specimen_id )
		  LEFT JOIN $TBIS_TISSUE_TYPE TT
		    ON ( S.tissue_type_id = TT.tissue_type_id )
		  LEFT JOIN $TBIS_ANTIBODY A
		    ON ( AC.antibody_id = A.antibody_id )
		  JOIN $TB_ORGANISM O
		    ON ( O.organism_id = S.organism_id )
		  WHERE SS.record_status!='D'
      AND SI.record_status!='D'
		  ORDER BY project_tag,tissue_type_name,specimen_block_name,
               A.sort_order,A.antibody_name,SS.assay_name,
               SI.image_magnification,SI.image_name
      ~;
    } elsif ( $info_key eq 'hidden_cols' ) {
        return ( sort_order => 1, 
                 annotated_image_file => 1  );
# tissue_type_name => 1 );

    }

  }


    if ($table_name eq "IS_antibody") {
        if ($info_key eq "BASICQuery") {
            return qq~
		SELECT antibody_id,antibody_name,antibody_description,comment, sort_order
		  FROM $TBIS_ANTIBODY A
		 WHERE A.record_status!='D'
		 ORDER BY sort_order,antibody_name
            ~;
        }

    }

  
    if ($table_name eq "IS_assay_unit_expression") {
        if ($info_key eq "BASICQuery") {
            return qq~
		SELECT SCP.assay_unit_expression_id,assay_name,structural_unit_name,
                       level_name,abundance_level_name, SCP.comment
                  FROM $TBIS_ASSAY_UNIT_EXPRESSION  SCP
				  LEFT JOIN $TBIS_ASSAY_CHANNEL AC
				  		ON (SCP.ASSAY_CHANNEL_ID = AC.ASSAY_CHANNEL_ID) 
				  LEFT JOIN $TBIS_ASSAY SS
                       ON ( AC.assay_id  = SS.assay_id )
		  LEFT JOIN $TBIS_STRUCTURAL_UNIT CT
		       ON ( SCP.structural_unit_id = CT.structural_unit_id )
		  LEFT JOIN $TBIS_EXPRESSION_LEVEL CPL
		       ON ( SCP.expression_level_id = CPL.expression_level_id )
			LEFT JOIN $TBIS_ABUNDANCE_LEVEL AL
						ON (SCP.abundance_level_id = AL.abundance_level_id) 
		 WHERE SCP.record_status!='D'
		 ORDER BY assay_name,structural_unit_name,level_name
            ~;
			
        }

    }
	
 if ($table_name eq "IS_assay_channel") {
        if ($info_key eq "BASICQuery") {
            return qq~
		SELECT  assay_channel_id, assay_channel_name, assay_name, antibody_name, probe_name, detection_method_name	
		FROM $TBIS_ASSAY_CHANNEL AC 
		LEFT JOIN $TBIS_ASSAY AY ON (AC.assay_id = AY.assay_id)
		LEFT JOIN $TBIS_ANTIBODY AB ON (AC.antibody_id = AB.antibody_id)
		LEFT JOIN $TBIS_PROBE P ON (AC.probe_id = P.probe_id)
		LEFT JOIN $TBIS_DETECTION_METHOD DM ON (AC.detection_method_id = DM.detection_method_id)
		WHERE AC.record_status!='D'
		ORDER BY  AC.assay_channel_name,assay_name
		~;
		}
 	}
###############################################################################

    #### Obtain main SBEAMS object and fall back to its TableInfo handler
    my $sbeams = $self->getSBEAMS();
    my @temp_result = $sbeams->returnTableInfo($table_name,$info_key);
    return @temp_result;

}



###############################################################################
# getParentProject
#
# Return the parent project of a record in a table which might govern
# whether the proposed INSERT or UPDATE function may proceed.
###############################################################################
sub getParentProject {
  my $self = shift;
  my %args = @_;
  my $SUB_NAME = "getParentProject";

  #### Decode the argument list
  my $table_name = $args{'table_name'}
    || die("ERROR: $SUB_NAME: Parameter table_name not passed");
  my $action = $args{'action'}
    || die("ERROR: $SUB_NAME: Parameter action not passed");
  my $parameters_ref = $args{'parameters_ref'}
    || die("ERROR: $SUB_NAME: Parameter parameters_ref not passed");

  #### Make sure action is one of INSERT,UPDATE,DELETE
  unless ($action =~ /^INSERT$|^UPDATE$|^DELETE$/) {
    die("ERROR: $SUB_NAME: action must be one of INSERT,UPDATE,DELETE");
  }

  #### Get sbeams object, needed for Core tables and SQL queries
  my $sbeams = $self->getSBEAMS();

  #### Define the project_id, starting as undef, it gets filled if there is one
  my $project_id;

  #### Check to see if this is a Core table that has project control
  $project_id = $sbeams->getParentProject(
    table_name => $table_name,
    action => $action,
    parameters_ref => $parameters_ref,
  );
  return($project_id) if ($project_id);


  #############################################################################
  #### Process actions for individual tables

  #### If table is xxxx
  if ($table_name eq "xxxx") {

    #### If the user wants to INSERT, determine how it fits into project
    if ($action eq 'INSERT') {

    #### Else for an UPDATE or DELETE, determine how it fits into project
    } elsif ($action eq 'UPDATE' || $action eq 'DELETE') {

    }

    return($project_id) if ($project_id);
  }


  #### No information for this table so return undef
  return;

}



###############################################################################
1;

__END__
###############################################################################
###############################################################################
###############################################################################
