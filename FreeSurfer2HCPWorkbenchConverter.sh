#!/bin/bash
set -e
#set -x

# Requirements for this script
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP), wb_command
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR

# Author: Alex Cohen, adapted from HCP Pipelines code, last edit 01/21/15

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
    echo "For now this just makes a sub-dir and creates all of the HCP .spec file contents from the FreeSurfer output"
    echo "needs two inputs in the style of: --path=/blah/blah/ --subject=99-999-999"
    exit 1
}

# --------------------------------------------------------------------------------
#   Establish tool name for logging
# --------------------------------------------------------------------------------
log_SetToolName "FreeSurfer2HCPWorkbenchConverter.sh"

################################################## OPTION PARSING #####################################################

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
    show_usage
fi

log_Msg "Parsing Command Line Options"

# Input Variables
StudyFolder=`opts_GetOpt1 "--path" $@`
Subject=`opts_GetOpt1 "--subject" $@`

FreeSurferFolder="$StudyFolder"/"$Subject"

# Hardcoded parameters
HCPFolder="$FreeSurferFolder"/hcp
FreeSurferLabels="${HCPPIPEDIR_Config}/FreeSurferAllLut.txt"
SurfaceAtlasDIR="${HCPPIPEDIR_Templates}/standard_mesh_atlases"
HighResMesh="164"
LowResMeshes="32"
RegName="FS"
GrayordinatesSpaceDIR="${HCPPIPEDIR_Templates}/91282_Greyordinates"

# Make output folder
if [ ! -e "$HCPFolder" ] ; then
  mkdir -p "$HCPFolder"
fi


#Find c_ras offset between FreeSurfer surface and volume and generate matrix to transform surfaces
MatrixX=`mri_info "$FreeSurferFolder"/mri/brain.finalsurfs.mgz | grep "c_r" | cut -d "=" -f 5 | sed s/" "/""/g`
MatrixY=`mri_info "$FreeSurferFolder"/mri/brain.finalsurfs.mgz | grep "c_a" | cut -d "=" -f 5 | sed s/" "/""/g`
MatrixZ=`mri_info "$FreeSurferFolder"/mri/brain.finalsurfs.mgz | grep "c_s" | cut -d "=" -f 5 | sed s/" "/""/g`
echo "1 0 0 ""$MatrixX" > "$FreeSurferFolder"/mri/c_ras.mat
echo "0 1 0 ""$MatrixY" >> "$FreeSurferFolder"/mri/c_ras.mat
echo "0 0 1 ""$MatrixZ" >> "$FreeSurferFolder"/mri/c_ras.mat
echo "0 0 0 1" >> "$FreeSurferFolder"/mri/c_ras.mat


#Convert FreeSurfer Volumes
for Image in wmparc aparc.a2009s+aseg aparc+aseg ; do
  if [ -e "$FreeSurferFolder"/mri/"$Image".mgz ] ; then
    mri_convert -ot nii "$FreeSurferFolder"/mri/"$Image".mgz "$HCPFolder"/"$Image".nii.gz
    fslreorient2std "$HCPFolder"/"$Image".nii.gz "$HCPFolder"/"$Image".nii.gz
    ${CARET7DIR}/wb_command -volume-label-import "$HCPFolder"/"$Image".nii.gz "$FreeSurferLabels" "$HCPFolder"/"$Image".nii.gz -drop-unused-labels
  fi
done

#Add Anatomical Volumes
for Image in rawavg T1 ; do
  if [ -e "$FreeSurferFolder"/mri/"$Image".mgz ] ; then
    mri_convert -ot nii "$FreeSurferFolder"/mri/"$Image".mgz "$HCPFolder"/"$Image".nii.gz
    fslreorient2std "$HCPFolder"/"$Image".nii.gz "$HCPFolder"/"$Image".nii.gz
    pushd "$HCPFolder"
    	${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject".native.wb.spec INVALID ./"$Image".nii.gz
    	${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec INVALID ./"$Image".nii.gz
    popd "$HCPFolder"/fsaverage_LR"$LowResMesh"k
    	${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID ../"$Image".nii.gz
    pushd 
  fi
done

#Loop through left and right hemispheres
for Hemisphere in L R ; do
  #Set a bunch of different ways of saying left and right
  if [ $Hemisphere = "L" ] ; then
    hemisphere="l"
    Structure="CORTEX_LEFT"
  elif [ $Hemisphere = "R" ] ; then
    hemisphere="r"
    Structure="CORTEX_RIGHT"
  fi

  #native Mesh Processing
  #Convert and volumetrically register white and pial surfaces makign linear and nonlinear copies, add each to the appropriate spec file
  Types="ANATOMICAL@GRAY_WHITE ANATOMICAL@PIAL"
  i=1
  for Surface in white pial ; do
    Type=`echo "$Types" | cut -d " " -f $i`
    Secondary=`echo "$Type" | cut -d "@" -f 2`
    Type=`echo "$Type" | cut -d "@" -f 1`
    if [ ! $Secondary = $Type ] ; then
      Secondary=`echo " -surface-secondary-type ""$Secondary"`
    else
      Secondary=""
    fi
    mris_convert "$FreeSurferFolder"/surf/"$hemisphere"h."$Surface" "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii
    ${CARET7DIR}/wb_command -set-structure "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${Structure} -surface-type $Type$Secondary
    ${CARET7DIR}/wb_command -surface-apply-affine "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$FreeSurferFolder"/mri/c_ras.mat "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject".native.wb.spec $Structure "$Subject"."$Hemisphere"."$Surface".native.surf.gii
    i=$(($i+1))
  done

  #Create midthickness by averaging white and pial surfaces and use it to make inflated surfacess
  for Folder in "$HCPFolder" ; do
    ${CARET7DIR}/wb_command -surface-average "$Folder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii -surf "$Folder"/"$Subject"."$Hemisphere".white.native.surf.gii -surf "$Folder"/"$Subject"."$Hemisphere".pial.native.surf.gii
    ${CARET7DIR}/wb_command -set-structure "$Folder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii ${Structure} -surface-type ANATOMICAL -surface-secondary-type MIDTHICKNESS
    ${CARET7DIR}/wb_command -add-to-spec-file "$Folder"/"$Subject".native.wb.spec $Structure "$Subject"."$Hemisphere".midthickness.native.surf.gii
    ${CARET7DIR}/wb_command -surface-generate-inflated "$Folder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$Folder"/"$Subject"."$Hemisphere".inflated.native.surf.gii "$Folder"/"$Subject"."$Hemisphere".very_inflated.native.surf.gii -iterations-scale 2.5
    ${CARET7DIR}/wb_command -add-to-spec-file "$Folder"/"$Subject".native.wb.spec $Structure "$Subject"."$Hemisphere".inflated.native.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$Folder"/"$Subject".native.wb.spec $Structure "$Subject"."$Hemisphere".very_inflated.native.surf.gii
  done

  #Convert original and registered spherical surfaces and add them to the spec file
  for Surface in sphere.reg sphere ; do
    mris_convert "$FreeSurferFolder"/surf/"$hemisphere"h."$Surface" "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii
    ${CARET7DIR}/wb_command -set-structure "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${Structure} -surface-type SPHERICAL
  done
  ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject".native.wb.spec $Structure "$Subject"."$Hemisphere".sphere.native.surf.gii

  #Add more files to the spec file and convert other FreeSurfer surface data to metric/GIFTI including sulc, curv, and thickness.
  for Map in sulc@sulc@Sulc thickness@thickness@Thickness curv@curvature@Curvature ; do
    fsname=`echo $Map | cut -d "@" -f 1`
    wbname=`echo $Map | cut -d "@" -f 2`
    mapname=`echo $Map | cut -d "@" -f 3`
    mris_convert -c "$FreeSurferFolder"/surf/"$hemisphere"h."$fsname" "$FreeSurferFolder"/surf/"$hemisphere"h.white "$HCPFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii
    ${CARET7DIR}/wb_command -set-structure "$HCPFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii ${Structure}
    ${CARET7DIR}/wb_command -metric-math "var * -1" "$HCPFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii -var var "$HCPFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii
    ${CARET7DIR}/wb_command -set-map-names "$HCPFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii -map 1 "$Subject"_"$Hemisphere"_"$mapname"
    ${CARET7DIR}/wb_command -metric-palette "$HCPFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii MODE_AUTO_SCALE_PERCENTAGE -pos-percent 2 98 -palette-name Gray_Interp -disp-pos true -disp-neg true -disp-zero true
  done
  #Thickness specific operations (we should review the implications of the math...)
  ${CARET7DIR}/wb_command -metric-math "abs(thickness)" "$HCPFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii -var thickness "$HCPFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii
  ${CARET7DIR}/wb_command -metric-palette "$HCPFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
  ${CARET7DIR}/wb_command -metric-math "thickness > 0" "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -var thickness "$HCPFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii
  ${CARET7DIR}/wb_command -metric-fill-holes "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
  ${CARET7DIR}/wb_command -metric-remove-islands "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
  ${CARET7DIR}/wb_command -set-map-names "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -map 1 "$Subject"_"$Hemisphere"_ROI
  ${CARET7DIR}/wb_command -metric-dilate "$HCPFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii 10 "$HCPFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii -nearest
  ${CARET7DIR}/wb_command -metric-dilate "$HCPFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii 10 "$HCPFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii -nearest

  #Label operations
  for Map in aparc aparc.a2009s BA ; do
    if [ -e "$FreeSurferFolder"/label/"$hemisphere"h."$Map".annot ] ; then
      mris_convert --annot "$FreeSurferFolder"/label/"$hemisphere"h."$Map".annot "$FreeSurferFolder"/surf/"$hemisphere"h.white "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii
      ${CARET7DIR}/wb_command -set-structure "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii $Structure
      ${CARET7DIR}/wb_command -set-map-names "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii -map 1 "$Subject"_"$Hemisphere"_"$Map"
      ${CARET7DIR}/wb_command -gifti-label-add-prefix "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii "${Hemisphere}_" "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii
    fi
  done
  #End main native mesh processing


  #Copy Atlas Files
  if [ ! -e "$HCPFolder"/fsaverage ] ; then
  	mkdir -p "$HCPFolder"/fsaverage
  fi

  cp "$SurfaceAtlasDIR"/fs_"$Hemisphere"/fsaverage."$Hemisphere".sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii "$HCPFolder"/fsaverage/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii
  cp "$SurfaceAtlasDIR"/fs_"$Hemisphere"/fs_"$Hemisphere"-to-fs_LR_fsaverage."$Hemisphere"_LR.spherical_std."$HighResMesh"k_fs_"$Hemisphere".surf.gii "$HCPFolder"/fsaverage/"$Subject"."$Hemisphere".def_sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii
  cp "$SurfaceAtlasDIR"/fsaverage."$Hemisphere"_LR.spherical_std."$HighResMesh"k_fs_LR.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii
  ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii
  cp "$SurfaceAtlasDIR"/"$Hemisphere".atlasroi."$HighResMesh"k_fs_LR.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".roi."$HighResMesh"k_fs_LR.shape.gii
  cp "$SurfaceAtlasDIR"/"$Hemisphere".refsulc."$HighResMesh"k_fs_LR.shape.gii "$HCPFolder"/${Subject}.${Hemisphere}.refsulc."$HighResMesh"k_fs_LR.shape.gii
  if [ -e "$SurfaceAtlasDIR"/colin.cerebral."$Hemisphere".flat."$HighResMesh"k_fs_LR.surf.gii ] ; then
    cp "$SurfaceAtlasDIR"/colin.cerebral."$Hemisphere".flat."$HighResMesh"k_fs_LR.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".flat."$HighResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere".flat."$HighResMesh"k_fs_LR.surf.gii
  fi

  #Concatinate FS registration to FS --> FS_LR registration
  ${CARET7DIR}/wb_command -surface-sphere-project-unproject "$HCPFolder"/"$Subject"."$Hemisphere".sphere.reg.native.surf.gii "$HCPFolder"/fsaverage/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii "$HCPFolder"/fsaverage/"$Subject"."$Hemisphere".def_sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.surf.gii

  #Make FreeSurfer Registration Areal Distortion Maps
  ${CARET7DIR}/wb_command -surface-vertex-areas "$HCPFolder"/"$Subject"."$Hemisphere".sphere.native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii
  ${CARET7DIR}/wb_command -surface-vertex-areas "$HCPFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.shape.gii
  ${CARET7DIR}/wb_command -metric-math "ln(spherereg / sphere) / ln(2)" "$HCPFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii -var sphere "$HCPFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii -var spherereg "$HCPFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.shape.gii
  rm "$HCPFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.shape.gii
  ${CARET7DIR}/wb_command -set-map-names "$HCPFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii -map 1 "$Subject"_"$Hemisphere"_Areal_Distortion_FS
  ${CARET7DIR}/wb_command -metric-palette "$HCPFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii MODE_AUTO_SCALE -palette-name ROY-BIG-BL -thresholding THRESHOLD_TYPE_NORMAL THRESHOLD_TEST_SHOW_OUTSIDE -1 1

  RegSphere="${HCPFolder}/${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii"

  #Ensure no zeros in atlas medial wall ROI
  ${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere".roi."$HighResMesh"k_fs_LR.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ${RegSphere} BARYCENTRIC "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -largest
  ${CARET7DIR}/wb_command -metric-math "(atlas + individual) > 0" "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -var atlas "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -var individual "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
  ${CARET7DIR}/wb_command -metric-mask "$HCPFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii
  ${CARET7DIR}/wb_command -metric-mask "$HCPFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii


  #Populate Highres fs_LR spec file.  Deform surfaces and other data according to native to folding-based registration selected above.  Regenerate inflated surfaces.
  for Surface in white midthickness pial ; do
    ${CARET7DIR}/wb_command -surface-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${RegSphere} "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii BARYCENTRIC "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface"."$HighResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere"."$Surface"."$HighResMesh"k_fs_LR.surf.gii
  done
  ${CARET7DIR}/wb_command -surface-generate-inflated "$HCPFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".inflated."$HighResMesh"k_fs_LR.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".very_inflated."$HighResMesh"k_fs_LR.surf.gii -iterations-scale 2.5
  ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere".inflated."$HighResMesh"k_fs_LR.surf.gii
  ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere".very_inflated."$HighResMesh"k_fs_LR.surf.gii

  for Map in thickness curvature ; do
    ${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.shape.gii ${RegSphere} "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR.shape.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii -current-roi "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
    ${CARET7DIR}/wb_command -metric-mask "$HCPFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere".roi."$HighResMesh"k_fs_LR.shape.gii "$HCPFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR.shape.gii
  done
  ${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii ${RegSphere} "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS."$HighResMesh"k_fs_LR.shape.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii
  ${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere".sulc.native.shape.gii ${RegSphere} "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/"$Subject"."$Hemisphere".sulc."$HighResMesh"k_fs_LR.shape.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$HCPFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii

  for Map in aparc aparc.a2009s BA ; do
    if [ -e "$FreeSurferFolder"/label/"$hemisphere"h."$Map".annot ] ; then
      ${CARET7DIR}/wb_command -label-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii ${RegSphere} "$HCPFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii BARYCENTRIC "$HCPFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR.label.gii -largest
    fi
  done

  for LowResMesh in ${LowResMeshes} ; do
	if [ ! -e "$HCPFolder"/fsaverage_LR"$LowResMesh"k ] ; then
		mkdir -p "$HCPFolder"/fsaverage_LR"$LowResMesh"k
	fi

    #Copy Atlas Files
    cp "$SurfaceAtlasDIR"/"$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii
    cp "$GrayordinatesSpaceDIR"/"$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".roi."$LowResMesh"k_fs_LR.shape.gii
    if [ -e "$SurfaceAtlasDIR"/colin.cerebral."$Hemisphere".flat."$LowResMesh"k_fs_LR.surf.gii ] ; then
      cp "$SurfaceAtlasDIR"/colin.cerebral."$Hemisphere".flat."$LowResMesh"k_fs_LR.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".flat."$LowResMesh"k_fs_LR.surf.gii
      ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere".flat."$LowResMesh"k_fs_LR.surf.gii
    fi

    #Create downsampled fs_LR spec files.
    for Surface in white midthickness pial ; do
      ${CARET7DIR}/wb_command -surface-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${RegSphere} "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii BARYCENTRIC "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
      ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
    done
    ${CARET7DIR}/wb_command -surface-generate-inflated "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".inflated."$LowResMesh"k_fs_LR.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".very_inflated."$LowResMesh"k_fs_LR.surf.gii -iterations-scale 0.75
    ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere".inflated."$LowResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$Subject"."$Hemisphere".very_inflated."$LowResMesh"k_fs_LR.surf.gii

    for Map in sulc thickness curvature ; do
      ${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.shape.gii ${RegSphere} "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.shape.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$HCPFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
      ${CARET7DIR}/wb_command -metric-mask "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.shape.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".roi."$LowResMesh"k_fs_LR.shape.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.shape.gii
    done
    ${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii ${RegSphere} "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".ArealDistortion_FS."$LowResMesh"k_fs_LR.shape.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -metric-resample "$HCPFolder"/"$Subject"."$Hemisphere".sulc.native.shape.gii ${RegSphere} "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sulc."$LowResMesh"k_fs_LR.shape.gii -area-surfs "$HCPFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii

    for Map in aparc aparc.a2009s BA ; do
      if [ -e "$FreeSurferFolder"/label/"$hemisphere"h."$Map".annot ] ; then
        ${CARET7DIR}/wb_command -label-resample "$HCPFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii ${RegSphere} "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii BARYCENTRIC "$HCPFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.label.gii -largest
      fi
    done
  done
done




STRINGII=""
for LowResMesh in ${LowResMeshes} ; do
  STRINGII=`echo "${STRINGII}${HCPFolder}/fsaverage_LR${LowResMesh}k@${LowResMesh}k_fs_LR@roi "`
done

#Create CIFTI Files
for STRING in "$HCPFolder"@native@roi "$HCPFolder"@"$HighResMesh"k_fs_LR@roi ${STRINGII} ; do
  Folder=`echo $STRING | cut -d "@" -f 1`
  Mesh=`echo $STRING | cut -d "@" -f 2`
  ROI=`echo $STRING | cut -d "@" -f 3`

  ${CARET7DIR}/wb_command -cifti-create-dense-scalar "$Folder"/"$Subject".sulc."$Mesh".dscalar.nii -left-metric "$Folder"/"$Subject".L.sulc."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.sulc."$Mesh".shape.gii
  ${CARET7DIR}/wb_command -set-map-names "$Folder"/"$Subject".sulc."$Mesh".dscalar.nii -map 1 "${Subject}_Sulc"
  ${CARET7DIR}/wb_command -cifti-palette "$Folder"/"$Subject".sulc."$Mesh".dscalar.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".sulc."$Mesh".dscalar.nii -pos-percent 2 98 -palette-name Gray_Interp -disp-pos true -disp-neg true -disp-zero true

  ${CARET7DIR}/wb_command -cifti-create-dense-scalar "$Folder"/"$Subject".curvature."$Mesh".dscalar.nii -left-metric "$Folder"/"$Subject".L.curvature."$Mesh".shape.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.curvature."$Mesh".shape.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
  ${CARET7DIR}/wb_command -set-map-names "$Folder"/"$Subject".curvature."$Mesh".dscalar.nii -map 1 "${Subject}_Curvature"
  ${CARET7DIR}/wb_command -cifti-palette "$Folder"/"$Subject".curvature."$Mesh".dscalar.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".curvature."$Mesh".dscalar.nii -pos-percent 2 98 -palette-name Gray_Interp -disp-pos true -disp-neg true -disp-zero true

  ${CARET7DIR}/wb_command -cifti-create-dense-scalar "$Folder"/"$Subject".thickness."$Mesh".dscalar.nii -left-metric "$Folder"/"$Subject".L.thickness."$Mesh".shape.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.thickness."$Mesh".shape.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
  ${CARET7DIR}/wb_command -set-map-names "$Folder"/"$Subject".thickness."$Mesh".dscalar.nii -map 1 "${Subject}_Thickness"
  ${CARET7DIR}/wb_command -cifti-palette "$Folder"/"$Subject".thickness."$Mesh".dscalar.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".thickness."$Mesh".dscalar.nii -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false

  ${CARET7DIR}/wb_command -cifti-create-dense-scalar "$Folder"/"$Subject".ArealDistortion_FS."$Mesh".dscalar.nii -left-metric "$Folder"/"$Subject".L.ArealDistortion_FS."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.ArealDistortion_FS."$Mesh".shape.gii
  ${CARET7DIR}/wb_command -set-map-names "$Folder"/"$Subject".ArealDistortion_FS."$Mesh".dscalar.nii -map 1 "${Subject}_ArealDistortion_FS"
  ${CARET7DIR}/wb_command -cifti-palette "$Folder"/"$Subject".ArealDistortion_FS."$Mesh".dscalar.nii MODE_USER_SCALE "$Folder"/"$Subject".ArealDistortion_FS."$Mesh".dscalar.nii -pos-user 0 1 -neg-user 0 -1 -interpolate true -palette-name ROY-BIG-BL -disp-pos true -disp-neg true -disp-zero false

  for Map in aparc aparc.a2009s BA ; do
    if [ -e "$Folder"/"$Subject".L.${Map}."$Mesh".label.gii ] ; then
      ${CARET7DIR}/wb_command -cifti-create-label "$Folder"/"$Subject".${Map}."$Mesh".dlabel.nii -left-label "$Folder"/"$Subject".L.${Map}."$Mesh".label.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-label "$Folder"/"$Subject".R.${Map}."$Mesh".label.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
      ${CARET7DIR}/wb_command -set-map-names "$Folder"/"$Subject".${Map}."$Mesh".dlabel.nii -map 1 "$Subject"_${Map}
    fi
  done
done

STRINGII=""
for LowResMesh in ${LowResMeshes} ; do
  STRINGII=`echo "${STRINGII}${HCPFolder}/fsaverage_LR${LowResMesh}k@${HCPFolder}/fsaverage_LR${LowResMesh}k@${LowResMesh}k_fs_LR"`
done

#Add CIFTI Maps to Spec Files
for STRING in "$HCPFolder"@"$HCPFolder"@native "$HCPFolder"@"$HCPFolder"@"$HighResMesh"k_fs_LR ${STRINGII} ; do
  FolderI=`echo $STRING | cut -d "@" -f 1`
  FolderII=`echo $STRING | cut -d "@" -f 2`
  Mesh=`echo $STRING | cut -d "@" -f 3`
  for STRINGII in sulc@dscalar thickness@dscalar curvature@dscalar aparc@dlabel aparc.a2009s@dlabel BA@dlabel ; do
    Map=`echo $STRINGII | cut -d "@" -f 1`
    Ext=`echo $STRINGII | cut -d "@" -f 2`
    if [ -e "$FolderII"/"$Subject"."$Map"."$Mesh"."$Ext".nii ] ; then
      ${CARET7DIR}/wb_command -add-to-spec-file "$FolderI"/"$Subject"."$Mesh".wb.spec INVALID "$Subject"."$Map"."$Mesh"."$Ext".nii
    fi
  done
done












