### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## based on AnyKernel3

### AnyKernel setup
# global properties
properties() { '
kernel.string=Maybe Kernel R1.2 by voxelsy & iLRTx45557
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
# boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

# GKI check
kernel_version=$(cat /proc/version | awk -F '-' '{print $1}' | awk '{print $3}')
case $kernel_version in
    5.10*) ksu_supported=true ;;
    5.15*) ksu_supported=true ;;
    6.1*) ksu_supported=true ;;
    6.6*) ksu_supported=true ;;
    6.12*) ksu_supported=true ;;
    *) ksu_supported=false ;;
esac

ui_print " " "  -> MaybeKernel GKI supported: $ksu_supported"
$ksu_supported || abort "  -> Non-GKI device, aborting."

# boot install
split_boot

if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi

ui_print " "
ui_print " "
ui_print "Thanks for using MaybeKernel"
ui_print "GKI kernel with KMI module restrictions lifted."
ui_print "Vendor modules from /vendor_dlkm and /system_dlkm load unmodified."
ui_print " "
ui_print "Flashed Image: $(strings "$AKHOME/Image" | grep -m1 -oE 'Linux version [^ ]+' | sed 's/Linux version //')"
ui_print " "
ui_print "Issues with this kernel are the user's own risk."
ui_print " "