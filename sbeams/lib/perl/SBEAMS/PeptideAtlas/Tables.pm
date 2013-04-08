package SBEAMS::PeptideAtlas::Tables;

###############################################################################
# Program     : SBEAMS::PeptideAtlas::Tables
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This is part of the SBEAMS::PeptideAtlas module which provides
#               a level of abstraction to the database tables.
#
###############################################################################


use strict;

use SBEAMS::Connection::Settings;


use vars qw(@ISA @EXPORT 
    $TB_ORGANISM
    $TBBL_POLYMER_TYPE

    $TBAT_BIOSEQUENCE_SET
    $TBAT_DBXREF
    $TBAT_BIOSEQUENCE
    $TBAT_BIOSEQUENCE_PROPERTY_SET
    $TBAT_QUERY_OPTION

    $TBAT_ATLAS_BUILD
    $TBAT_DEFAULT_ATLAS_BUILD
    $TBAT_ATLAS_SEARCH_BATCH
    $TBAT_SAMPLE
    $TBAT_ATLAS_BUILD_SAMPLE
    $TBAT_ATLAS_BUILD_SEARCH_BATCH
    $TBAT_PEPTIDE
    $TBAT_PEPTIDE_INSTANCE
    $TBAT_PEPTIDE_INSTANCE_SAMPLE
    $TBAT_PEPTIDE_INSTANCE_SEARCH_BATCH
    $TBAT_MODIFIED_PEPTIDE_INSTANCE
    $TBAT_MODIFIED_PEPTIDE_INSTANCE_SAMPLE
    $TBAT_MODIFIED_PEPTIDE_INSTANCE_SEARCH_BATCH
    $TBAT_PEPTIDE_MAPPING

    $TBAT_PUBLICATION
    $TBAT_BIOSEQUENCE_ANNOTATED_GENE
    $TBAT_BIOSEQUENCE_ANNOTATION
    $TBAT_SWISS_PROT_ANNOTATION
    $TBAT_SAMPLE_PUBLICATION

    $TBAT_IPI_VERSION
    $TBAT_IPI_XREFS
    $TBAT_IPI_DATA
    $TBAT_CELLULAR_LOCATION
    $TBAT_GLYCO_SITE
    $TBAT_IDENTIFIED_PEPTIDE
    $TBAT_PREDICTED_PEPTIDE
    $TBAT_PEPTIDE_TO_TISSUE
    $TBAT_TISSUE_TYPE
    $TBAT_GLYCO_SAMPLE
    $TBAT_IDENTIFIED_TO_IPI
    $TBAT_SYNTHESIZED_PEPTIDE

    $TBAT_SPECTRA_DESCRIPTION_SET
    $TBAT_ATLAS_SEARCH_BATCH_PARAMETER
    $TBAT_ATLAS_SEARCH_BATCH_PARAMETER_SET

    $TBAT_SEARCH_KEY
    $TBAT_SEARCH_KEY_LINK
    $TBAT_SEARCH_KEY_ENTITY

    $TBAT_CONSENSUS_LIBRARY
    $TBAT_CONSENSUS_LIBRARY_SPECTRUM
    $TBAT_CONSENSUS_LIBRARY_SPECTRUM_PEAK
    $TBAT_CONSENSUS_LIBRARY_SPECTRUM_COMMENT
    $TBAT_CONSENSUS_SPECTRUM_TYPE

    $TBAT_NIST_LIBRARY
    $TBAT_NIST_LIBRARY_SPECTRUM
    $TBAT_NIST_LIBRARY_SPECTRUM_PEAK
    $TBAT_NIST_LIBRARY_SPECTRUM_COMMENT
    $TBAT_NIST_SPECTRUM_TYPE

    $TBAT_SPECTRUM_IDENTIFICATION
    $TBAT_SPECTRUM_PTM_IDENTIFICATION
    $TBAT_SPECTRUM
    $TBAT_SPECTRUM_PEAK

    $TBAT_SEARCH_BATCH_STATISTICS

    $TBAT_SPECTRUM_ANNOTATION
    $TBAT_SPECTRUM_ANNOTATION_LEVEL
    $TBAT_PEPTIDE_ANNOTATION
    $TBAT_MODIFIED_PEPTIDE_ANNOTATION
    $TBAT_TRANSITION_SUITABILITY_LEVEL

    $TBAT_SRM_TRANSITION_SET
    $TBAT_SRM_TRANSITION

    $TBAT_PROTEOTYPIC_PEPTIDE
    $TBAT_PROTEOTYPIC_PEPTIDE_MAPPING
    $TBAT_PROTEOTYPIC_PEPTIDE_XSPECIES_MAPPING
    $TBAT_PROTEIN_PRESENCE_LEVEL
    $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE
    $TBAT_PROTEIN_IDENTIFICATION
    $TBAT_BIOSEQUENCE_RELATIONSHIP
    $TBAT_UNIPROT_DB
    $TBAT_UNIPROT_DB_ENTRY

    $TBAT_PABST_PEPTIDE
    $TBAT_PABST_PEPTIDE_MAPPING
    $TBAT_PABST_PEPTIDE_ION
    $TBAT_PABST_PEPTIDE_ION_INSTANCE
    $TBAT_PABST_TRANSITION
    $TBAT_PABST_BUILD
    $TBAT_PABST_BUILD_FILE
    $TBAT_PABST_BUILD_RESOURCE
    $TBAT_PABST_TRANSITION_INSTANCE
    $TBAT_INSTRUMENT_TYPE
    $TBAT_TRANSITION_TYPE
    $TBAT_PABST_SOURCE_PRIORITY
    $TBAT_ELUTION_TIME_TYPE
    $TBAT_ELUTION_TIME

    $TBAT_CHROMATOGRAM_SOURCE_FILE

    $TBAT_PROTEIN_LIST
    $TBAT_PROTEIN_LIST_PROTEIN

    $TBAT_SEL_EXPERIMENT
    $TBAT_SEL_RUN
    $TBAT_SEL_PEPTIDE_ION
    $TBAT_SEL_PEPTIDE_ION_PROTEIN
    $TBAT_SEL_TRANSITION_GROUP
    $TBAT_SEL_TRANSITION
    $TBAT_SEL_CHROMATOGRAM
    $TBAT_SEL_PEAK_GROUP
    $TBAT_QT5500_TRANSITION_GROUP

    $TBAT_PASS_SUBMITTER
    $TBAT_PASS_DATASET

    $TBAT_PUTATIVE_PROTEIN
    $TBAT_PUTATIVE_PEPTIDE
    $TBAT_PUTATIVE_PROTEIN_PEPTIDE
    $TBAT_PEPTIDE_INSTANCE_ANNOTATION
    $TBAT_PROTEIN_IDENTIFICATION_ANNOTATION

);


require Exporter;
@ISA = qw (Exporter);

@EXPORT = qw (
    $TB_ORGANISM
    $TBBL_POLYMER_TYPE

    $TBAT_BIOSEQUENCE_SET
    $TBAT_DBXREF
    $TBAT_BIOSEQUENCE
    $TBAT_BIOSEQUENCE_PROPERTY_SET
    $TBAT_QUERY_OPTION

    $TBAT_ATLAS_BUILD
    $TBAT_DEFAULT_ATLAS_BUILD
    $TBAT_ATLAS_SEARCH_BATCH
    $TBAT_SAMPLE
    $TBAT_ATLAS_BUILD_SAMPLE
    $TBAT_ATLAS_BUILD_SEARCH_BATCH
    $TBAT_PEPTIDE
    $TBAT_PEPTIDE_INSTANCE
    $TBAT_PEPTIDE_INSTANCE_SAMPLE
    $TBAT_PEPTIDE_INSTANCE_SEARCH_BATCH
    $TBAT_MODIFIED_PEPTIDE_INSTANCE
    $TBAT_ATLAS_SEARCH_BATCH
    $TBAT_SAMPLE
    $TBAT_ATLAS_BUILD_SAMPLE
    $TBAT_ATLAS_BUILD_SEARCH_BATCH
    $TBAT_PEPTIDE
    $TBAT_PEPTIDE_INSTANCE
    $TBAT_PEPTIDE_INSTANCE_SAMPLE
    $TBAT_PEPTIDE_INSTANCE_SEARCH_BATCH
    $TBAT_MODIFIED_PEPTIDE_INSTANCE
    $TBAT_MODIFIED_PEPTIDE_INSTANCE_SAMPLE
    $TBAT_MODIFIED_PEPTIDE_INSTANCE_SEARCH_BATCH
    $TBAT_PEPTIDE_MAPPING

    $TBAT_PUBLICATION
    $TBAT_BIOSEQUENCE_ANNOTATED_GENE
    $TBAT_BIOSEQUENCE_ANNOTATION
    $TBAT_SWISS_PROT_ANNOTATION
    $TBAT_SAMPLE_PUBLICATION

    $TBAT_IPI_VERSION
    $TBAT_IPI_XREFS
    $TBAT_IPI_DATA
    $TBAT_CELLULAR_LOCATION
    $TBAT_GLYCO_SITE
    $TBAT_IDENTIFIED_PEPTIDE
    $TBAT_PREDICTED_PEPTIDE
    $TBAT_PEPTIDE_TO_TISSUE
    $TBAT_TISSUE_TYPE
    $TBAT_GLYCO_SAMPLE
    $TBAT_IDENTIFIED_TO_IPI
    $TBAT_SYNTHESIZED_PEPTIDE

    $TBAT_SPECTRA_DESCRIPTION_SET
    $TBAT_ATLAS_SEARCH_BATCH_PARAMETER
    $TBAT_ATLAS_SEARCH_BATCH_PARAMETER_SET

    $TBAT_SEARCH_KEY
    $TBAT_SEARCH_KEY_LINK
    $TBAT_SEARCH_KEY_ENTITY

    $TBAT_CONSENSUS_LIBRARY
    $TBAT_CONSENSUS_LIBRARY_SPECTRUM
    $TBAT_CONSENSUS_LIBRARY_SPECTRUM_PEAK
    $TBAT_CONSENSUS_LIBRARY_SPECTRUM_COMMENT
    $TBAT_CONSENSUS_SPECTRUM_TYPE

    $TBAT_NIST_LIBRARY
    $TBAT_NIST_LIBRARY_SPECTRUM
    $TBAT_NIST_LIBRARY_SPECTRUM_PEAK
    $TBAT_NIST_LIBRARY_SPECTRUM_COMMENT
    $TBAT_NIST_SPECTRUM_TYPE

    $TBAT_SPECTRUM_IDENTIFICATION
    $TBAT_SPECTRUM_PTM_IDENTIFICATION
    $TBAT_SPECTRUM
    $TBAT_SPECTRUM_PEAK
    $TBAT_SEARCH_BATCH_STATISTICS

    $TBAT_SPECTRUM_ANNOTATION
    $TBAT_SPECTRUM_ANNOTATION_LEVEL
    $TBAT_PEPTIDE_ANNOTATION
    $TBAT_MODIFIED_PEPTIDE_ANNOTATION
    $TBAT_TRANSITION_SUITABILITY_LEVEL

    $TBAT_SRM_TRANSITION_SET
    $TBAT_SRM_TRANSITION

    $TBAT_PROTEOTYPIC_PEPTIDE
    $TBAT_PROTEOTYPIC_PEPTIDE_MAPPING
    $TBAT_PROTEOTYPIC_PEPTIDE_XSPECIES_MAPPING
    $TBAT_PROTEIN_PRESENCE_LEVEL
    $TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE
    $TBAT_PROTEIN_IDENTIFICATION
    $TBAT_BIOSEQUENCE_RELATIONSHIP
    $TBAT_UNIPROT_DB
    $TBAT_UNIPROT_DB_ENTRY

    $TBAT_PABST_PEPTIDE
    $TBAT_PABST_PEPTIDE_MAPPING
    $TBAT_PABST_PEPTIDE_ION
    $TBAT_PABST_PEPTIDE_ION_INSTANCE
    $TBAT_PABST_TRANSITION
    $TBAT_PABST_BUILD
    $TBAT_PABST_BUILD_RESOURCE
    $TBAT_PABST_BUILD_FILE
    $TBAT_PABST_TRANSITION_INSTANCE
    $TBAT_INSTRUMENT_TYPE
    $TBAT_TRANSITION_TYPE
    $TBAT_PABST_SOURCE_PRIORITY
    $TBAT_ELUTION_TIME_TYPE
    $TBAT_ELUTION_TIME
    $TBAT_CHROMATOGRAM_SOURCE_FILE

    $TBAT_PROTEIN_LIST
    $TBAT_PROTEIN_LIST_PROTEIN

    $TBAT_SEL_EXPERIMENT
    $TBAT_SEL_RUN
    $TBAT_SEL_PEPTIDE_ION
    $TBAT_SEL_PEPTIDE_ION_PROTEIN
    $TBAT_SEL_TRANSITION_GROUP
    $TBAT_SEL_TRANSITION
    $TBAT_SEL_CHROMATOGRAM
    $TBAT_SEL_PEAK_GROUP
    $TBAT_QT5500_TRANSITION_GROUP

    $TBAT_PASS_SUBMITTER
    $TBAT_PASS_DATASET

    $TBAT_PUTATIVE_PROTEIN
    $TBAT_PUTATIVE_PEPTIDE
    $TBAT_PUTATIVE_PROTEIN_PEPTIDE
    $TBAT_PEPTIDE_INSTANCE_ANNOTATION
    $TBAT_PROTEIN_IDENTIFICATION_ANNOTATION
);


#### Get the appropriate database prefixes for the SBEAMS core and this module
my $core = $DBPREFIX{Core};
my $mod = $DBPREFIX{PeptideAtlas};
my $prodmod = 'peptideatlas.dbo.';
my $test_mod = $DBPREFIX{PeptideAtlasTest} || $DBPREFIX{PeptideAtlas};
my $glycomod = $DBPREFIX{GlycoPeptide} || $DBPREFIX{PeptideAtlas};
my $BioLink = $DBPREFIX{BioLink};

$TB_ORGANISM                = "${core}organism";
$TBBL_POLYMER_TYPE          = "${BioLink}polymer_type";

$TBAT_BIOSEQUENCE_SET       = "${mod}biosequence_set";
$TBAT_DBXREF                = "${BioLink}dbxref";
$TBAT_BIOSEQUENCE           = "${mod}biosequence";
$TBAT_BIOSEQUENCE_PROPERTY_SET = "${mod}biosequence_property_set";
$TBAT_QUERY_OPTION          = "${mod}query_option";

$TBAT_ATLAS_BUILD           = "${mod}atlas_build";
$TBAT_DEFAULT_ATLAS_BUILD   = "${mod}default_atlas_build";
$TBAT_ATLAS_SEARCH_BATCH    = "${mod}atlas_search_batch";
$TBAT_SAMPLE                = "${mod}sample";
$TBAT_ATLAS_BUILD_SAMPLE    = "${mod}atlas_build_sample";
$TBAT_ATLAS_BUILD_SEARCH_BATCH  = "${mod}atlas_build_search_batch";
$TBAT_PEPTIDE               = "${mod}peptide";
$TBAT_PEPTIDE_INSTANCE      = "${mod}peptide_instance";
$TBAT_PEPTIDE_INSTANCE_SAMPLE  = "${mod}peptide_instance_sample";
$TBAT_PEPTIDE_INSTANCE_SEARCH_BATCH  = "${mod}peptide_instance_search_batch";
$TBAT_MODIFIED_PEPTIDE_INSTANCE    = "${mod}modified_peptide_instance";
$TBAT_MODIFIED_PEPTIDE_INSTANCE_SAMPLE  = "${mod}modified_peptide_instance_sample";
$TBAT_MODIFIED_PEPTIDE_INSTANCE_SEARCH_BATCH  = "${mod}modified_peptide_instance_search_batch";
$TBAT_PEPTIDE_MAPPING       = "${mod}peptide_mapping";

$TBAT_PUBLICATION           = "${mod}publication";
$TBAT_BIOSEQUENCE_ANNOTATED_GENE = "${mod}biosequence_annotated_gene";
$TBAT_BIOSEQUENCE_ANNOTATION = "${mod}biosequence_annotation";
$TBAT_SWISS_PROT_ANNOTATION = "${mod}swiss_prot_annotation";
$TBAT_SAMPLE                = "${mod}sample";
$TBAT_SAMPLE_PUBLICATION    = "${mod}sample_publication";

$TBAT_IPI_VERSION	    	= "PeptideAtlas_test.dbo.ipi_version";
$TBAT_IPI_XREFS	    	= "PeptideAtlas_test.dbo.ipi_xrefs";
$TBAT_IPI_DATA			= "${glycomod}ipi_data";
$TBAT_CELLULAR_LOCATION		= "${glycomod}cellular_location";
$TBAT_GLYCO_SITE		= "${glycomod}glyco_site";
$TBAT_IDENTIFIED_PEPTIDE	= "${glycomod}identified_peptide";
$TBAT_PREDICTED_PEPTIDE		= "${glycomod}predicted_peptide";
$TBAT_PEPTIDE_TO_TISSUE		= "${glycomod}peptide_to_tissue";
$TBAT_TISSUE_TYPE			= "${glycomod}tissue_type";
$TBAT_IDENTIFIED_TO_IPI= "${glycomod}identified_to_ipi";
$TBAT_GLYCO_SAMPLE   = "${glycomod}glyco_sample";
$TBAT_SYNTHESIZED_PEPTIDE	= "${glycomod}synthesized_peptide";

$TBAT_SPECTRA_DESCRIPTION_SET = "${mod}spectra_description_set";
$TBAT_ATLAS_SEARCH_BATCH_PARAMETER = "${mod}atlas_search_batch_parameter";
$TBAT_ATLAS_SEARCH_BATCH_PARAMETER_SET = "${mod}atlas_search_batch_parameter_set";

$TBAT_SEARCH_KEY                = "${mod}search_key";
$TBAT_SEARCH_KEY_LINK           = "${mod}search_key_link";
$TBAT_SEARCH_KEY_ENTITY         = "${mod}search_key_entity";

$TBAT_CONSENSUS_LIBRARY                   = "${mod}consensus_library";
$TBAT_CONSENSUS_LIBRARY_SPECTRUM          = "${mod}consensus_library_spectrum";
$TBAT_CONSENSUS_LIBRARY_SPECTRUM_PEAK     = "${mod}consensus_library_spectrum_peak";
$TBAT_CONSENSUS_LIBRARY_SPECTRUM_COMMENT  = "${mod}consensus_library_spectrum_comment";
$TBAT_CONSENSUS_SPECTRUM_TYPE             = "${mod}consensus_spectrum_type";

$TBAT_NIST_LIBRARY                   = "${mod}consensus_library";
$TBAT_NIST_LIBRARY_SPECTRUM          = "${mod}consensus_library_spectrum";
$TBAT_NIST_LIBRARY_SPECTRUM_PEAK     = "${mod}consensus_library_spectrum_peak";
$TBAT_NIST_LIBRARY_SPECTRUM_COMMENT  = "${mod}consensus_library_spectrum_comment";
$TBAT_NIST_SPECTRUM_TYPE             = "${mod}consensus_spectrum_type";

##$TBAT_SEARCH_BATCH_STATISTICS   = "glycopeptide.dbo.search_batch_statistics";
$TBAT_SEARCH_BATCH_STATISTICS   = "${mod}search_batch_statistics";

$TBAT_SPECTRUM_IDENTIFICATION    = "${mod}spectrum_identification";
$TBAT_SPECTRUM_PTM_IDENTIFICATION    = "${mod}spectrum_ptm_identification";
$TBAT_SPECTRUM                   = "${mod}spectrum";
$TBAT_SPECTRUM_PEAK              = "${mod}spectrum_peak";

$TBAT_SPECTRUM_ANNOTATION           = "${mod}spectrum_annotation";
$TBAT_SPECTRUM_ANNOTATION_LEVEL     = "${mod}spectrum_annotation_level";
$TBAT_PEPTIDE_ANNOTATION            = "${mod}peptide_annotation";

#$TBAT_MODIFIED_PEPTIDE_ANNOTATION   = "${testmod}modified_peptide_annotation";
#$TBAT_TRANSITION_SUITABILITY_LEVEL  = "${testmod}transition_suitability_level";

$TBAT_MODIFIED_PEPTIDE_ANNOTATION   = "${mod}modified_peptide_annotation";
$TBAT_TRANSITION_SUITABILITY_LEVEL  = "${mod}transition_suitability_level";

$TBAT_SRM_TRANSITION_SET            = "${mod}srm_transition_set";
$TBAT_SRM_TRANSITION            = "${mod}srm_transition";

$TBAT_PROTEOTYPIC_PEPTIDE           = "${mod}proteotypic_peptide";
$TBAT_PROTEOTYPIC_PEPTIDE_MAPPING   = "${mod}proteotypic_peptide_mapping";
$TBAT_PROTEOTYPIC_PEPTIDE_XSPECIES_MAPPING  = "${mod}proteotypic_peptide_xspecies_mapping";

#$TBAT_PROTEOTYPIC_PEPTIDE           = "peptideatlas_test.dbo.proteotypic_peptide_test";
#$TBAT_PROTEOTYPIC_PEPTIDE_MAPPING   = "peptideatlas_test.dbo.proteotypic_peptide_mapping";

$TBAT_PROTEIN_PRESENCE_LEVEL        = "${mod}protein_presence_level";
$TBAT_BIOSEQUENCE_RELATIONSHIP_TYPE = "${mod}biosequence_relationship_type";
$TBAT_PROTEIN_IDENTIFICATION        = "${mod}protein_identification";
$TBAT_BIOSEQUENCE_RELATIONSHIP      = "${mod}biosequence_relationship";
$TBAT_UNIPROT_DB                    = "${mod}uniprot_db";
$TBAT_UNIPROT_DB_ENTRY              = "${mod}uniprot_db_entry";

$TBAT_PABST_PEPTIDE                 = "${mod}pabst_tmp_peptide";
$TBAT_PABST_PEPTIDE_MAPPING         = "${mod}pabst_tmp_peptide_mapping";
$TBAT_PABST_PEPTIDE_ION             = "${mod}pabst_tmp_peptide_ion";
$TBAT_PABST_PEPTIDE_ION_INSTANCE    = "${mod}pabst_tmp_peptide_ion_instance";
$TBAT_PABST_TRANSITION              = "${mod}pabst_tmp_transition";
$TBAT_PABST_BUILD                   = "${mod}pabst_tmp_build";
$TBAT_PABST_BUILD_RESOURCE          = "${mod}pabst_build_resource";
$TBAT_PABST_BUILD_FILE              = "${mod}pabst_tmp_build_file";
$TBAT_PABST_TRANSITION_INSTANCE     = "${mod}pabst_tmp_transition_instance";
$TBAT_INSTRUMENT_TYPE               = "${mod}instrument_type";
$TBAT_TRANSITION_TYPE               = "${mod}transition_type";
$TBAT_PABST_SOURCE_PRIORITY         = "${mod}pabst_tmp_source_priority";
$TBAT_ELUTION_TIME_TYPE             = "${mod}elution_time_type";
$TBAT_ELUTION_TIME                  = "${mod}elution_time";
$TBAT_CHROMATOGRAM_SOURCE_FILE      = "${mod}chromatogram_source_file";

$TBAT_PROTEIN_LIST                  = "${mod}protein_list";
$TBAT_PROTEIN_LIST_PROTEIN          = "${mod}protein_list_protein";

$TBAT_SEL_EXPERIMENT                = "${mod}SEl_experiment";
$TBAT_SEL_RUN                       = "${mod}SEL_run";
$TBAT_SEL_PEPTIDE_ION               = "${mod}SEL_peptide_ion";
$TBAT_SEL_PEPTIDE_ION_PROTEIN       = "${mod}SEL_peptide_ion_protein";
$TBAT_SEL_TRANSITION_GROUP          = "${mod}SEL_transition_group";
$TBAT_SEL_TRANSITION                = "${mod}SEL_transition";
$TBAT_SEL_CHROMATOGRAM              = "${mod}SEL_chromatogram";
$TBAT_SEL_PEAK_GROUP                = "${mod}SEL_peak_group";
$TBAT_QT5500_TRANSITION_GROUP       = "${mod}QT5500_transition_group";

$TBAT_PASS_SUBMITTER                = "${mod}PASS_submitter";
$TBAT_PASS_DATASET                  = "${mod}PASS_dataset";

$TBAT_PUTATIVE_PROTEIN              = "${mod}putative_protein";
$TBAT_PUTATIVE_PEPTIDE              = "${mod}putative_peptide";
$TBAT_PUTATIVE_PROTEIN_PEPTIDE      = "${mod}putative_protein_peptide";
$TBAT_PEPTIDE_INSTANCE_ANNOTATION   = "${mod}peptide_instance_annotation";
$TBAT_PROTEIN_IDENTIFICATION_ANNOTATION   = "${mod}protein_identification_annotation";
