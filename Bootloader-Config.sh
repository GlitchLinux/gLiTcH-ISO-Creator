#!/bin/bash

# Ask user for the directory that should become a bootable Linux live ISO
read -p "Enter the directory path to make bootable: " ISO_DIR

# Verify the directory exists
if [ ! -d "$ISO_DIR" ]; then
    echo "Error: Directory $ISO_DIR does not exist."
    exit 1
fi

# Check if the live directory exists
if [ ! -d "$ISO_DIR/live" ]; then
    echo "Error: $ISO_DIR/live directory not found. This doesn't appear to be a live system directory."
    exit 1
fi

# Scan for kernel and initrd files
VMLINUZ=""
INITRD=""
SQUASHFS=""

# Look for vmlinuz file
for file in "$ISO_DIR/live"/vmlinuz*; do
    if [ -f "$file" ]; then
        VMLINUZ=$(basename "$file")
        break
    fi
done

# Look for initrd file
for file in "$ISO_DIR/live"/initrd*; do
    if [ -f "$file" ]; then
        INITRD=$(basename "$file")
        break
    fi
done

# Look for filesystem.squashfs
for file in "$ISO_DIR/live"/*.squashfs; do
    if [ -f "$file" ]; then
        SQUASHFS=$(basename "$file")
        break
    fi
done

# Verify we found the necessary files
if [ -z "$VMLINUZ" ]; then
    echo "Error: Could not find vmlinuz file in $ISO_DIR/live/"
    exit 1
fi

if [ -z "$INITRD" ]; then
    echo "Error: Could not find initrd file in $ISO_DIR/live/"
    exit 1
fi

if [ -z "$SQUASHFS" ]; then
    echo "Warning: Could not find squashfs file in $ISO_DIR/live/"
fi

# Ask for system name
read -p "Enter the name of the system in the ISO: " NAME

# Confirm detected files or allow user to override
echo "Detected files:"
echo "vmlinuz: $VMLINUZ"
echo "initrd: $INITRD"
echo "squashfs: $SQUASHFS"
read -p "Press enter to accept these or enter new values (vmlinuz initrd): " -r OVERRIDE

if [ ! -z "$OVERRIDE" ]; then
    read -ra OVERRIDE_ARRAY <<< "$OVERRIDE"
    VMLINUZ=${OVERRIDE_ARRAY[0]:-$VMLINUZ}
    INITRD=${OVERRIDE_ARRAY[1]:-$INITRD}
fi

# Create boot/grub directory if it doesn't exist
mkdir -p "$ISO_DIR/boot/grub"

# Generate grub.cfg
cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF
# GRUB.CFG 

set default="0"
set timeout=10

function load_video {
    insmod vbe
    insmod vga
    insmod video_bochs
    insmod video_cirrus
}

loadfont /boot/grub/share/grub/unicode.pf2

set gfxmode=640x480
load_video
insmod gfxterm
set locale_dir=/boot/grub/locale
set lang=C
insmod gettext
background_image -m stretch /boot/grub/splash.png
terminal_output gfxterm
insmod png
if background_image /boot/grub/splash.png; then
    true
else
    set menu_color_normal=cyan/blue
    set menu_color_highlight=white/blue
fi

menuentry "$NAME - LIVE" {
    linux /live/$VMLINUZ boot=live config quiet
    initrd /live/$INITRD
}

menuentry "$NAME - Boot ISO to RAM" {
    linux /live/$VMLINUZ boot=live config quiet toram
    initrd /live/$INITRD
}

menuentry "$NAME - Encrypted Persistence" {
    linux /live/$VMLINUZ boot=live components quiet splash noeject findiso=\${iso_path} persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/$INITRD
}

menuentry "GRUBFM - (UEFI)" {
    chainloader /EFI/GRUB-FM/E2B-bootx64.efi
}

EOF

# Create isolinux directory if it doesn't exist
mkdir -p "$ISO_DIR/isolinux"

# Generate isolinux.cfg
cat > "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
default vesamenu.c32
prompt 0
timeout 100

menu title $NAME-LIVE
menu tabmsg Press TAB key to edit
menu background splash.png

label live
  menu label $NAME - LIVE
  kernel /live/$VMLINUZ
  append boot=live config quiet initrd=/live/$INITRD

label live_ram
  menu label $NAME - Boot ISO to RAM
  kernel /live/$VMLINUZ
  append boot=live config quiet toram initrd=/live/$INITRD

label encrypted_persistence
  menu label $NAME - Encrypted Persistence
  kernel /live/$VMLINUZ
  append boot=live components quiet splash noeject findiso=\${iso_path} persistent=cryptsetup persistence-encryption=luks persistence initrd=/live/$INITRD

label netboot_bios
  menu label Netboot.xyz (BIOS)
  kernel /boot/grub/netboot.xyz/netboot.xyz.lkrn
  
EOF

echo "Configuration files created successfully:"
echo " - $ISO_DIR/boot/grub/grub.cfg"
echo " - $ISO_DIR/isolinux/isolinux.cfg"
