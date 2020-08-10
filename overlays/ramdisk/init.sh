#!/rescue/sh

PATH="/rescue"

if [ "`ps -o command 1 | tail -n 1 | ( read c o; echo ${o} )`" = "-s" ]; then
	echo "==> Running in single-user mode"
	SINGLE_USER="true"
fi

echo "==> Remount rootfs as read-write"
mount -u -w /

echo "==> Make mountpoints"
mkdir -p /cdrom /usr/dists /memdisk /memusr /mnt /sysroot /usr /tmp

echo "==> Waiting for FURYBSD media to initialize"
while : ; do
    [ -e "/dev/iso9660/FURYBSD" ] && echo "==> Found /dev/iso9660/FURYBSD" && break
    sleep 1
done

echo "==> Mount cdrom"
mount_cd9660 /dev/iso9660/FURYBSD /cdrom

if [ -f "/cdrom/data/system.uzip" ] ; then
  mdmfs -P -F /cdrom/data/system.uzip -o ro md.uzip /sysroot
else
  rm -rf /sysroot
  rm -rf /memusr
fi

if [ -f "/cdrom/data/dists.uzip" ] ; then
  mdmfs -P -F /cdrom/data/dists.uzip -o ro md.uzip /usr/dists
fi

# Make room for backup in /tmp
mount -t tmpfs tmpfs /tmp

echo "==> Mount swap-based memdisk"
mdmfs -s 2048m md /memdisk || exit 1

if [ -d "/sysroot" ] ; then
  dump -0f - /dev/md1.uzip | (cd /memdisk; restore -rf -)
  rm /memdisk/restoresymtable
  kenv vfs.root.mountfrom=ufs:/dev/md2
  kenv init_script="/init-reroot.sh"
fi

if [ -f "/usr/dists/base.txz" ] ; then
  echo "==> Extracting kernel.txz"
  cd /usr/dists && tar -xf kernel.txz -C /memdisk
  echo "==> Extracting base.txz"
  cd /usr/dists && tar -xf base.txz -C /memdisk
  cp /etc/fstab /memdisk/etc/
  cp /init-reroot.sh /memdisk
  kenv vfs.root.mountfrom=ufs:/dev/md2
  kenv init_script="/init-reroot.sh"
  #kenv -u init_script
fi

if [ "$SINGLE_USER" = "true" ]; then
	echo "Starting interactive shell in temporary rootfs ..."
	exit 0
fi

kenv init_shell="/rescue/sh"
exit 0
