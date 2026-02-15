pkgs: with pkgs; [
  # Core toolchain bits expected by upstream bundles
  glibc
  curl
  icu
  libunwind
  libuuid
  lttng-ust
  openssl
  zlib

  # Mono/.NET friendly libraries
  krb5

  # GTK / desktop integration
  glib
  gdk-pixbuf
  gtk3
  gtk4
  libappindicator-gtk3
  libnotify
  libsecret
  libxkbcommon
  xdg-desktop-portal
  xdg-user-dirs
  xdg-utils
  pipewire
  systemd
  udev
  libudev0-shim

  # Audio
  alsa-lib
  libpulseaudio
  speechd-minimal

  # Font stack
  dejavu_fonts
  fontconfig
  freetype
  harfbuzz
  pango
  cairo

  # Media / GPU
  libdrm
  libGL
  libglvnd
  libgbm
  mesa
  libva
  libvdpau
  vulkan-loader
  pciutils
  stdenv.cc.cc
  cups

  # Runtime libraries used by Electron extensions
  nspr
  nss
  dbus
  at-spi2-atk
  at-spi2-core
  expat
  # X11 / Xorg
  libx11
  libxscrnsaver
  libxcomposite
  libxcursor
  libxdamage
  libxext
  libxfixes
  libxkbfile
  libxrandr
  libxrender
  libxtst
  libxi
  libxcb
  libxshmfence
  libxau
  libxdmcp
]
