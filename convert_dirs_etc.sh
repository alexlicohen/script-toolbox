#!/bin/bash
set -e
#created to get converted/registered study files to T1.mgz space
#then runs import to spec with writing ascii file
#created 2/21/15 JMT

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------
Usage() {
    echo "Usage: `basename $0` [options] e.g. convert_dirs_etc.sh --path=~/Desktop/bladibla --sub=testr" 
	echo "mandatory input "
	echo "--path=xxx"
	echo "--sub or --list=..."
	echo "--i"
	echo " " 
	echo "--path		set the path_directory where both "FREESURFER" folder and "SUBJECT" folder is in"
    echo "--sub			sets the subject. if you have a list, run the lower option]"
    echo "--list		the file list that needs to go run"
	echo "--i 			the sourcefile (this will be saved in /xfms folder in the "SUBJECT" directory as regheader.source.dat)"
	echo "--ilist		if you have more than one file to run it on, separated by @, chose from (gmdir,wmdir,psir,gair,T2,flair ORRRR allnov (all 6) or alldod (gmdir,wmdir,psir)"
	echo "--anything else"
    #echo "       `basename $0` [options] --list=<list of image names OR a text file>"
    echo " "
	echo "need to add, but for now script runs from alextoolbox is in /Volumes/dtilab/Desktop/alextoolbox"
}

#change to be specified or in path (running this from Mac without ssh)
toolbox=/Volumes/dtilab/Desktop/alextoolbox


# extracts the option name from any version (-- or -)
get_opt1() {
    arg=`echo $1 | sed 's/=.*//'`
    echo $arg
}

# get arg for -- options
get_arg1() {
    if [ X`echo $1 | grep '='` = X ] ; then 
        echo "Option $1 requires an argument" 1>&2
        exit 1
    else 
        arg=`echo $1 | sed 's/.*=//'`
        if [ X$arg = X ] ; then
            echo "Option $1 requires an argument" 1>&2
            exit 1
        fi
        echo $arg
    fi
}

if [ $# -eq 0 ] ; then Usage; exit 0; fi
if [ $# -lt 3 ] ; then Usage; exit 1; fi
        while [ $# -ge 1 ] ; do
            iarg=`get_opt1 $1`
        
multipleimages=no
multiplefiles=no
        
case "$iarg"
        in
        --list)
        		sublist=`get_arg1 $1`;
                multipleimages=yes
                shift;;
        --path)
                PATH_DIR=`get_arg1 $1`;
                shift;;
        --sub)
                nam=`get_arg1 $1`;
                shift;;
		--i)	
				file=`get_arg1 $1`;
				shift;;
				
		--ilist) 
				srclist=`get_arg1 $1`;
				multiplefiles=yes
				shift;;
		esac

done

if [ $multipleimages = yes ] ; then
	list =`cat "$sublist" | awk '{printf $0 " "}'`
	else
		list="$nam"
	fi

if [ $multiplefiles = yes ] ; then
	if [ $srclist = allnov ] ; then
		file="gmdir wmdir psir gair T2 flair"
	elif [ $srclist = alldod ] ; then
		file="gmdir wmdir psir"
	else
		file=$srclist
	fi
fi
	
for sub in "$list"
do
	src=$PATH_DIR/$sub
	trg=$PATH_DIR/FREESURFER/$sub
	SUBJECTS_DIR=$PATH_DIR/FREESURFER
	if [ -d $src/xfms ] ; then
		echo "$src/xfms already exists"
		else
			mkdir $src/xfms
	fi
	if [ -d $src/pos ] ; then
		echo "$src/pos already exists"
		else
			mkdir $src/pos
	fi
	
	echo $file
	for i in $file
	do
		echo "Starting conversion on $i"
		echo "source directory is $src"
		echo "target directory is $trg"
		if [ $i = gmdir ] ; then fil="GMDIR_fsl.nii.gz"
			contrast=t1
		elif [ $i = wmdir ] ; then fil="WMDIR_fsl.nii.gz"
			contrast=t2
		elif [ $i = gair ] ; then fil="GAIR_fsl.nii.gz"
			contrast=t1
		elif [ $i = psir ] ; then fil="PSIR_fsl.nii.gz"
			contrast=t1
		elif [ $i = T2 ] ; then fil="3DT2_fsl.nii.gz"
			contrast=t2
		elif [ $i = flair ] ; then fil="3DFLAIR_fsl.nii.gz"
			contrast=t2
		else echo "are you sure you have a correct file name"
		fi

		negval=`fslstats $src/$fil -R | awk '{print $1}'`
		filpos="pos/"$fil"pos.nii.gz"
		fslmaths $src/$fil -sub "$negval" $src/$filpos	
		bbregister --s $sub --mov $src/$filpos --$contrast --reg $src/xfms/register."$i".dat --init-header
		#echo tkregister2 --mov $src/$fil --reg $src/xfms/register."$i".dat --surf
		echo "tkregister2 --mov $src/$fil --reg $src/xfms/register."$i".dat --surf" >> $src/log_check_reg.txt
		mri_vol2vol --mov $src/$fil --targ $trg/mri/orig.mgz --reg $src/xfms/register."$i".dat --o $trg/hcp/"$i".nii.gz --cubic
		fslreorient2std $trg/hcp/"$i".nii.gz $trg/hcp/"$i".nii.gz
		$toolbox/ImportVolumeToSpec.sh --subject="$sub" --path="$SUBJECTS_DIR" --layers=corticallayer_0.66@corticallayer_0.33@subcortlayer_mm_1.3@subcortlayer_mm_2 --onefile=yes --inputname="$i"
	done
	$src/log_check_reg.txt
	cd $trg/mri; fslview $file
done

		