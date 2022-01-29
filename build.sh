#!/bin/bash
echo ""
echo "Pixel Experience 11 Treble Buildbot"
echo "ATTENTION: this script syncs repo on each run"
echo "Executing in 5 seconds - CTRL-C to exit"
echo ""
sleep 5

# Abort early on error
set -eE
trap '(\
echo;\
echo \!\!\! An error happened during script execution;\
echo \!\!\! Please check console output for bad sync,;\
echo \!\!\! failed patch application, etc.;\
echo\
)' ERR

START=`date +%s`
BUILD_DATE="$(date +%Y%m%d)"
BL=$PWD/treble_build_pe
BRANCH=$1
[ "$BRANCH" == "" ] && BRANCH="eleven"
[ "$BRANCH" == "eleven" ] && BUILD="PixelExperience" || BUILD="PixelExperience_Plus"

echo "Preparing local manifest"
mkdir -p .repo/local_manifests
cp $BL/manifest.xml .repo/local_manifests/pixel.xml
echo ""

echo "Syncing repos"
repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
echo ""

echo "Cloning dependecy repos"
[ ! -d sas-creator ] && git clone https://github.com/AndyCGYan/sas-creator
rm -rf treble_app && git clone https://github.com/phhusson/treble_app

echo "Setting up build environment"
source build/envsetup.sh &> /dev/null
echo ""

echo "Applying prerequisite patches"
bash $BL/apply-patches.sh $BL prerequisite $BRANCH
echo ""

echo "Applying PHH patches"
rm -f device/*/sepolicy/common/private/genfs_contexts
cd device/phh/treble
cp $BL/pe.mk .
bash generate.sh pe
cd ../../..
bash $BL/apply-patches.sh $BL phh $BRANCH
echo ""

echo "Applying personal patches"
bash $BL/apply-patches.sh $BL personal $BRANCH
echo ""

echo "CHECK PATCH STATUS NOW!"
sleep 5
echo ""

export WITHOUT_CHECK_API=true
mkdir -p ~/builds

buildTrebleApp() {
    cd treble_app
    bash build.sh
    cp TrebleApp.apk ../vendor/hardware_overlay/TrebleApp/app.apk
    cd ..
}

buildVariant() {
    lunch ${1}-userdebug
    make installclean
    njob="$(nproc)"
    until make -j$njob systemimage
    do
        (( njob -= 2 ))
        (( njob > 0 ))
    done
    make vndk-test-sepolicy
    mv $OUT/system.img ~/builds/system-"$1".img
}

buildSasImages() {
    cd sas-creator
    BASE_IMAGE=~/builds/system-treble_arm_bvN.img
    if [ -f $BASE_IMAGE ]
    then
        sudo bash run.sh 32 $BASE_IMAGE
        xz -c s.img -T0 > ~/builds/"$BUILD"_arm-aonly-11.0-$BUILD_DATE-UNOFFICIAL.img.xz
        xz -c $BASE_IMAGE -T0 > ~/builds/"$BUILD"_arm-ab-11.0-$BUILD_DATE-UNOFFICIAL.img.xz
        rm -rf $BASE_IMAGE
    fi
    BASE_IMAGE=~/builds/system-treble_a64_bvN.img
    if [ -f $BASE_IMAGE ]
    then
        sudo bash lite-adapter.sh 32 $BASE_IMAGE
        xz -c s.img -T0 > ~/builds/"$BUILD"_arm32_binder64-ab-vndklite-11.0-$BUILD_DATE-UNOFFICIAL.img.xz
        xz -c $BASE_IMAGE -T0 > ~/builds/"$BUILD"_arm32_binder64-ab-11.0-$BUILD_DATE-UNOFFICIAL.img.xz
        rm -rf $BASE_IMAGE
    fi
    BASE_IMAGE=~/builds/system-treble_arm64_bvN.img
    if [ -f $BASE_IMAGE ]
    then
        sudo bash run.sh 64 $BASE_IMAGE
        xz -c s.img -T0 > ~/builds/"$BUILD"_arm64-aonly-11.0-$BUILD_DATE-UNOFFICIAL.img.xz
        sudo bash lite-adapter.sh 64 $BASE_IMAGE
        xz -c s.img -T0 > ~/builds/"$BUILD"_arm64-ab-vndklite-11.0-$BUILD_DATE-UNOFFICIAL.img.xz
        xz -c $BASE_IMAGE -T0 > ~/builds/"$BUILD"_arm64-ab-11.0-$BUILD_DATE-UNOFFICIAL.img.xz
        rm -rf $BASE_IMAGE
    fi
    cd ..
}

buildTrebleApp
buildVariant treble_arm64_bvN
buildSasImages
ls ~/builds | grep $BUILD

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo ""
