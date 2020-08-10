#!/bin/sh

version="12.1"
pkgset="branches/2020Q1"
desktop=$1
tag=$2
cwd="`realpath | sed 's|/scripts||g'`"
workdir="/usr/local"
livecd="${workdir}/furybsd"
cache="${livecd}/cache"
arch=AMD64
base="${cache}/${version}/base"
packages="${cache}/packages"
ports="${cache}/furybsd-ports-master"
iso="${livecd}/iso"
uzip="${livecd}/uzip"
cdroot="${livecd}/cdroot"
ramdisk_root="${cdroot}/data/ramdisk"
vol="furybsd"
label="FURYBSD"
isopath="${iso}/${vol}.iso"
export DISTRIBUTIONS="kernel.txz base.txz"
export BSDINSTALL_DISTSITE="http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/12.1-RELEASE/"
export BSDINSTALL_CHROOT="/usr/local/furybsd/uzip"
export BSDINSTALL_DISTDIR="/usr/local/furybsd/cache/12.1/base"

# Only run as superuser
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Make sure git is installed
if [ ! -f "/usr/local/bin/git" ] ; then
  echo "Git is required"
  echo "Please install it with pkg install git or pkg install git-lite first"
  exit 1
fi

# Make sure poudriere is installed
if [ ! -f "/usr/local/bin/poudriere" ] ; then
  echo "Poudriere is required"
  echo "Please install poudriere with pkg install poudriere or pkg install poudriere-devel first"
  exit 1
fi

case $desktop in
  'kde')
    export desktop="kde"
    export edition="KDE"
    ;;
  'gnome')
    export desktop="gnome"
    export edition="GNOME"
    ;;
  'xfce')
    export desktop="xfce"
    export edition="XFCE"
    ;;
  *)
    export desktop="core"
    export edition="CORE"
    ;;
esac

# Get the version tag
if [ -z "$2" ] ; then
  rm /usr/local/furybsd/tag >/dev/null 2>/dev/null
  export vol="FuryBSD-${version}-${edition}"
else
  rm /usr/local/furybsd/version >/dev/null 2>/dev/null
  echo "${2}" > /usr/local/furybsd/tag
  export vol="FuryBSD-${version}-${edition}-${tag}"
fi

label="FURYBSD"
isopath="${iso}/${vol}.iso"

workspace()
{
  umount ${uzip}/var/cache/pkg >/dev/null 2>/dev/null
  umount ${ports} >/dev/null 2>/dev/null
  rm -rf ${ports} >/dev/null 2>/dev/null
  umount ${cache}/furybsd-packages/ >/dev/null 2>/dev/null
  rm ${cache}/master.zip >/dev/null 2>/dev/null
  umount ${uzip}/dev >/dev/null 2>/dev/null
  if [ -d "${livecd}" ] ;then
    chflags -R noschg ${uzip} ${cdroot} >/dev/null 2>/dev/null
    rm -rf ${uzip} ${cdroot} ${ports} >/dev/null 2>/dev/null
  fi
  mkdir -p ${livecd} ${base} ${iso} ${packages} ${uzip} ${ramdisk_root}/dev ${ramdisk_root}/etc >/dev/null 2>/dev/null
}

base()
{
  if [ ! -f "${base}/base.txz" ] ; then 
    bsdinstall distfetch
  fi
  
  if [ ! -f "${base}/kernel.txz" ] ; then
    cd ${base}
    bsdinstall distfetch
  fi
  bsdinstall distextract
#  cp /etc/resolv.conf ${uzip}/etc/resolv.conf
#  chroot ${uzip} env PAGER=cat freebsd-update fetch --not-running-from-cron
#  chroot ${uzip} freebsd-update install
}

poudriere_jail()
{
  # Check if jail exists
  poudriere jail -l | grep -q furybsd
  if [ $? -eq 1 ] ; then
    # If jail does not exist create it
    poudriere jail -c -j furybsd -v ${version}-RELEASE -K GENERIC
  else
    # Update jail if it exists
    poudriere jail -u -j furybsd
  fi
}

poudriere_ports()
{
  # Check if ports tree exists
  poudriere ports -l | grep -q furybsd
  if [ $? -eq 1 ] ; then
    # If ports tree does not exist create it
    poudriere ports -c -p furybsd-ports -B ${pkgset} -m git
  else
    # Update ports tree if it exists
    poudriere ports -u -p furybsd-ports -B ${pkgset} -m git
  fi
}

poudriere_bulk()
{
  poudriere bulk -j furybsd -p furybsd-ports -f settings/ports.${desktop}
}

poudriere_image()
{
  poudriere image -t tar -j furybsd -p furybsd-ports -h furybsd -n furybsd -f settings/ports.${desktop}
  tar -xf /data/images/furybsd.txz -C ${uzip}  
}

packages()
{
  cp /etc/resolv.conf ${uzip}/etc/resolv.conf
  mkdir ${uzip}/var/cache/pkg
  mount_nullfs ${packages} ${uzip}/var/cache/pkg
  mount -t devfs devfs ${uzip}/dev
  cat ${cwd}/settings/packages.common | xargs pkg-static -c ${uzip} install -y
  cat ${cwd}/settings/packages.${desktop} | xargs pkg-static -c ${uzip} install -y
  rm ${uzip}/etc/resolv.conf
  umount ${uzip}/var/cache/pkg
  umount ${uzip}/dev
}

rc()
{
  if [ ! -f "${uzip}/etc/rc.conf" ] ; then
    touch ${uzip}/etc/rc.conf
  fi
  if [ ! -f "${uzip}/etc/rc.conf.local" ] ; then
    touch ${uzip}/etc/rc.conf.local
  fi
  cat ${cwd}/settings/rc.conf.common | xargs chroot ${uzip} sysrc -f /etc/rc.conf.local
  cat ${cwd}/settings/rc.conf.${desktop} | xargs chroot ${uzip} sysrc -f /etc/rc.conf.local
}

live-settings()
{
  cp ${cwd}/furybsd-live-helper ${uzip}/opt/local/bin/
  cp ${cwd}/furybsd-init-helper ${uzip}/opt/local/bin/
  cp ${cwd}/furybsd-install ${uzip}/opt/local/bin/
  cp ${cwd}/fury-helper.desktop ${uzip}/usr/local/etc/xdg/autostart/
  cp ${cwd}/nginx.conf ${uzip}/usr/local/etc/nginx/nginx.conf
  cp ${uzip}/usr/local/www/phpsysinfo/phpsysinfo.ini.new ${uzip}/usr/local/www/phpsysinfo/phpsysinfo.ini
  cp ${uzip}/usr/local/etc/php.ini-production ${uzip}/usr/local/etc/php.ini
}

repos()
{
  if [ ! -d "${cache}/furybsd-xfce-settings" ] ; then
    git clone https://github.com/furybsd/furybsd-xfce-settings.git ${cache}/furybsd-xfce-settings
  else
    cd ${cache}/furybsd-xfce-settings && git pull
  fi
  if [ ! -d "${cache}/furybsd-wallpapers" ] ; then
    git clone https://github.com/furybsd/furybsd-wallpapers.git ${cache}/furybsd-wallpapers
  else
    cd ${cache}/furybsd-wallpapers && git pull
  fi
  if [ ! -d "${cache}/furybsd-xorg-tool" ] ; then
    git clone https://github.com/furybsd/furybsd-xorg-tool.git ${cache}/furybsd-xorg-tool
  else
    cd ${cache}/furybsd-xorg-tool && git pull
  fi
  if [ ! -d "${cache}/furybsd-wifi-tool" ] ; then
    git clone https://github.com/furybsd/furybsd-wifi-tool.git ${cache}/furybsd-wifi-tool
  else
    cd ${cache}/furybsd-wifi-tool && git pull
  fi
}

skel()
{
  mkdir -p ${uzip}/usr/share/skel/dot.config/xfce4/xfconf/xfce-perchannel-xml
  cp -R ${cache}/furybsd-xfce-settings/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/* ${uzip}/usr/share/skel/dot.config/xfce4/xfconf/xfce-perchannel-xml/
}

opt()
{
  mkdir -p ${uzip}/opt/local/bin
  mkdir -p ${uzip}/opt/local/share/backgrounds/furybsd
  cp ${cache}/furybsd-xorg-tool/bin/* ${uzip}/opt/local/bin/
  cp -R ${cache}/furybsd-wallpapers/*.png ${uzip}/opt/local/share/backgrounds/furybsd/
  cp ${cache}/furybsd-wifi-tool/bin/* ${uzip}/opt/local/bin/
}

opt_core()
{
  mkdir -p ${uzip}/opt/local/bin
  cp ${cwd}/furybsd-core-init ${uzip}/opt/local/bin/
}

user()
{
  mkdir -p ${uzip}/usr/home/liveuser/Desktop
  cp -R ${cwd}/xorg.conf.d/ ${uzip}/usr/home/liveuser/xorg.conf.d
  cp ${cwd}/fury-config-xorg.desktop ${uzip}/usr/home/liveuser/Desktop/
  cp ${cwd}/fury-config-wifi.desktop ${uzip}/usr/home/liveuser/Desktop/
  cp ${cwd}/fury-install.desktop ${uzip}/usr/home/liveuser/Desktop/
  cp ${cwd}/fury-sysinfo.desktop ${uzip}/usr/home/liveuser/Desktop/
  chroot ${uzip} echo furybsd | chroot ${uzip} pw mod user root -h 0
  chroot ${uzip} pw useradd liveuser -u 1000 \
  -c "Live User" -d "/home/liveuser" \
  -g wheel -G operator -m -s /bin/csh -k /usr/share/skel -w none
  chroot ${uzip} pw groupadd liveuser -g 1000
  chroot ${uzip} echo furybsd | chroot ${uzip} pw mod user liveuser -h 0
  chroot ${uzip} chown -R 1000:1000 /usr/home/liveuser
  chroot ${uzip} pw groupmod wheel -m liveuser
  chroot ${uzip} pw groupmod video -m liveuser
  chroot ${uzip} pw groupmod webcamd -m liveuser
}

dm()
{
  case $desktop in
    'kde')
      cp ${cwd}/sddm.conf ${uzip}/usr/local/etc/
      ;;
    'gnome')
      cp ${cwd}/custom.conf ${uzip}/usr/local/etc/gdm/custom.conf
      ;;
    'xfce')
      cp ${cwd}/lightdm.conf ${uzip}/usr/local/etc/lightdm/
      chroot ${uzip} sed -i '' -e 's/memorylocked=128M/memorylocked=256M/' /etc/login.conf
      chroot ${uzip} cap_mkdb /etc/login.conf
      ;;
    *)
      ;;
  esac
}

installed-settings()
{
  if [ ! -d "${cache}/furybsd-common-settings" ] ; then
    git clone https://github.com/furybsd/furybsd-common-settings.git ${cache}/furybsd-common-settings
  else
    cd ${cache}/furybsd-common-settings && git pull
  fi
  cp -R ${cache}/furybsd-common-settings/etc/* ${uzip}/usr/local/etc/
}

cdroot()
{
  cp -R ${cwd}/overlays/uzip/ ${uzip}
  install -o root -g wheel -m 755 -d "${cdroot}"
}

uzip_usr()
{
  makefs "${cdroot}/data/usr.ufs" "${uzip}/usr"
  mkuzip -o "${cdroot}/data/usr.uzip" "${cdroot}/data/usr.ufs"
  rm -f "${cdroot}/data/usr.ufs"
  chflags -R noschg ${uzip}/usr
  rm -rf ${uzip}/usr
}

uzip_system() 
{
  makefs "${cdroot}/data/system.ufs" "${uzip}"
  mkuzip -o "${cdroot}/data/system.uzip" "${cdroot}/data/system.ufs"
  rm -f "${cdroot}/data/system.ufs"
}

dists()
{
  mkdir -p ${cdroot}/data
  makefs "${cdroot}/data/dists.ufs" ${base}
  mkuzip -o "${cdroot}/data/dists.uzip" "${cdroot}/data/dists.ufs"
  rm -f "${cdroot}/data/dists.ufs"
}

ramdisk() 
{
  cp -R ${cwd}/overlays/ramdisk/ ${ramdisk_root}
  cd "${uzip}" && tar -cf - rescue | tar -xf - -C "${ramdisk_root}"
  # touch "${ramdisk_root}/etc/fstab"
  cp ${cwd}/fstab ${ramdisk_root}/etc
  cp ${cwd}/init-reroot.sh ${ramdisk_root}/init-reroot.sh
  cp ${uzip}/etc/login.conf ${ramdisk_root}/etc/login.conf
  makefs -b '10%' "${cdroot}/data/ramdisk.ufs" "${ramdisk_root}"
  gzip "${cdroot}/data/ramdisk.ufs"
  rm -rf "${ramdisk_root}"
}

boot() 
{
  cp -R ${cwd}/overlays/boot/ ${cdroot}
  cd "${uzip}" && tar -cf - --exclude boot/kernel boot | tar -xf - -C "${cdroot}"
  for kfile in kernel geom_uzip.ko nullfs.ko tmpfs.ko unionfs.ko xz.ko; do
  tar -cf - boot/kernel/${kfile} | tar -xf - -C "${cdroot}"
  done
}

boot_core()
{
  cp -R ${cwd}/overlays/core/ ${cdroot}
  cd "${uzip}" && tar -cf - --exclude boot/kernel boot | tar -xf - -C "${cdroot}"
  for kfile in kernel geom_uzip.ko nullfs.ko tmpfs.ko xz.ko; do
  tar -cf - boot/kernel/${kfile} | tar -xf - -C "${cdroot}"
  done
}

image() 
{
  sh ${cwd}/scripts/mkisoimages.sh -b $label $isopath ${cdroot}
}

image_core()
{
  sh /usr/src/release/amd64/mkisoimages.sh -b ${label} ${isopath} ${uzip}
}

cleanup()
{
  if [ -d "${livecd}" ] ; then
    chflags -R noschg ${uzip} ${cdroot} >/dev/null 2>/dev/null
    rm -rf ${uzip} ${cdroot} >/dev/null 2>/dev/null
  fi
}

case $desktop in
  'kde')
    workspace
    poudriere_jail
    poudriere_ports
    poudriere_bulk
    poudriere_image
    packages
    rc
    repos
    opt
    skel
    user
    live-settings
    installed-settings
    dm
    cdroot
    uzip_usr
    uzip_system
    ramdisk
    boot
    image
    cleanup
    ;;
  'gnome')
    workspace
    poudriere_jail
    poudriere_ports
    poudriere_bulk
    poudriere_image
    packages
    rc
    repos
    opt
    skel
    user
    live-settings
    installed-settings
    dm
    cdroot
    uzip_usr
    uzip_system
    ramdisk
    boot
    image
    cleanup
    ;;
  'xfce')
    workspace
    poudriere_jail
    poudriere_ports
    poudriere_bulk
    poudriere_image
    packages
    rc
    repos
    opt
    skel
    user
    live-settings
    installed-settings
    dm
    cdroot
    uzip_usr
    uzip_system
    ramdisk
    boot
    image
    cleanup
    ;;
  *)
    workspace
    base
    #dists
    #ramdisk
    #boot_core
    #image
    opt_core
    image_core
    #cleanup
    ;;
esac
