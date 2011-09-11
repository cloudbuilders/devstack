# Concepts

On a ubuntu linux server, you can create nfs powered netboot of ubuntu.  To do this you must:

* configure dhcp to send pxe instructions
* create a kernel/ramdisk that supports nfs
* create a nfs export per host you want to boot
* setup a pxeconfig for each host (mapping mac address to nfs export)
* serve kernel, ramdisk, and pxeconfig via tftp

Then you can manage nfs exported filesystems on the host as you would normal directories (copy/snapshot/backup/update) - allowing you to launch new (development/testing) machines in seconds.

## dnsmasq options on linux router

    dhcp-boot=pxelinux.0,aqua,192.168.2.2

## add ubuntu pxe installer

This gives us a base netboot install, that we can add netboot run.  (there has to be an easier way to get a pxelinux.0 file)

    cp /usr/lib/syslinux/pxelinux.0 /var/lib/tftpboot
    mkdir /var/lib/tftpboot/pxelinux.cfg

## linux ubuntu server: setup nfs

    apt-get install -y nfs-kernel-server
    mkdir /nfs
    echo "/nfs             192.168.2.*(rw,no_root_squash,async,insecure)" >> /etc/exports
    exportfs -rv
    
## build shared kernel/ramdisk that works with nfs

    cp /boot/vmlinuz-`uname -r` /var/lib/tftpboot

Update boot/modules in /etc/initramfs-tools/initramfs.conf

    BOOT=nfs
    MODULES=most # most instructions say netboot - but that won't include drivers to use local disk

Then build initrd.img

    mkinitramfs -o /var/lib/tftpboot/initrd.img-`uname -r`

## Per machine setup
    
### Create a /var/lib/tftpboot/pxelinux.cfg/01-lower-case-mac-address-with-dashes

    prompt 0
    timeout 0
    default net
    
    LABEL net
    KERNEL vmlinuz-2.6.38-8-generic
    APPEND root=/dev/nfs initrd=initrd.img-2.6.38-8-generic nfsroot=192.168.2.2:/nfs/NAME ip=dhcp rw

### Setup the filesystem

You can bootstrap a clean install of natty (or oneiric, maverick, various debian versions) from scratch via

    debootstrap natty /nfs/NAME
    
Copy over the modules that match the kernel/ramdisk we setup above

    cp -pr /lib/modules/`uname -r` /nfs/NAME/lib/modules

Or just bootstrap a single filesytem and create a copy each time you create a new machine

    debootstrap natty /nfs/proto # one time only
    cp -pr /nfs/proto /nfs/NAME

Recommended additional tweaks:

* update hostname in filesytem
* set password
* add more useful apt source list
* listuse chroot to update/install apt packages

# todo

* apt-cache or mirror?


