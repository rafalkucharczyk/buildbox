#!/bin/bash -exu
# --------------------------------------------------------------------------------------------------
# Prepares initial buildbox repository
# --------------------------------------------------------------------------------------------------
target_dir=$1

mkdir -p $target_dir

sudo debootstrap --arch=i386 precise $target_dir/rootfs http://archive.ubuntu.com/ubuntu/

# --------------------------------------------------------------------------------------------------
pushd $target_dir
  sudo chown -R `id -u`:`id -g` .
  rm -f rootfs/var/cache/apt/archives/*.deb
  rm -f rootfs/var/log/wtmp rootfs/run/motd rootfs/run/utmp

  touch rootfs/home/.empty
  touch rootfs/etc/apt/preferences.d/.empty
  touch rootfs/var/lib/dpkg/updates/.empty

  cat > rootfs/etc/skel/.profile <<'EOF'
export PS1="[\[\e[0;32m\]\u@buildroot \W]# \[\e[m\]"
EOF

  cat > rootfs/root/.profile <<'EOF'
export PS1="[\[\e[0;31m\]\u@buildroot \W]# \[\e[m\]"
EOF

  cat > rootfs/etc/apt/apt.conf.d/01ubuntu <<EOF
APT
{
   Install-Recommends "false";
};
EOF

  git init
  git add .
  git commit -m"[buildbox] initial commit"

  cat > .gitignore <<EOF
rootfs/dev/*
rootfs/proc
rootfs/sys
rootfs/tmp
rootfs/home/*
rootfs/host/*
rootfs/etc/group
rootfs/etc/profile.d
rootfs/var/log/wtmp
rootfs/run/motd
rootfs/run/utmp
rootfs/.buildbox_variant
EOF

  git add .gitignore
  git commit -m"[buildbox] ignore files modified during setup"

  git config --bool core.bare true
  rm -rf * .gitignore
popd

