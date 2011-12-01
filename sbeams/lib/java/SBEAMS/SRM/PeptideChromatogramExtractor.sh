#!/bin/bash

USER='PeptideAtlas'

if [ $# -lt 2 ]; then
  echo "$0: Extracts a trace from an mzML file, given a .tsv transition list.
  echo "   Stores result in .txt file of a particular format.
  echo "    <user>, if supplied, is prepended to output filenames."
  echo "    <rt> is retention time; will display on all chromatograms if provided"
  echo "Usage: $0 <transitions.tsv> <spectra.{mzXML,mzML}> [<user>] [<rt>]"
  exit
fi
TRANSITION_FILE=$1
SPECTRA_FILE=$2
if [ $# -ge 3 ]; then
  USER=$3
fi
if [ $# -ge 4 ]; then
  RT=$4
fi

#SBEAMS_ROOT_DIR="/net/dblocal/www/html/devTF/sbeams"
#if [ ! -d $SBEAMS_ROOT_DIR ] ; then
#  SBEAMS_ROOT_DIR="/local/www/html/devTF/sbeams"
#fi

#PA_PERL_HOME="$SBEAMS_ROOT_DIR/lib/scripts/PeptideAtlas"
#PA_JAVA_HOME="$SBEAMS_ROOT_DIR/lib/java/SBEAMS/SRM"

PA_JAVA_HOME=`dirname $0`;  # directory containing this script
if [ ! -d $PA_JAVA_HOME ] ; then
  PA_JAVA_HOME=`echo $PA_JAVA_HOME | sed 's|/net/dblocal|/local|'`
fi
PA_PERL_HOME="$PA_JAVA_HOME/../../../scripts/PeptideAtlas"

echo Java home: $PA_JAVA_HOME
echo Perl home: $PA_PERL_HOME
CONFDIR="$PA_JAVA_HOME"
BINDIR="/serum/analysis/SRM/bin"
JAVA='/tools/java/jdk1.6.0/bin/java'

cd $PA_JAVA_HOME

# Run the PeptideChromatogramExtractor
# Given a transition file and an mzML file,
# produces a .txt file for each distinct mod_pep/charge (?)

# Create the java command string

# expand available memory. If ask for 1G, complains.
JAVA_CMD="$JAVA -Xms500M -Xmx500M"
JAVA_CMD="${JAVA_CMD} -Dbitronix=$CONFDIR/bitronix-default-config.properties"
# 02/22/11: added headless to fix Exception in thread
#"main" java.lang.NoClassDefFoundError: Could not initialize 
# class sun.awt.X11GraphicsEnvironment
# Mi-Youn says that this class is only used when creating graphics,
# and with -WRITER=TEXT we're not creating graphics
JAVA_CMD="${JAVA_CMD} -Djava.awt.headless=true"
JAVA_CMD="${JAVA_CMD} -Dlog4j.configuration=file:$CONFDIR/log4j-procapp.properties"
# libraries used
JAVA_CMD="${JAVA_CMD} -cp $BINDIR/adapter-core-1.2.0.29.jar:$BINDIR/ATAQS.jar:$BINDIR/jai_codec.jar:$BINDIR/jai_core.jar:$BINDIR/jai_codec.jar:$BINDIR/jcommon-1.0.16.jar:$BINDIR/jfreechart-1.0.13.jar:$BINDIR/mysql-connector-java-5.1.7-bin.jar:$BINDIR/aebersoldlab_bitronix995.jar:$BINDIR/aebersoldlab_core1254.jar:$BINDIR/aebersoldlab_javax995.jar:$BINDIR/aebersoldlab_apache995.jar:$BINDIR/aebersoldlab_codehaus995.jar:$BINDIR/aebersoldlab_hibernate995.jar"
# actual core application
JAVA_CMD="${JAVA_CMD} org.systemsbiology.apps.peptideChromatogramExtractor.PeptideChromatogramExtractorApp"
# application params
JAVA_CMD="${JAVA_CMD} -USER=$USER"
JAVA_CMD="${JAVA_CMD} -KEEP_AND_UPDATE_DB=true"
JAVA_CMD="${JAVA_CMD} -OVERWRITE=true"
JAVA_CMD="${JAVA_CMD} -WRITER=TEXT"
JAVA_CMD="${JAVA_CMD} -SMOOTH_TRACE=false"
JAVA_CMD="${JAVA_CMD} -TRANSITION_INPUTS=$TRANSITION_FILE"
JAVA_CMD="${JAVA_CMD} -LCMS_INPUTS=$SPECTRA_FILE"
JAVA_CMD="${JAVA_CMD} -PROJECT=PeptideChromatogram"
JAVA_CMD="${JAVA_CMD} -OUTPUT_DIR=$PA_JAVA_HOME"
JAVA_CMD="${JAVA_CMD} -MOD_FILE=$BINDIR/modifications.xml"
JAVA_CMD="${JAVA_CMD} -instrument=agilent"

# Run the java command  
echo Running $JAVA_CMD
$JAVA_CMD

# These lines used to be in the above call but were removed/replaced
#MBDIR='/serum/analysis/mbrusniak'
#java -Xms1G -Xmx1G \
#-OUTPUT_DIR=/serum/analysis/mbrusniak/MrmToMs2SpectraConverter/TestSet \
#-Dlog4j.configuration=file:/serum/analysis/SRM/conf_test/log4j-procapp.properties \
#-USER=mbrusnia \
#-TRANSITION_INPUTS=$MBDIR/MrmToMs2SpectraConverter/TestSet/AgilentQQQ_K1653-3a-2_1.tsv \
#-LCMS_INPUTS=$MBDIR/MrmToMs2SpectraConverter/TestSet/QQ20100922_K1653-3a-2_1_W1_P3-r001.mzML \

# This clobbers the log files of other PeptideChromatogramExtractor
# processes running simultaneously, so we comment it out.
#rm -f btm*.tlog.*

cd - >& /dev/null
