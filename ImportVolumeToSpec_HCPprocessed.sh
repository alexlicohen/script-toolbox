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
T2wImage=`opts_GetOpt1 "--inputvolume" $@` #T2w/DIR or other image already registered to T1 used as HCP Pipelines/Freesurfer input
T2shortname=`opts_GetOpt1 "--inputname" $@` #what prefix/suffix to add to new files (if using T2 images, this could be T2w, etc...)

# hardcoded parameters
HighResMesh="164"
LowResMeshes="32"

T1wFolder="$StudyFolder"/"$Subject"/T1w
AtlasSpaceFolder="$StudyFolder"/"$Subject"/MNINonLinear


# The HCP code uses fslreorient2std at the beginning... I assume we'll need to apply that rotation too? (otherwise just skip it)
fslreorient2std "$StudyFolder"/"$Subject"/unprocessed/3T/T1w_MPR1/"$Subject"_3T_T1w_MPR1.nii.gz > "$T1wFolder"/xfms/"$T2shortname"scanner2std.mat
${FSLDIR}/bin/applywarp -i "$T2wImage" -r "$T1wFolder"/T1w.nii.gz --premat="$T1wFolder"/xfms/"$T2shortname"scanner2std.mat -o "$StudyFolder"/"$Subject"/T1w/"$T2shortname"_std


T2wImage="$StudyFolder"/"$Subject"/T1w/"$T2shortname"_std.nii.gz

# Convert Contrast Volume to "Native" acpc space with rigid body 6 DOF transform
${FSLDIR}/bin/applywarp -i "$T2wImage" -r "$T1wFolder"/T1w_acpc_dc_restore.nii.gz --premat="$T1wFolder"/xfms/acpc.mat --rel --interp=spline -o "$T1wFolder"/"$T2shortname"_acpc_xfmd.nii.gz

# Add volume files to "Native" spec file
${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/Native/"$Subject".native.wb.spec INVALID "$T1wFolder"/"$T2shortname"_acpc_xfmd.nii.gz

# Use transform from Original T1w-space to HCP "Native" space, then apply to Contrast Volume along with warp
${FSLDIR}/bin/applywarp -i "$T2wImage" -r "${HCPPIPEDIR_Templates}"/MNI152_T1_0.7mm.nii.gz --premat="$T1wFolder"/xfms/acpc.mat -w "${AtlasSpaceFolder}/xfms/acpc_dc2standard.nii.gz" --rel --interp=spline -o "$AtlasSpaceFolder"/"$T2shortname"_MNI_xfmd.nii.gz


# Add volume files to "MNIspace" spec files
${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/Native/"$Subject".native.wb.spec INVALID "$AtlasSpaceFolder"/"$T2shortname"_MNI_xfmd.nii.gz
${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec INVALID "$AtlasSpaceFolder"/"$T2shortname"_MNI_xfmd.nii.gz

for LowResMesh in ${LowResMeshes} ; do
  ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID "$AtlasSpaceFolder"/"$T2shortname"_MNI_xfmd.nii.gz
  ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID "$T1wFolder"/"$T2shortname"_acpc_xfmd.nii.gz
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
		${CARET7DIR}/wb_command -volume-to-surface-mapping "$T1wFolder"/"$T2shortname"_acpc_xfmd.nii.gz "$T1wFolder"/Native/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$T1wFolder"/Native/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii -trilinear

		${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/Native/"$Subject".native.wb.spec $Structure "$T1wFolder"/Native/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii
		${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/Native/"$Subject".native.wb.spec $Structure "$T1wFolder"/Native/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii

		# resample data to the hires surface atlas mesh
		${CARET7DIR}/wb_command -metric-resample "$T1wFolder"/Native/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii  "${AtlasSpaceFolder}/Native/${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii" "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$HighResMesh"k_fs_LR.func.gii -area-surfs "$T1wFolder"/Native/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Surface"."$HighResMesh"k_fs_LR.surf.gii

		# add it to the spec file
		${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$HighResMesh"k_fs_LR.func.gii

		for LowResMesh in ${LowResMeshes} ; do
			${CARET7DIR}/wb_command -metric-resample "$T1wFolder"/Native/"$Subject"."$Hemisphere"."$Surface"."$T2shortname".native.func.gii "${AtlasSpaceFolder}/Native/${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii" "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$LowResMesh"k_fs_LR.func.gii -area-surfs "$T1wFolder"/Native/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii

			${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$LowResMesh"k_fs_LR.func.gii
  			${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$T2shortname"."$LowResMesh"k_fs_LR.func.gii
		done
	done
done


log_Msg "Completed"
