# Import the BET'd T1 in fsAnat space to the HCP dir
fslreorient2std "$StudyFolder"/"$Subject"/mri/T1_brain.nii.gz >> "$HCPFolder"/T1_brain.fslreorient2std.mat
fslreorient2std "$StudyFolder"/"$Subject"/mri/T1_brain.nii.gz "$HCPFolder"/T1_brain.nii.gz

# Process the raw NIFTI BOLD data through FEAT, then FIX
### insert FEAT script? from the FEAT gui settings...
fix fMRI.feat /usr/local/fix/training_files/Standard.RData 20 -m

# or use ICA_AROMA?
python2.7 /usr/local/ICA-AROMA/ICA_AROMA.py -in /projects/mayoresearch/fc01/fMRI.feat/filtered_func_data.nii.gz -out /projects/mayoresearch/fc01/fMRI.feat/ICA_AROMA -affmat /projects/mayoresearch/fc01/fMRI.feat/reg/example_func2highres.mat -warp /projects/mayoresearch/fc01/fMRI.feat/reg/highres2standard_warp.nii.gz -mc /projects/mayoresearch/fc01/fMRI.feat/mc/prefiltered_func_data_mcf.par