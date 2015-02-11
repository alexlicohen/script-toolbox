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
    echo "Usage information To Be Written"
    exit 1
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
InputVolume=`opts_GetOpt1 "--source" $@` # The original volume used to run freesurfer with, used for orientation and reslicing, if needed.
T2wImage=`opts_GetOpt1 "--inputvolume" $@` #T2w, DIR or other image already registered to T1 used as HCP Pipelines/Freesurfer input
T2shortname=`opts_GetOpt1 "--inputname" $@` #what prefix/suffix to add to new files (if using T2 images, this could be T2w, etc...)

# hardcoded parameters
HighResMesh="164"
LowResMeshes="32"

HCPFolder="$StudyFolder"/"$Subject"/hcp


# The HCP code uses fslreorient2std at the beginning... I assume we'll need to apply that rotation too? (otherwise just skip it)
fslreorient2std "$T2wImage" "$HCPFolder"/"$T2shortname".nii.gz

T2wImage="$HCPFolder"/"$T2shortname".nii.gz

# Add volume files to spec files
${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject".native.wb.spec INVALID "$T2wImage"
${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec INVALID "$T2wImage"

for LowResMesh in ${LowResMeshes} ; do
  ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID "$T2wImage"
done


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

	# Loop through the surfaces, we could add more...
	Types="ANATOMICAL@GRAY_WHITE ANATOMICAL@MIDTHICKNESS ANATOMICAL@PIAL"
	#Types="ANATOMICAL@MIDTHICKNESS"
	i=1
	for Surface in white midthickness pial ; do
	#for Surface in midthickness ; do
		Type=`echo "$Types" | cut -d " " -f $i`
		Secondary=`echo "$Type" | cut -d "@" -f 2`
		Type=`echo "$Type" | cut -d "@" -f 1`
		if [ ! $Secondary = $Type ] ; then
			Secondary=`echo " -surface-secondary-type ""$Secondary"`
		else
			Secondary=""
		fi

		# sample the volume using each surface (alternatively could use the ribbon or myelin techniques, but for now, just use trilinear...)
		${CARET7DIR}/wb_command -volume-to-surface-mapping "$T2wImage" "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii -trilinear

		${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject".native.wb.spec $Structure "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii

		# resample data to the hires surface atlas mesh
		${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii  "$HCPFolder"/"${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii" "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$HighResMesh"k_fs_LR.func.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$HighResMesh"k_fs_LR.surf.gii

		# add it to the spec file
		${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$HighResMesh"k_fs_LR.func.gii

		for LowResMesh in ${LowResMeshes} ; do
			${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii "$HCPFolder"/"${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii" "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$LowResMesh"k_fs_LR.func.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii

			${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$LowResMesh"k_fs_LR.func.gii
		done
	done
done


log_Msg "Completed"
