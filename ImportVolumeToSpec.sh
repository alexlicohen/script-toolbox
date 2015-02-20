#!/bin/bash
set -e
#set -x

# Requirements for this script
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP), wb_command
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR

# Author: Alex Cohen, adapted from HCP Pipelines code, last edit 12/21/14

# --------------------------------------------------------------------------------
#  Load Function Libraries
# --------------------------------------------------------------------------------

source $HCPPIPEDIR/global/scripts/log.shlib  # Logging related functions
source $HCPPIPEDIR/global/scripts/opts.shlib # Command line option functions

########################################## SUPPORT FUNCTIONS ##########################################

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

show_usage() {
    echo "This takes a nifti volume and does surface intersections with a FS->HCP spec file"
    echo "  Inputs:"
    echo "    --subject=fc_12345"
    echo "    --inputvolume=/absolute/path/to/contrast_volume.nii.gz"
    echo "    --inputname=DIR or FLAIR, etc..."
    echo "    --layers=corticallayer_0.66@corticallayer_0.33@subcortlayer_mm_1  which surfaces to project to"
    echo "   	  choices for layers include:"
    echo "   								 pial"
    echo "   								 midthickness"
    echo "   								 white"
    echo "   								 corticallayer_0.25  (if you made one...)"
    echo "   								 subcortlayer_mm_1.5 (if you made one...)"
    echo "   [--path=/blah/blah/blah]  if not specified, assumes pwd"
    echo "   [--onefile=name_of_output_metric]  specify if you would like an combined ASCII file output"
    exit 1
}

defaultopt() {
    echo $1
}

# --------------------------------------------------------------------------------
#   Establish tool name for logging
# --------------------------------------------------------------------------------
log_SetToolName "ImportContrastVolumeToSpec.sh"

################################################## OPTION PARSING #####################################################

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
    show_usage
fi

log_Msg "Parsing Command Line Options"

# Input Variables
StudyFolder=`opts_GetOpt1 "--path" $@`
Subject=`opts_GetOpt1 "--subject" $@`
Layers=`opts_GetOpt1 "--layers" $@`
T2wImage=`opts_GetOpt1 "--inputvolume" $@` #T2w, DIR or other image already registered to T1 used as HCP Pipelines/Freesurfer input
T2shortname=`opts_GetOpt1 "--inputname" $@` #what prefix/suffix to add to new files (if using T2 images, this could be T2w, etc...)
Onefile=`opts_GetOpt1 "--onefile" $@`

#Initializing Variables with Default Values if not otherwise specified
WD="`pwd`"
StudyFolder=`defaultopt $StudyFolder $WD`
Onefile=`defaultopt $Onefile ""`

# hardcoded parameters
HighResMesh="164"
LowResMesh="32"

HCPFolder="$StudyFolder"/"$Subject"/hcp


# The HCP code uses fslreorient2std at the beginning... I assume we'll need to apply that rotation too? (otherwise just skip it)
fslreorient2std "$T2wImage" "$HCPFolder"/"$T2shortname".nii.gz

T2wImage="$HCPFolder"/"$T2shortname".nii.gz

# Add volume files to spec files
${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject".native.wb.spec INVALID "$T2wImage"
${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec INVALID "$T2wImage"
${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID "$T2wImage"

# Loop through left and right hemispheres
for Hemisphere in L R ; do
	# Set a bunch of different ways of saying left and right
	if [ $Hemisphere = "L" ] ; then
		hemisphere="l"
		Structure="CORTEX_LEFT"
	elif [ $Hemisphere = "R" ] ; then
		hemisphere="r"
		Structure="CORTEX_RIGHT"
	fi

	# Loop through the surfaces
	LayersList=`echo ${Layers} | sed 's/@/ /g'`
	for Surface in $LayersList; do

		# sample the volume using each surface (alternatively could use the ribbon or myelin techniques, but for now, just use trilinear...)
		${CARET7DIR}/wb_command -volume-to-surface-mapping "$T2wImage" "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii -trilinear

		${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject".native.wb.spec $Structure "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii

		# resample data to the hires surface atlas mesh
		${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii  "$HCPFolder"/"${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii" "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$HighResMesh"k_fs_LR.func.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$HighResMesh"k_fs_LR.surf.gii

		# add it to the spec files
		${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$HighResMesh"k_fs_LR.func.gii

		${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii "$HCPFolder"/"${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii" "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$LowResMesh"k_fs_LR.func.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
		${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$LowResMesh"k_fs_LR.func.gii
	done
done

 if [ ! -z "$onefile" ] ; then
 	echo "Creating single ASCII #.func.gii output for analysis"
 	for Hemisphere in L R ; do
	# Set a bunch of different ways of saying left and right
	if [ $Hemisphere = "L" ] ; then
		hemisphere="l"
		Structure="CORTEX_LEFT"
	elif [ $Hemisphere = "R" ] ; then
		hemisphere="r"
		Structure="CORTEX_RIGHT"
	fi

	# Generate list of metrics to merge
	for SurfaceSet in native "$HighResMesh"k_fs_LR ; do
		rm "$HCPFolder"/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.info.txt #2> /dev/null
		MetricList="-metric "
		for Layer in $LayersList ; do
			echo -metric "$HCPFolder"/"$Subject"."$Hemisphere"."$Layer".$T2shortname.$SurfaceSet.func.gii >> "$HCPFolder"/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.info.txt
		done
		wb_command -metric-merge "$HCPFolder"/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.func.gii `cat "$HCPFolder"/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.info.txt`
		wb_command -gifti-convert ASCII "$HCPFolder"/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.func.gii "$HCPFolder"/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.func.gii
	done
	# Make the Low-rez set too
	for SurfaceSet in "$LowResMesh"k_fs_LR ; do
		rm "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.info.txt #2> /dev/null
		MetricList="-metric "
		for Layer in $LayersList ; do
			echo -metric "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Layer".$T2shortname.$SurfaceSet.func.gii >> "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.info.txt
		done
		wb_command -metric-merge "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.func.gii `cat "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.info.txt`
		wb_command -gifti-convert ASCII "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.func.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$T2shortname"."$SurfaceSet".onefile.func.gii
	done



log_Msg "Completed"
