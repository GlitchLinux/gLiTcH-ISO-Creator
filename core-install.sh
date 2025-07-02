# LINUX LIVE - BIOS & UEFI 
# Isolinux & grub2 Chainload

sudo apt update && sudo apt install -y syslinux-utils grub-efi-amd64-bin mtools wget lzma

sudo rm -rf /tmp/bootfiles && sudo mkdir /tmp/bootfiles && cd /tmp/bootfiles
sudo wget https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/HYBRID-BASE.tar.lzma
sudo unlzma HYBRID-BASE.tar.lzma && sudo tar -xvf HYBRID-BASE.tar
sudo rm HYBRID-BASE.tar && cd HYBRID-BASE
