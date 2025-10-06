pkgs:
with pkgs;
(
  [
    # core toolchain bits expected by upstream bundles
    glibc
    curl
    icu
    libunwind
    libuuid
    lttng-ust
    openssl
    zlib

    # mono/.NET friendly libraries
    krb5

    # GTK / desktop integration
    glib
    gdk-pixbuf
    gtk3
    gtk4
    cups
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

    # audio
    alsa-lib
    libpulseaudio
    speechd-minimal

    # font stack
    dejavu_fonts
    fontconfig
    freetype
    harfbuzz
    pango
    cairo

    # media / GPU
    libdrm
    libGL
    libglvnd
    libgbm
    mesa
    libva
    libvdpau
    vulkan-loader
    pciutils

    # scripting runtimes used by extensions
    nspr
    nss
    dbus
    at-spi2-atk
    at-spi2-core
    expat
    stdenv.cc.cc
  ]
  ++ (with pkgs.xorg; [
    libX11
    libXScrnSaver
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXkbfile
    libXrandr
    libXrender
    libXtst
    libXi
    libxcb
    libxshmfence
    libXau
    libXdmcp
  ])
)
