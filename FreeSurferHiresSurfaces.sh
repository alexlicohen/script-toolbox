#!/bin/bash
set -e
echo -e "\n START: FreeSurferHighResSurfaces"

#EnvironmentScript="${HCPPIPEDIR}/SetUpHCPPipeline_MacBook-Air.sh" #Pipeline environment script

# TODO: Need to separate out the white and pial code to allow for creation from DIFFERENT images... right now final surfaces are simply labeled as white and pial, need to be white_T1w, white_DIR, pial_T2w, pial_PSIR

SubjectID="$1" # just the name of the freesurfer subject dir, e.g., 07-391-500
SubjectDIR="$2" # Freesurfer SUBJECT_DIR; for the HCP scripts, this is the T1w dir, e.g., /mayoresearch/07-391-500/T1w/
StudyFolder="$3" # The parent DIR where you want the wb .spec files to be created (will be in sub-DIRs named SubjectID/native or atlas, etc...)
T1wImage="$3" #T1w FreeSurfer Input (Full Resolution), e.g., T1w_acpc_dc_restore.nii.gz
T2wImage="$4" #T2w or other image for FreeSurfer Input (already registered to T1?)
T2shortname="$5" #what suffix to add to the new files (if using T2, this would be T2w)
T2Register="$6" #register the 'T2w' image to the T1w, choices are: "register" or "bypass"
GreyWhiteBright="$7" # give t1 if White brighter than Grey, t2 if Grey brighter than White (may not be needed if bbregister is removed)
makesurface="$8" # whiteonly, pialonly, or both  (for now, everything runs unless you enter pialonly, to skip the first half of the code, assuming it's already been run at least once.

export SUBJECTS_DIR="$SubjectDIR"

mridir=$SubjectDIR/$SubjectID/mri
surfdir=$SubjectDIR/$SubjectID/surf

reg=$mridir/transforms/hires21mm.dat
regII=$mridir/transforms/1mm2hires.dat
fslmaths "$T1wImage" -abs -add 1 "$mridir"/T1w_hires.nii.gz
hires="$mridir"/T1w_hires.nii.gz





####
#### THIS SECTION IS MODIFIED FROM FreeSurferHiresWhite.sh that lives in /Pipelines-3.4.0/FreeSurfer/scripts
#### It generates a higher resolution white surface (still just based on the T1w...) and Fine Tunes the T2w to T1w Registration
#### Todo: remove registration fine-tuning and instantiate White surface based on alt sequence.
####





if [ $makesurface != "pialonly" ] ; then

	echo "Starting with the contents of FreeSurferHiresWhite.sh and the intermediate recon-all steps"
	
	# generate registration between conformed and hires based on headers
	tkregister2 --mov "$mridir"/T1w_hires.nii.gz --targ $mridir/orig.mgz --noedit --regheader --reg $reg
	# map white and pial to hires coords (pial is only for visualization - won't be used later)
	cp $SubjectDIR/$SubjectID/surf/lh.white $SubjectDIR/$SubjectID/surf/lh.sphere.reg
	cp $SubjectDIR/$SubjectID/surf/rh.white $SubjectDIR/$SubjectID/surf/rh.sphere.reg
	mri_surf2surf --s $SubjectID --sval-xyz white --reg $reg "$mridir"/T1w_hires.nii.gz --tval-xyz --tval white.hires --hemi lh
	mri_surf2surf --s $SubjectID --sval-xyz white --reg $reg "$mridir"/T1w_hires.nii.gz --tval-xyz --tval white.hires --hemi rh

	cp $SubjectDIR/$SubjectID/surf/lh.white $SubjectDIR/$SubjectID/surf/lh.white.prehires
	cp $SubjectDIR/$SubjectID/surf/rh.white $SubjectDIR/$SubjectID/surf/rh.white.prehires

	# make sure to create the file control.hires.dat in the scripts dir with at least a few points
	# in the wm for the mri_normalize call that comes next

	# map the various lowres volumes that mris_make_surfaces needs into the hires coords
	for v in wm.mgz filled.mgz brain.mgz aseg.mgz ; do
	  basename=`echo $v | cut -d "." -f 1`
	  mri_convert -rl "$mridir"/T1w_hires.nii.gz -rt nearest $mridir/$v $mridir/$basename.hires.mgz
	done

	# remove nonbrain tissue
	mri_mask "$mridir"/T1w_hires.nii.gz $mridir/brain.hires.mgz $mridir/T1w_hires.masked.mgz

	mri_convert $mridir/aseg.hires.mgz $mridir/aseg.hires.nii.gz
	leftcoords=`fslstats $mridir/aseg.hires.nii.gz -l 1 -u 3 -c`
	rightcoords=`fslstats $mridir/aseg.hires.nii.gz -l 40 -u 42 -c`

	echo "$leftcoords" > $SubjectDIR/$SubjectID/scripts/control.hires.dat
	echo "$rightcoords" >> $SubjectDIR/$SubjectID/scripts/control.hires.dat
	echo "info" >> $SubjectDIR/$SubjectID/scripts/control.hires.dat
	echo "numpoints 2" >> $SubjectDIR/$SubjectID/scripts/control.hires.dat
	echo "useRealRAS 1" >> $SubjectDIR/$SubjectID/scripts/control.hires.dat

	# do intensity normalization on the hires volume using the white surface (use locations that
	mri_normalize -erode 1 -f $SubjectDIR/$SubjectID/scripts/control.hires.dat -min_dist 1 -surface "$surfdir"/lh.white.hires identity.nofile -surface "$surfdir"/rh.white.hires identity.nofile $mridir/T1w_hires.masked.mgz $mridir/T1w_hires.masked.norm.mgz

	#Check if FreeSurfer is version 5.2.0 or not.  If it is not, use new -first_wm_peak mris_make_surfaces flag
	if [ -z `cat ${FREESURFER_HOME}/build-stamp.txt | grep v5.2.0` ] ; then
	  FIRSTWMPEAK="-first_wm_peak"
	else
	  FIRSTWMPEAK=""
	fi

	#deform the surfaces
	mris_make_surfaces ${FIRSTWMPEAK} -noaparc -aseg aseg.hires -orig white.hires -filled filled.hires -wm wm.hires -sdir $SubjectDIR -T1 T1w_hires.masked.norm -orig_white white.hires -output .deformed -w 0 $SubjectID lh
	mris_make_surfaces ${FIRSTWMPEAK} -noaparc -aseg aseg.hires -orig white.hires -filled filled.hires -wm wm.hires -sdir $SubjectDIR -T1 T1w_hires.masked.norm -orig_white white.hires -output .deformed -w 0 $SubjectID rh


	#Fine Tune T2w to T1w Registration
	# Todo: if disabled, some files still need to be created for compatibility: "$mridir"/"$T2shortname"_hires.nii.gz and "$mridir"/transforms/"$T2shortname"toT1w.mat, with some math done to them too...

	echo "$SubjectID" > "$mridir"/transforms/eye.dat
	echo "1" >> "$mridir"/transforms/eye.dat
	echo "1" >> "$mridir"/transforms/eye.dat
	echo "1" >> "$mridir"/transforms/eye.dat
	echo "1 0 0 0" >> "$mridir"/transforms/eye.dat
	echo "0 1 0 0" >> "$mridir"/transforms/eye.dat
	echo "0 0 1 0" >> "$mridir"/transforms/eye.dat
	echo "0 0 0 1" >> "$mridir"/transforms/eye.dat
	echo "round" >> "$mridir"/transforms/eye.dat

	if [ $T2Register != "bypass" ] ; then
	  bbregister --s "$SubjectID" --mov "$T2wImage" --surf white.deformed --init-reg "$mridir"/transforms/eye.dat --"$GreyWhiteBright" --reg "$mridir"/transforms/"$T2shortname"toT1w.dat --o "$mridir"/"$T2shortname"_hires.nii.gz
	  tkregister2 --noedit --reg "$mridir"/transforms/"$T2shortname"toT1w.dat --mov "$T2wImage" --targ "$mridir"/T1w_hires.nii.gz --fslregout "$mridir"/transforms/"$T2shortname"toT1w.mat
	  applywarp --interp=spline -i "$T2wImage" -r "$mridir"/T1w_hires.nii.gz --premat="$mridir"/transforms/"$T2shortname"toT1w.mat -o "$mridir"/"$T2shortname"_hires.nii.gz
	  fslmaths "$mridir"/"$T2shortname"_hires.nii.gz -abs -add 1 "$mridir"/"$T2shortname"_hires.nii.gz
	  fslmaths "$mridir"/T1w_hires.nii.gz -mul "$mridir"/"$T2shortname"_hires.nii.gz -sqrt "$mridir"/T1wMul"$T2shortname"_hires.nii.gz
	else
	  echo "Bypassing T2w to T1w Registration code and just resampling to match the T1w"
	  cp "$mridir"/transforms/eye.dat "$mridir"/transforms/"$T2shortname"toT1w.dat
	  mri_convert -rl "$mridir"/T1w_hires.nii.gz -rt nearest "$T2wImage" "$mridir"/"$T2shortname"_hires.nii.gz
	  fslmaths "$mridir"/"$T2shortname"_hires.nii.gz -abs -add 1 "$mridir"/"$T2shortname"_hires.nii.gz
	  fslmaths "$mridir"/T1w_hires.nii.gz -mul "$mridir"/"$T2shortname"_hires.nii.gz -sqrt "$mridir"/T1wMul"$T2shortname"_hires.nii.gz
	fi

	tkregister2 --mov $mridir/orig.mgz --targ "$mridir"/T1w_hires.nii.gz --noedit --regheader --reg $regII
	mri_surf2surf --s $SubjectID --sval-xyz white.deformed --reg $regII $mridir/orig.mgz --tval-xyz --tval white --hemi lh
	mri_surf2surf --s $SubjectID --sval-xyz white.deformed --reg $regII $mridir/orig.mgz --tval-xyz --tval white --hemi rh

	cp $SubjectDIR/$SubjectID/surf/lh.curv $SubjectDIR/$SubjectID/surf/lh.curv.prehires
	cp $SubjectDIR/$SubjectID/surf/lh.area $SubjectDIR/$SubjectID/surf/lh.area.prehires
	cp $SubjectDIR/$SubjectID/label/lh.cortex.label $SubjectDIR/$SubjectID/label/lh.cortex.prehires.label
	cp $SubjectDIR/$SubjectID/surf/rh.curv $SubjectDIR/$SubjectID/surf/rh.curv.prehires
	cp $SubjectDIR/$SubjectID/surf/rh.area $SubjectDIR/$SubjectID/surf/rh.area.prehires
	cp $SubjectDIR/$SubjectID/label/rh.cortex.label $SubjectDIR/$SubjectID/label/rh.cortex.prehires.label


	cp $SubjectDIR/$SubjectID/surf/lh.curv.deformed $SubjectDIR/$SubjectID/surf/lh.curv
	cp $SubjectDIR/$SubjectID/surf/lh.area.deformed  $SubjectDIR/$SubjectID/surf/lh.area
	cp $SubjectDIR/$SubjectID/label/lh.cortex.deformed.label $SubjectDIR/$SubjectID/label/lh.cortex.label
	cp $SubjectDIR/$SubjectID/surf/rh.curv.deformed $SubjectDIR/$SubjectID/surf/rh.curv
	cp $SubjectDIR/$SubjectID/surf/rh.area.deformed  $SubjectDIR/$SubjectID/surf/rh.area
	cp $SubjectDIR/$SubjectID/label/rh.cortex.deformed.label $SubjectDIR/$SubjectID/label/rh.cortex.label


	rm $SubjectDIR/$SubjectID/surf/lh.sphere.reg
	rm $SubjectDIR/$SubjectID/surf/rh.sphere.reg


	#If you want to keep using HCP_Pipelines, enable the following code to re-instantiate the expected files (pretending that the alt-volume is a T2...)
	# cp "$mridir"/transforms/"$T2shortname"toT1w.dat "$mridir"/transforms/T2wtoT1w.dat
	# cp "$mridir"/"$T2shortname"_hires.nii.gz "$mridir"/T2w_hires.nii.gz
	# cp "$mridir"/T1wMul"$T2shortname"_hires.nii.gz "$mridir"/T1wMulT2w_hires.nii.gz
	# echo -e "\n END: FreeSurferHighResWhite"

else
	echo "Skipping the contents of FreeSurferHiresWhite.sh and the intermediate recon-all steps"
fi



# Intermediate Recon-all Steps
# This gets run by the Pipelines-3.4.0 FreeSurferPipeline.sh script in between the white and pial scripts
recon-all -subjid $SubjectID -sd $SubjectDIR -smooth2 -inflate2 -curvstats -sphere -surfreg -jacobian_white -avgcurv -cortparc





####
#### THIS IS MODIFIED FROM FreeSurferHiresPial.sh that lives in /Pipelines-3.4.0/FreeSurfer/scripts
#### It generates a higher resolution pial surface based on the T2w or alternative sequence...
#### Todo: Lots of settings to try and adjust...
#### Note: -T2Dura is an undocumented flag for mris_make_surfaces to specify a FLAIR or T2 image for pial differentiation
####





echo -e "\n START: FreeSurferHighResPial"

Sigma="5" #in mm (This is apparently used for riboon smoothing only, unclear what the value should be...)

hires="$mridir"/T1w_hires.nii.gz
T2="$mridir"/"$T2shortname"_hires.norm.mgz
Ratio="$mridir"/T1wDividedBy"$T2shortname"_sqrt.nii.gz

# Converting and thresholding the WM volume, normalizing the T1 image, and conversting both the T1 and 'T2' to mgz format

mri_convert "$mridir"/wm.hires.mgz "$mridir"/wm.hires.nii.gz
fslmaths "$mridir"/wm.hires.nii.gz -thr 110 -uthr 110 "$mridir"/wm.hires.nii.gz
wmMean=`fslstats "$mridir"/T1w_hires.nii.gz -k "$mridir"/wm.hires.nii.gz -M`
fslmaths "$mridir"/T1w_hires.nii.gz -div $wmMean -mul 110 "$mridir"/T1w_hires.norm.nii.gz
mri_convert "$mridir"/T1w_hires.norm.nii.gz "$mridir"/T1w_hires.norm.mgz

fslmaths "$mridir"/"$T2shortname"_hires.nii.gz -div `fslstats "$mridir"/"$T2shortname"_hires.nii.gz -k "$mridir"/wm.hires.nii.gz -M` -mul 57 "$mridir"/"$T2shortname"_hires.norm.nii.gz -odt float
mri_convert "$mridir"/"$T2shortname"_hires.norm.nii.gz "$mridir"/"$T2shortname"_hires.norm.mgz



#Check if FreeSurfer is version 5.2.0 or not.  If it is not, use new -first_wm_peak mris_make_surfaces flag
if [ -z `cat ${FREESURFER_HOME}/build-stamp.txt | grep v5.2.0` ] ; then
  VARIABLESIGMA="8"
else
  VARIABLESIGMA="4"
fi

# making surfaces, first round?
mris_make_surfaces -variablesigma ${VARIABLESIGMA} -white NOWRITE -aseg aseg.hires -orig white.deformed -filled filled.hires -wm wm.hires -sdir $SubjectDIR -mgz -T1 T1w_hires.norm "$SubjectID" lh
mris_make_surfaces -variablesigma ${VARIABLESIGMA} -white NOWRITE -aseg aseg.hires -orig white.deformed -filled filled.hires -wm wm.hires -sdir $SubjectDIR -mgz -T1 T1w_hires.norm "$SubjectID" rh


# first stage backups...
cp $SubjectDIR/$SubjectID/surf/lh.pial $SubjectDIR/$SubjectID/surf/lh.pial.pre"$T2shortname"
cp $SubjectDIR/$SubjectID/surf/rh.pial $SubjectDIR/$SubjectID/surf/rh.pial.pre"$T2shortname"


#For mris_make_surface with correct arguments #Could go from 3 to 2 potentially...
mris_make_surfaces -nsigma_above 2 -nsigma_below 3 -aseg aseg.hires -filled filled.hires -wm wm.hires -mgz -sdir $SubjectDIR -orig white.deformed -nowhite -orig_white white.deformed -orig_pial pial -T2dura "$mridir"/"$T2shortname"_hires.norm -T1 T1w_hires.norm -output ."$T2shortname" $SubjectID lh
mris_make_surfaces -nsigma_above 2 -nsigma_below 3 -aseg aseg.hires -filled filled.hires -wm wm.hires -mgz -sdir $SubjectDIR -orig white.deformed -nowhite -orig_white white.deformed -orig_pial pial -T2dura "$mridir"/"$T2shortname"_hires.norm -T1 T1w_hires.norm -output ."$T2shortname" $SubjectID rh

mri_surf2surf --s $SubjectID --sval-xyz pial."$T2shortname" --reg $regII $mridir/orig.mgz --tval-xyz --tval pial."$T2shortname" --hemi lh
mri_surf2surf --s $SubjectID --sval-xyz pial."$T2shortname" --reg $regII $mridir/orig.mgz --tval-xyz --tval pial."$T2shortname" --hemi rh

MatrixX=`mri_info $mridir/brain.finalsurfs.mgz | grep "c_r" | cut -d "=" -f 5 | sed s/" "/""/g`
MatrixY=`mri_info $mridir/brain.finalsurfs.mgz | grep "c_a" | cut -d "=" -f 5 | sed s/" "/""/g`
MatrixZ=`mri_info $mridir/brain.finalsurfs.mgz | grep "c_s" | cut -d "=" -f 5 | sed s/" "/""/g`
echo "1 0 0 ""$MatrixX" > $mridir/c_ras.mat
echo "0 1 0 ""$MatrixY" >> $mridir/c_ras.mat
echo "0 0 1 ""$MatrixZ" >> $mridir/c_ras.mat
echo "0 0 0 1" >> $mridir/c_ras.mat

mris_convert "$surfdir"/lh.white "$surfdir"/lh.white.surf.gii
${CARET7DIR}/wb_command -set-structure "$surfdir"/lh.white.surf.gii CORTEX_LEFT
${CARET7DIR}/wb_command -surface-apply-affine "$surfdir"/lh.white.surf.gii $mridir/c_ras.mat "$surfdir"/lh.white.surf.gii
${CARET7DIR}/wb_command -create-signed-distance-volume "$surfdir"/lh.white.surf.gii "$mridir"/T1w_hires.nii.gz "$surfdir"/lh.white.nii.gz

mris_convert "$surfdir"/lh.pial."$T2shortname" "$surfdir"/lh.pial."$T2shortname".surf.gii
${CARET7DIR}/wb_command -set-structure "$surfdir"/lh.pial."$T2shortname".surf.gii CORTEX_LEFT
${CARET7DIR}/wb_command -surface-apply-affine "$surfdir"/lh.pial."$T2shortname".surf.gii $mridir/c_ras.mat "$surfdir"/lh.pial."$T2shortname".surf.gii
${CARET7DIR}/wb_command -create-signed-distance-volume "$surfdir"/lh.pial."$T2shortname".surf.gii "$mridir"/T1w_hires.nii.gz "$surfdir"/lh.pial."$T2shortname".nii.gz

mris_convert "$surfdir"/rh.white "$surfdir"/rh.white.surf.gii
${CARET7DIR}/wb_command -set-structure "$surfdir"/rh.white.surf.gii CORTEX_RIGHT
${CARET7DIR}/wb_command -surface-apply-affine "$surfdir"/rh.white.surf.gii $mridir/c_ras.mat "$surfdir"/rh.white.surf.gii
${CARET7DIR}/wb_command -create-signed-distance-volume "$surfdir"/rh.white.surf.gii "$mridir"/T1w_hires.nii.gz "$surfdir"/rh.white.nii.gz

mris_convert "$surfdir"/rh.pial."$T2shortname" "$surfdir"/rh.pial."$T2shortname".surf.gii
${CARET7DIR}/wb_command -set-structure "$surfdir"/rh.pial."$T2shortname".surf.gii CORTEX_RIGHT
${CARET7DIR}/wb_command -surface-apply-affine "$surfdir"/rh.pial."$T2shortname".surf.gii $mridir/c_ras.mat "$surfdir"/rh.pial."$T2shortname".surf.gii
${CARET7DIR}/wb_command -create-signed-distance-volume "$surfdir"/rh.pial."$T2shortname".surf.gii "$mridir"/T1w_hires.nii.gz "$surfdir"/rh.pial."$T2shortname".nii.gz

fslmaths "$surfdir"/lh.white.nii.gz -mul "$surfdir"/lh.pial."$T2shortname".nii.gz -uthr 0 -mul -1 -bin "$mridir"/lh.ribbon."$T2shortname".nii.gz
fslmaths "$surfdir"/rh.white.nii.gz -mul "$surfdir"/rh.pial."$T2shortname".nii.gz -uthr 0 -mul -1 -bin "$mridir"/rh.ribbon."$T2shortname".nii.gz
fslmaths "$mridir"/lh.ribbon."$T2shortname".nii.gz -add "$mridir"/rh.ribbon."$T2shortname".nii.gz -bin "$mridir"/ribbon."$T2shortname".nii.gz
fslcpgeom "$mridir"/T1w_hires.norm.nii.gz "$mridir"/ribbon."$T2shortname".nii.gz

fslmaths "$mridir"/ribbon."$T2shortname".nii.gz -s $Sigma "$mridir"/ribbon."$T2shortname"_s"$Sigma".nii.gz
fslmaths "$mridir"/T1w_hires.norm.nii.gz -mas "$mridir"/ribbon."$T2shortname".nii.gz "$mridir"/T1w_hires.norm_ribbon."$T2shortname".nii.gz
greymean=`fslstats "$mridir"/T1w_hires.norm_ribbon."$T2shortname".nii.gz -M`
fslmaths "$mridir"/ribbon."$T2shortname".nii.gz -sub 1 -mul -1 "$mridir"/ribbon."$T2shortname"_inv.nii.gz
fslmaths "$mridir"/T1w_hires.norm_ribbon."$T2shortname".nii.gz -s $Sigma -div "$mridir"/ribbon."$T2shortname"_s"$Sigma".nii.gz -div $greymean -mas "$mridir"/ribbon."$T2shortname".nii.gz -add "$mridir"/ribbon."$T2shortname"_inv.nii.gz "$mridir"/T1w_hires.norm_ribbon."$T2shortname"_myelin.nii.gz

fslmaths "$surfdir"/lh.white.nii.gz -uthr 0 -mul -1 -bin "$mridir"/lh.white.nii.gz
fslmaths "$surfdir"/rh.white.nii.gz -uthr 0 -mul -1 -bin "$mridir"/rh.white.nii.gz
fslmaths "$mridir"/lh.white.nii.gz -add "$mridir"/rh.white.nii.gz -bin "$mridir"/white.nii.gz
rm "$mridir"/lh.white.nii.gz "$mridir"/rh.white.nii.gz
fslmaths "$mridir"/T1w_hires.norm_ribbon."$T2shortname"_myelin.nii.gz -mas "$mridir"/ribbon."$T2shortname".nii.gz -add "$mridir"/white.nii.gz -uthr 1.9 "$mridir"/T1w_hires."$T2shortname".norm_grey_myelin.nii.gz
fslmaths "$mridir"/T1w_hires."$T2shortname".norm_grey_myelin.nii.gz -dilM -dilM -dilM -dilM -dilM "$mridir"/T1w_hires."$T2shortname".norm_grey_myelin.nii.gz
fslmaths "$mridir"/T1w_hires."$T2shortname".norm_grey_myelin.nii.gz -binv "$mridir"/dilribbon."$T2shortname"_inv.nii.gz
fslmaths "$mridir"/T1w_hires."$T2shortname".norm_grey_myelin.nii.gz -add "$mridir"/dilribbon."$T2shortname"_inv.nii.gz "$mridir"/T1w_hires."$T2shortname".norm_grey_myelin.nii.gz

fslmaths "$mridir"/T1w_hires.norm.nii.gz -div "$mridir"/T1w_hires."$T2shortname".norm_ribbon_myelin.nii.gz "$mridir"/T1w_hires."$T2shortname".greynorm_ribbon.nii.gz
fslmaths "$mridir"/T1w_hires.norm.nii.gz -div "$mridir"/T1w_hires."$T2shortname".norm_grey_myelin.nii.gz "$mridir"/T1w_hires."$T2shortname".greynorm.nii.gz

mri_convert "$mridir"/T1w_hires."$T2shortname".greynorm.nii.gz "$mridir"/T1w_hires."$T2shortname".greynorm.mgz

cp $SubjectDIR/$SubjectID/surf/lh.pial."$T2shortname" $SubjectDIR/$SubjectID/surf/lh.pial."$T2shortname".one
cp $SubjectDIR/$SubjectID/surf/rh.pial."$T2shortname" $SubjectDIR/$SubjectID/surf/rh.pial."$T2shortname".one

#Check if FreeSurfer is version 5.2.0 or not.  If it is not, use new -first_wm_peak mris_make_surfaces flag
if [ -z `cat ${FREESURFER_HOME}/build-stamp.txt | grep v5.2.0` ] ; then
  VARIABLESIGMA="4"
else
  VARIABLESIGMA="2"
fi

mris_make_surfaces -variablesigma ${VARIABLESIGMA} -white NOWRITE -aseg aseg.hires -orig white.deformed -filled filled.hires -wm wm.hires -sdir $SubjectDIR -mgz -T1 T1w_hires."$T2shortname".greynorm "$SubjectID" lh
mris_make_surfaces -variablesigma ${VARIABLESIGMA} -white NOWRITE -aseg aseg.hires -orig white.deformed -filled filled.hires -wm wm.hires -sdir $SubjectDIR -mgz -T1 T1w_hires."$T2shortname".greynorm "$SubjectID" rh

# second stage backups...
cp $SubjectDIR/$SubjectID/surf/lh.pial."$T2shortname" $SubjectDIR/$SubjectID/surf/lh.pial.pre"$T2shortname".two
cp $SubjectDIR/$SubjectID/surf/rh.pial."$T2shortname" $SubjectDIR/$SubjectID/surf/rh.pial.pre"$T2shortname".two

#Could go from 3 to 2 potentially...
mris_make_surfaces -nsigma_above 2 -nsigma_below 3 -aseg aseg.hires -filled filled.hires -wm wm.hires -mgz -sdir $SubjectDIR -orig white.deformed -nowhite -orig_white white.deformed -orig_pial pial."$T2shortname" -T2dura "$mridir"/"$T2shortname"_hires.norm -T1 T1w_hires.norm -output ."$T2shortname".two $SubjectID lh
mris_make_surfaces -nsigma_above 2 -nsigma_below 3 -aseg aseg.hires -filled filled.hires -wm wm.hires -mgz -sdir $SubjectDIR -orig white.deformed -nowhite -orig_white white.deformed -orig_pial pial."$T2shortname" -T2dura "$mridir"/"$T2shortname"_hires.norm -T1 T1w_hires.norm -output ."$T2shortname".two $SubjectID rh

mri_surf2surf --s $SubjectID --sval-xyz pial."$T2shortname".two --reg $regII $mridir/orig.mgz --tval-xyz --tval pial."$T2shortname" --hemi lh
mri_surf2surf --s $SubjectID --sval-xyz pial."$T2shortname".two --reg $regII $mridir/orig.mgz --tval-xyz --tval pial."$T2shortname" --hemi rh

cp $SubjectDIR/$SubjectID/surf/lh.thickness $SubjectDIR/$SubjectID/surf/lh.thickness.pre"$T2shortname"
cp $SubjectDIR/$SubjectID/surf/rh.thickness $SubjectDIR/$SubjectID/surf/rh.thickness.pre"$T2shortname"

cp $SubjectDIR/$SubjectID/surf/lh.thickness."$T2shortname".two $SubjectDIR/$SubjectID/surf/lh."$T2shortname".thickness
cp $SubjectDIR/$SubjectID/surf/rh.thickness."$T2shortname".two $SubjectDIR/$SubjectID/surf/rh."$T2shortname".thickness

cp $SubjectDIR/$SubjectID/surf/lh.area.pial."$T2shortname".two $SubjectDIR/$SubjectID/surf/lh."$T2shortname".area.pial
cp $SubjectDIR/$SubjectID/surf/rh.area.pial."$T2shortname".two $SubjectDIR/$SubjectID/surf/rh."$T2shortname".area.pial

cp $SubjectDIR/$SubjectID/surf/lh.curv.pial."$T2shortname".two $SubjectDIR/$SubjectID/surf/lh."$T2shortname".curv.pial
cp $SubjectDIR/$SubjectID/surf/rh.curv.pial."$T2shortname".two $SubjectDIR/$SubjectID/surf/lh."$T2shortname".curv.pial

echo -e "\n END: FreeSurferHighResPial"





# This gets run by the Pipelines-3.4.0 FreeSurferPipeline.sh script after the pial script
#Final Recon-all Steps
recon-all -subjid $SubjectID -sd $SubjectDIR -surfvolume -parcstats -cortparc2 -parcstats2 -cortparc3 -parcstats3 -cortribbon -segstats -aparc2aseg -wmparc -balabels -label-exvivo-ec





####
#### Code pulled from PostFreeSurfer.sh and FreeSurfer2CaretConvertAndRegisterNonlinear.sh to quickly make spec files to examine the new surfaces...
####


exit


# Input Variables
# HARDCODED FOR NOW... GET RID OF WHAT ISN'T USED!!!
SurfaceAtlasDIR="${HCPPIPEDIR_Templates}/standard_mesh_atlases"
GrayordinatesSpaceDIR="${HCPPIPEDIR_Templates}/91282_Greyordinates"
GrayordinatesResolutions="2"
HighResMesh="164"
LowResMeshes="32"
SubcorticalGrayLabels="${HCPPIPEDIR_Config}/FreeSurferSubcorticalLabelTableLut.txt"
FreeSurferLabels="${HCPPIPEDIR_Config}/FreeSurferAllLut.txt"
ReferenceMyelinMaps="${HCPPIPEDIR_Templates}/standard_mesh_atlases/Conte69.MyelinMap_BC.164k_fs_LR.dscalar.nii"
CorrectionSigma=`echo "sqrt ( 200 )" | bc -l)`  #unclear what this is supposed to be, I don't see that it is set in the HCP scripts.
RegName="FS"

PipelineScripts=${HCPPIPEDIR_PostFS} # environment variable


T1wFolder="$SubjectDIR" #Location of T1w images
FreeSurferFolder="$SubjectDIR"
AtlasSpaceFolder="$StudyFolder"/"$SubjectID"/"$AtlasSpaceFolder"
AtlasTransform="$AtlasSpaceFolder"/xfms/acpc_dc2standard
InverseAtlasTransform="$AtlasSpaceFolder"/xfms/standard2acpc_dc
NativeFolder="Native"
FreeSurferInput="$T1wImage"

AtlasSpaceT1wImage="T1w_restore"
AtlasSpaceT2wImage="$T2shortname"_restore
T1wRestoreImage="T1w_acpc_dc_restore"
T2wRestoreImage="$T2shortname"_acpc_dc_restore
T1wImageBrainMask="brainmask_fs"


################### !!!!!!!!!!! I HAVE GOTTEN THROUGH TO HERE !!!!!!!!!!! ###################
################### !!!!!!!!!!! I HAVE GOTTEN THROUGH TO HERE !!!!!!!!!!! ###################
################### !!!!!!!!!!! I HAVE GOTTEN THROUGH TO HERE !!!!!!!!!!! ###################


#Conversion of FreeSurfer Volumes and Surfaces to NIFTI and GIFTI and Create Caret Files and Registration
log_Msg "Conversion of FreeSurfer Volumes and Surfaces to NIFTI and GIFTI and Create Caret Files and Registration"
"$PipelineScripts"/FreeSurfer2CaretConvertAndRegisterNonlinear.sh "$StudyFolder" "$SubjectID" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$FreeSurferFolder" "$FreeSurferInput" "$T1wRestoreImage" "$T2wRestoreImage" "$SurfaceAtlasDIR" "$HighResMesh" "$LowResMeshes" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$AtlasSpaceT2wImage" "$T1wImageBrainMask" "$FreeSurferLabels" "$GrayordinatesSpaceDIR" "$GrayordinatesResolutions" "$SubcorticalGrayLabels" "$RegName"

StudyFolder="$1"
Subject="$2"
T1wFolder="$3"
AtlasSpaceFolder="$4"
NativeFolder="$5"
FreeSurferFolder="$6"
FreeSurferInput="$7"
T1wImage="$8"
T2wImage="$9"
SurfaceAtlasDIR="${10}"
HighResMesh="${11}"
LowResMeshes="${12}"
AtlasTransform="${13}"
InverseAtlasTransform="${14}"
AtlasSpaceT1wImage="${15}"
AtlasSpaceT2wImage="${16}"
T1wImageBrainMask="${17}"
FreeSurferLabels="${18}"
GrayordinatesSpaceDIR="${19}"
GrayordinatesResolutions="${20}"
SubcorticalGrayLabels="${21}"
RegName="${22}"

LowResMeshes=`echo ${LowResMeshes} | sed 's/@/ /g'`
GrayordinatesResolutions=`echo ${GrayordinatesResolutions} | sed 's/@/ /g'`

#Make some folders for this and later scripts
if [ ! -e "$T1wFolder"/"$NativeFolder" ] ; then
  mkdir -p "$T1wFolder"/"$NativeFolder"
fi
if [ ! -e "$AtlasSpaceFolder"/ROIs ] ; then
  mkdir -p "$AtlasSpaceFolder"/ROIs
fi
if [ ! -e "$AtlasSpaceFolder"/Results ] ; then
  mkdir "$AtlasSpaceFolder"/Results
fi
if [ ! -e "$AtlasSpaceFolder"/"$NativeFolder" ] ; then
  mkdir "$AtlasSpaceFolder"/"$NativeFolder"
fi
if [ ! -e "$AtlasSpaceFolder"/fsaverage ] ; then
  mkdir "$AtlasSpaceFolder"/fsaverage
fi
for LowResMesh in ${LowResMeshes} ; do
  if [ ! -e "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k ] ; then
    mkdir "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k
  fi
  if [ ! -e "$T1wFolder"/fsaverage_LR"$LowResMesh"k ] ; then
    mkdir "$T1wFolder"/fsaverage_LR"$LowResMesh"k
  fi
done

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
    mri_convert -rt nearest -rl "$T1wFolder"/"$T1wImage".nii.gz "$FreeSurferFolder"/mri/"$Image".mgz "$T1wFolder"/"$Image"_1mm.nii.gz
    applywarp --rel --interp=nn -i "$T1wFolder"/"$Image"_1mm.nii.gz -r "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage" --premat=$FSLDIR/etc/flirtsch/ident.mat -o "$T1wFolder"/"$Image".nii.gz
    applywarp --rel --interp=nn -i "$T1wFolder"/"$Image"_1mm.nii.gz -r "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage" -w "$AtlasTransform" -o "$AtlasSpaceFolder"/"$Image".nii.gz
    ${CARET7DIR}/wb_command -volume-label-import "$T1wFolder"/"$Image".nii.gz "$FreeSurferLabels" "$T1wFolder"/"$Image".nii.gz -drop-unused-labels
    ${CARET7DIR}/wb_command -volume-label-import "$AtlasSpaceFolder"/"$Image".nii.gz "$FreeSurferLabels" "$AtlasSpaceFolder"/"$Image".nii.gz -drop-unused-labels
  fi
done

#Create FreeSurfer Brain Mask
fslmaths "$T1wFolder"/wmparc_1mm.nii.gz -bin -dilD -dilD -dilD -ero -ero "$T1wFolder"/"$T1wImageBrainMask"_1mm.nii.gz
${CARET7DIR}/wb_command -volume-fill-holes "$T1wFolder"/"$T1wImageBrainMask"_1mm.nii.gz "$T1wFolder"/"$T1wImageBrainMask"_1mm.nii.gz
fslmaths "$T1wFolder"/"$T1wImageBrainMask"_1mm.nii.gz -bin "$T1wFolder"/"$T1wImageBrainMask"_1mm.nii.gz
applywarp --rel --interp=nn -i "$T1wFolder"/"$T1wImageBrainMask"_1mm.nii.gz -r "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage" --premat=$FSLDIR/etc/flirtsch/ident.mat -o "$T1wFolder"/"$T1wImageBrainMask".nii.gz
applywarp --rel --interp=nn -i "$T1wFolder"/"$T1wImageBrainMask"_1mm.nii.gz -r "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage" -w "$AtlasTransform" -o "$AtlasSpaceFolder"/"$T1wImageBrainMask".nii.gz

#Add volume files to spec files
${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/"$NativeFolder"/"$Subject".native.wb.spec INVALID "$T1wFolder"/"$T2wImage".nii.gz
${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/"$NativeFolder"/"$Subject".native.wb.spec INVALID "$T1wFolder"/"$T1wImage".nii.gz

${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject".native.wb.spec INVALID "$AtlasSpaceFolder"/"$AtlasSpaceT2wImage".nii.gz
${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject".native.wb.spec INVALID "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage".nii.gz

${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec INVALID "$AtlasSpaceFolder"/"$AtlasSpaceT2wImage".nii.gz
${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec INVALID "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage".nii.gz

for LowResMesh in ${LowResMeshes} ; do
  ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID "$AtlasSpaceFolder"/"$AtlasSpaceT2wImage".nii.gz
  ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage".nii.gz

  ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID "$T1wFolder"/"$T2wImage".nii.gz
  ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec INVALID "$T1wFolder"/"$T1wImage".nii.gz
done

#Import Subcortical ROIs
for GrayordinatesResolution in ${GrayordinatesResolutions} ; do
  cp "$GrayordinatesSpaceDIR"/Atlas_ROIs."$GrayordinatesResolution".nii.gz "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz
  applywarp --interp=nn -i "$AtlasSpaceFolder"/wmparc.nii.gz -r "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz -o "$AtlasSpaceFolder"/ROIs/wmparc."$GrayordinatesResolution".nii.gz
  ${CARET7DIR}/wb_command -volume-label-import "$AtlasSpaceFolder"/ROIs/wmparc."$GrayordinatesResolution".nii.gz "$FreeSurferLabels" "$AtlasSpaceFolder"/ROIs/wmparc."$GrayordinatesResolution".nii.gz -drop-unused-labels
  applywarp --interp=nn -i "$SurfaceAtlasDIR"/Avgwmparc.nii.gz -r "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz -o "$AtlasSpaceFolder"/ROIs/Atlas_wmparc."$GrayordinatesResolution".nii.gz
  ${CARET7DIR}/wb_command -volume-label-import "$AtlasSpaceFolder"/ROIs/Atlas_wmparc."$GrayordinatesResolution".nii.gz "$FreeSurferLabels" "$AtlasSpaceFolder"/ROIs/Atlas_wmparc."$GrayordinatesResolution".nii.gz -drop-unused-labels
  ${CARET7DIR}/wb_command -volume-label-import "$AtlasSpaceFolder"/ROIs/wmparc."$GrayordinatesResolution".nii.gz ${SubcorticalGrayLabels} "$AtlasSpaceFolder"/ROIs/ROIs."$GrayordinatesResolution".nii.gz -discard-others
  applywarp --interp=spline -i "$AtlasSpaceFolder"/"$AtlasSpaceT2wImage".nii.gz -r "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz -o "$AtlasSpaceFolder"/"$AtlasSpaceT2wImage"."$GrayordinatesResolution".nii.gz
  applywarp --interp=spline -i "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage".nii.gz -r "$AtlasSpaceFolder"/ROIs/Atlas_ROIs."$GrayordinatesResolution".nii.gz -o "$AtlasSpaceFolder"/"$AtlasSpaceT1wImage"."$GrayordinatesResolution".nii.gz
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
    mris_convert "$FreeSurferFolder"/surf/"$hemisphere"h."$Surface" "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii
    ${CARET7DIR}/wb_command -set-structure "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${Structure} -surface-type $Type$Secondary
    ${CARET7DIR}/wb_command -surface-apply-affine "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$FreeSurferFolder"/mri/c_ras.mat "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/"$NativeFolder"/"$Subject".native.wb.spec $Structure "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii
    ${CARET7DIR}/wb_command -surface-apply-warpfield "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii "$InverseAtlasTransform".nii.gz "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii -fnirt "$AtlasTransform".nii.gz
    ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject".native.wb.spec $Structure "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii
    i=$(($i+1))
  done
  
  #Create midthickness by averaging white and pial surfaces and use it to make inflated surfacess
  for Folder in "$T1wFolder" "$AtlasSpaceFolder" ; do
    ${CARET7DIR}/wb_command -surface-average "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii -surf "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".white.native.surf.gii -surf "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".pial.native.surf.gii
    ${CARET7DIR}/wb_command -set-structure "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii ${Structure} -surface-type ANATOMICAL -surface-secondary-type MIDTHICKNESS
    ${CARET7DIR}/wb_command -add-to-spec-file "$Folder"/"$NativeFolder"/"$Subject".native.wb.spec $Structure "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii
    ${CARET7DIR}/wb_command -surface-generate-inflated "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".inflated.native.surf.gii "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".very_inflated.native.surf.gii -iterations-scale 2.5
    ${CARET7DIR}/wb_command -add-to-spec-file "$Folder"/"$NativeFolder"/"$Subject".native.wb.spec $Structure "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".inflated.native.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$Folder"/"$NativeFolder"/"$Subject".native.wb.spec $Structure "$Folder"/"$NativeFolder"/"$Subject"."$Hemisphere".very_inflated.native.surf.gii
  done
  
  #Convert original and registered spherical surfaces and add them to the nonlinear spec file
  for Surface in sphere.reg sphere ; do
    mris_convert "$FreeSurferFolder"/surf/"$hemisphere"h."$Surface" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii
    ${CARET7DIR}/wb_command -set-structure "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${Structure} -surface-type SPHERICAL
  done
  ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject".native.wb.spec $Structure "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.surf.gii
   
  #Add more files to the spec file and convert other FreeSurfer surface data to metric/GIFTI including sulc, curv, and thickness.
  for Map in sulc@sulc@Sulc thickness@thickness@Thickness curv@curvature@Curvature ; do
    fsname=`echo $Map | cut -d "@" -f 1`
    wbname=`echo $Map | cut -d "@" -f 2`
    mapname=`echo $Map | cut -d "@" -f 3`
    mris_convert -c "$FreeSurferFolder"/surf/"$hemisphere"h."$fsname" "$FreeSurferFolder"/surf/"$hemisphere"h.white "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii
    ${CARET7DIR}/wb_command -set-structure "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii ${Structure}
    ${CARET7DIR}/wb_command -metric-math "var * -1" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii -var var "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii
    ${CARET7DIR}/wb_command -set-map-names "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii -map 1 "$Subject"_"$Hemisphere"_"$mapname"
    ${CARET7DIR}/wb_command -metric-palette "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$wbname".native.shape.gii MODE_AUTO_SCALE_PERCENTAGE -pos-percent 2 98 -palette-name Gray_Interp -disp-pos true -disp-neg true -disp-zero true
  done
  #Thickness specific operations
  ${CARET7DIR}/wb_command -metric-math "abs(thickness)" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii -var thickness "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii
  ${CARET7DIR}/wb_command -metric-palette "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
  ${CARET7DIR}/wb_command -metric-math "thickness > 0" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -var thickness "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii
  ${CARET7DIR}/wb_command -metric-fill-holes "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
  ${CARET7DIR}/wb_command -metric-remove-islands "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
  ${CARET7DIR}/wb_command -set-map-names "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -map 1 "$Subject"_"$Hemisphere"_ROI
  ${CARET7DIR}/wb_command -metric-dilate "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii 10 "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii -nearest
  ${CARET7DIR}/wb_command -metric-dilate "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii 10 "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii -nearest

  #Label operations
  for Map in aparc aparc.a2009s BA ; do
    if [ -e "$FreeSurferFolder"/label/"$hemisphere"h."$Map".annot ] ; then
      mris_convert --annot "$FreeSurferFolder"/label/"$hemisphere"h."$Map".annot "$FreeSurferFolder"/surf/"$hemisphere"h.white "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii
      ${CARET7DIR}/wb_command -set-structure "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii $Structure
      ${CARET7DIR}/wb_command -set-map-names "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii -map 1 "$Subject"_"$Hemisphere"_"$Map"
      ${CARET7DIR}/wb_command -gifti-label-add-prefix "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii "${Hemisphere}_" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii
    fi
  done
  #End main native mesh processing

  #Copy Atlas Files
  cp "$SurfaceAtlasDIR"/fs_"$Hemisphere"/fsaverage."$Hemisphere".sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii "$AtlasSpaceFolder"/fsaverage/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii
  cp "$SurfaceAtlasDIR"/fs_"$Hemisphere"/fs_"$Hemisphere"-to-fs_LR_fsaverage."$Hemisphere"_LR.spherical_std."$HighResMesh"k_fs_"$Hemisphere".surf.gii "$AtlasSpaceFolder"/fsaverage/"$Subject"."$Hemisphere".def_sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii
  cp "$SurfaceAtlasDIR"/fsaverage."$Hemisphere"_LR.spherical_std."$HighResMesh"k_fs_LR.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii
  ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii
  cp "$SurfaceAtlasDIR"/"$Hemisphere".atlasroi."$HighResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".atlasroi."$HighResMesh"k_fs_LR.shape.gii
  cp "$SurfaceAtlasDIR"/"$Hemisphere".refsulc."$HighResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/${Subject}.${Hemisphere}.refsulc."$HighResMesh"k_fs_LR.shape.gii
  if [ -e "$SurfaceAtlasDIR"/colin.cerebral."$Hemisphere".flat."$HighResMesh"k_fs_LR.surf.gii ] ; then
    cp "$SurfaceAtlasDIR"/colin.cerebral."$Hemisphere".flat."$HighResMesh"k_fs_LR.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".flat."$HighResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".flat."$HighResMesh"k_fs_LR.surf.gii
  fi
  
  #Concatinate FS registration to FS --> FS_LR registration  
  ${CARET7DIR}/wb_command -surface-sphere-project-unproject "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.reg.native.surf.gii "$AtlasSpaceFolder"/fsaverage/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii "$AtlasSpaceFolder"/fsaverage/"$Subject"."$Hemisphere".def_sphere."$HighResMesh"k_fs_"$Hemisphere".surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.surf.gii

  #Make FreeSurfer Registration Areal Distortion Maps
  ${CARET7DIR}/wb_command -surface-vertex-areas "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii
  ${CARET7DIR}/wb_command -surface-vertex-areas "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.shape.gii
  ${CARET7DIR}/wb_command -metric-math "ln(spherereg / sphere) / ln(2)" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii -var sphere "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii -var spherereg "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.shape.gii
  rm "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.reg.reg_LR.native.shape.gii
  ${CARET7DIR}/wb_command -set-map-names "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii -map 1 "$Subject"_"$Hemisphere"_Areal_Distortion_FS
  ${CARET7DIR}/wb_command -metric-palette "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii MODE_AUTO_SCALE -palette-name ROY-BIG-BL -thresholding THRESHOLD_TYPE_NORMAL THRESHOLD_TEST_SHOW_OUTSIDE -1 1

  #If desired, run MSMSulc folding-based registration to FS_LR initialized with FS affine
  if [ ${RegName} = "MSMSulc" ] ; then
    #Calculate Affine Transform and Apply
    if [ ! -e "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc ] ; then
      mkdir "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc
    fi
    ${CARET7DIR}/wb_command -surface-affine-regression "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc/${Hemisphere}.mat
    ${CARET7DIR}/wb_command -surface-apply-affine "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc/${Hemisphere}.mat "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc/${Hemisphere}.sphere_rot.surf.gii
    ${CARET7DIR}/wb_command -surface-modify-sphere "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc/${Hemisphere}.sphere_rot.surf.gii 100 "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc/${Hemisphere}.sphere_rot.surf.gii
    cp "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc/${Hemisphere}.sphere_rot.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.rot.native.surf.gii
    DIR=`pwd`
    cd "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc
    #Register using FreeSurfer Sulc Folding Map Using MSM Algorithm Configured for Reduced Distortion 
    #${MSMBin}/msm --version
    ${MSMBin}/msm --levels=4 --conf=${MSMBin}/allparameterssulcDRconf --inmesh="$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.rot.native.surf.gii --trans="$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.rot.native.surf.gii --refmesh="$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii --indata="$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sulc.native.shape.gii --refdata="$AtlasSpaceFolder"/${Subject}.${Hemisphere}.refsulc."$HighResMesh"k_fs_LR.shape.gii --out="$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc/${Hemisphere}. --verbose
    cd $DIR
    cp "$AtlasSpaceFolder"/"$NativeFolder"/MSMSulc/${Hemisphere}.HIGHRES_transformed.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.MSMSulc.native.surf.gii
    ${CARET7DIR}/wb_command -set-structure "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.MSMSulc.native.surf.gii ${Structure}

    #Make MSMSulc Registration Areal Distortion Maps
    ${CARET7DIR}/wb_command -surface-vertex-areas "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii
    ${CARET7DIR}/wb_command -surface-vertex-areas "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.MSMSulc.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.MSMSulc.native.shape.gii
    ${CARET7DIR}/wb_command -metric-math "ln(spherereg / sphere) / ln(2)" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_MSMSulc.native.shape.gii -var sphere "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii -var spherereg "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.MSMSulc.native.shape.gii
    rm "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sphere.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/${Subject}.${Hemisphere}.sphere.MSMSulc.native.shape.gii
    ${CARET7DIR}/wb_command -set-map-names "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_MSMSulc.native.shape.gii -map 1 "$Subject"_"$Hemisphere"_Areal_Distortion_MSMSulc
    ${CARET7DIR}/wb_command -metric-palette "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_MSMSulc.native.shape.gii MODE_AUTO_SCALE -palette-name ROY-BIG-BL -thresholding THRESHOLD_TYPE_NORMAL THRESHOLD_TEST_SHOW_OUTSIDE -1 1

    RegSphere="${AtlasSpaceFolder}/${NativeFolder}/${Subject}.${Hemisphere}.sphere.MSMSulc.native.surf.gii"
  else
    RegSphere="${AtlasSpaceFolder}/${NativeFolder}/${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii"
  fi

  #Ensure no zeros in atlas medial wall ROI
  ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".atlasroi."$HighResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ${RegSphere} BARYCENTRIC "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".atlasroi.native.shape.gii -largest
  ${CARET7DIR}/wb_command -metric-math "(atlas + individual) > 0" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -var atlas "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".atlasroi.native.shape.gii -var individual "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
  ${CARET7DIR}/wb_command -metric-mask "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii
  ${CARET7DIR}/wb_command -metric-mask "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii


  #Populate Highres fs_LR spec file.  Deform surfaces and other data according to native to folding-based registration selected above.  Regenerate inflated surfaces.
  for Surface in white midthickness pial ; do
    ${CARET7DIR}/wb_command -surface-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${RegSphere} "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii BARYCENTRIC "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Surface"."$HighResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Surface"."$HighResMesh"k_fs_LR.surf.gii
  done
  ${CARET7DIR}/wb_command -surface-generate-inflated "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".inflated."$HighResMesh"k_fs_LR.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".very_inflated."$HighResMesh"k_fs_LR.surf.gii -iterations-scale 2.5
  ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".inflated."$HighResMesh"k_fs_LR.surf.gii
  ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/"$Subject"."$HighResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".very_inflated."$HighResMesh"k_fs_LR.surf.gii
  
  for Map in thickness curvature ; do
    ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.shape.gii ${RegSphere} "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR.shape.gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
    ${CARET7DIR}/wb_command -metric-mask "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".atlasroi."$HighResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR.shape.gii
  done  
  ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii ${RegSphere} "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS."$HighResMesh"k_fs_LR.shape.gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii
  if [ ${RegName} = "MSMSulc" ] ; then
    ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_MSMSulc.native.shape.gii ${RegSphere} "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".ArealDistortion_MSMSulc."$HighResMesh"k_fs_LR.shape.gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii
  fi
  ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sulc.native.shape.gii ${RegSphere} "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sulc."$HighResMesh"k_fs_LR.shape.gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii

  for Map in aparc aparc.a2009s BA ; do
    if [ -e "$FreeSurferFolder"/label/"$hemisphere"h."$Map".annot ] ; then
      ${CARET7DIR}/wb_command -label-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii ${RegSphere} "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii BARYCENTRIC "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR.label.gii -largest
    fi
  done

  for LowResMesh in ${LowResMeshes} ; do
    #Copy Atlas Files
    cp "$SurfaceAtlasDIR"/"$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii
    cp "$GrayordinatesSpaceDIR"/"$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii
    if [ -e "$SurfaceAtlasDIR"/colin.cerebral."$Hemisphere".flat."$LowResMesh"k_fs_LR.surf.gii ] ; then
      cp "$SurfaceAtlasDIR"/colin.cerebral."$Hemisphere".flat."$LowResMesh"k_fs_LR.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".flat."$LowResMesh"k_fs_LR.surf.gii
      ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".flat."$LowResMesh"k_fs_LR.surf.gii
    fi

    #Create downsampled fs_LR spec files.   
    for Surface in white midthickness pial ; do
      ${CARET7DIR}/wb_command -surface-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${RegSphere} "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii BARYCENTRIC "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
      ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
    done
    ${CARET7DIR}/wb_command -surface-generate-inflated "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".inflated."$LowResMesh"k_fs_LR.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".very_inflated."$LowResMesh"k_fs_LR.surf.gii -iterations-scale 0.75
    ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".inflated."$LowResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".very_inflated."$LowResMesh"k_fs_LR.surf.gii
  
    for Map in sulc thickness curvature ; do
      ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.shape.gii ${RegSphere} "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.shape.gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
      ${CARET7DIR}/wb_command -metric-mask "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.shape.gii
    done  
    ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_FS.native.shape.gii ${RegSphere} "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".ArealDistortion_FS."$LowResMesh"k_fs_LR.shape.gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii
    if [ ${RegName} = "MSMSulc" ] ; then
      ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".ArealDistortion_MSMSulc.native.shape.gii ${RegSphere} "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".ArealDistortion_MSMSulc."$LowResMesh"k_fs_LR.shape.gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii
    fi
    ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".sulc.native.shape.gii ${RegSphere} "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sulc."$LowResMesh"k_fs_LR.shape.gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii

    for Map in aparc aparc.a2009s BA ; do
      if [ -e "$FreeSurferFolder"/label/"$hemisphere"h."$Map".annot ] ; then
        ${CARET7DIR}/wb_command -label-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native.label.gii ${RegSphere} "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii BARYCENTRIC "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.label.gii -largest
      fi
    done

    #Create downsampled fs_LR spec file in structural space.  
    for Surface in white midthickness pial ; do
      ${CARET7DIR}/wb_command -surface-resample "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Surface".native.surf.gii ${RegSphere} "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii BARYCENTRIC "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
      ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Surface"."$LowResMesh"k_fs_LR.surf.gii
    done
    ${CARET7DIR}/wb_command -surface-generate-inflated "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".inflated."$LowResMesh"k_fs_LR.surf.gii "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".very_inflated."$LowResMesh"k_fs_LR.surf.gii -iterations-scale 0.75
    ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".inflated."$LowResMesh"k_fs_LR.surf.gii
    ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$LowResMesh"k_fs_LR.wb.spec $Structure "$T1wFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".very_inflated."$LowResMesh"k_fs_LR.surf.gii
  done
done

STRINGII=""
for LowResMesh in ${LowResMeshes} ; do
  STRINGII=`echo "${STRINGII}${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k@${LowResMesh}k_fs_LR@atlasroi "`
done

#Create CIFTI Files
for STRING in "$AtlasSpaceFolder"/"$NativeFolder"@native@roi "$AtlasSpaceFolder"@"$HighResMesh"k_fs_LR@atlasroi ${STRINGII} ; do
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

  if [ ${RegName} = "MSMSulc" ] ; then
    ${CARET7DIR}/wb_command -cifti-create-dense-scalar "$Folder"/"$Subject".ArealDistortion_MSMSulc."$Mesh".dscalar.nii -left-metric "$Folder"/"$Subject".L.ArealDistortion_MSMSulc."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.ArealDistortion_MSMSulc."$Mesh".shape.gii
    ${CARET7DIR}/wb_command -set-map-names "$Folder"/"$Subject".ArealDistortion_MSMSulc."$Mesh".dscalar.nii -map 1 "${Subject}_ArealDistortion_MSMSulc"
    ${CARET7DIR}/wb_command -cifti-palette "$Folder"/"$Subject".ArealDistortion_MSMSulc."$Mesh".dscalar.nii MODE_USER_SCALE "$Folder"/"$Subject".ArealDistortion_MSMSulc."$Mesh".dscalar.nii -pos-user 0 1 -neg-user 0 -1 -interpolate true -palette-name ROY-BIG-BL -disp-pos true -disp-neg true -disp-zero false
  fi
  
  for Map in aparc aparc.a2009s BA ; do 
    if [ -e "$Folder"/"$Subject".L.${Map}."$Mesh".label.gii ] ; then
      ${CARET7DIR}/wb_command -cifti-create-label "$Folder"/"$Subject".${Map}."$Mesh".dlabel.nii -left-label "$Folder"/"$Subject".L.${Map}."$Mesh".label.gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-label "$Folder"/"$Subject".R.${Map}."$Mesh".label.gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
      ${CARET7DIR}/wb_command -set-map-names "$Folder"/"$Subject".${Map}."$Mesh".dlabel.nii -map 1 "$Subject"_${Map}
    fi
  done 
done

STRINGII=""
for LowResMesh in ${LowResMeshes} ; do
  STRINGII=`echo "${STRINGII}${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k@${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k@${LowResMesh}k_fs_LR ${T1wFolder}/fsaverage_LR${LowResMesh}k@${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k@${LowResMesh}k_fs_LR "`
done

#Add CIFTI Maps to Spec Files
for STRING in "$T1wFolder"/"$NativeFolder"@"$AtlasSpaceFolder"/"$NativeFolder"@native "$AtlasSpaceFolder"/"$NativeFolder"@"$AtlasSpaceFolder"/"$NativeFolder"@native "$AtlasSpaceFolder"@"$AtlasSpaceFolder"@"$HighResMesh"k_fs_LR ${STRINGII} ; do
  FolderI=`echo $STRING | cut -d "@" -f 1`
  FolderII=`echo $STRING | cut -d "@" -f 2`
  Mesh=`echo $STRING | cut -d "@" -f 3`
  for STRINGII in sulc@dscalar thickness@dscalar curvature@dscalar aparc@dlabel aparc.a2009s@dlabel BA@dlabel ; do
    Map=`echo $STRINGII | cut -d "@" -f 1`
    Ext=`echo $STRINGII | cut -d "@" -f 2`
    if [ -e "$FolderII"/"$Subject"."$Map"."$Mesh"."$Ext".nii ] ; then
      ${CARET7DIR}/wb_command -add-to-spec-file "$FolderI"/"$Subject"."$Mesh".wb.spec INVALID "$FolderII"/"$Subject"."$Map"."$Mesh"."$Ext".nii
    fi
  done
done