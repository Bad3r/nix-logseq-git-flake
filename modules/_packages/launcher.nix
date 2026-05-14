{
  logseqFhs,
  pkgs,
  runtimeLibPath,
}:
pkgs.writeShellScriptBin "logseq" ''
  base_ld="${runtimeLibPath}"
  if [ -n "''${LD_LIBRARY_PATH-}" ]; then
    base_ld="$base_ld:''${LD_LIBRARY_PATH}"
  fi
  if [ -d /run/opengl-driver ]; then
    export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver-32/lib:$base_ld"
    export LIBGL_DRIVERS_PATH="''${LIBGL_DRIVERS_PATH:-/run/opengl-driver/lib/dri}"
    export LIBVA_DRIVERS_PATH="''${LIBVA_DRIVERS_PATH:-/run/opengl-driver/lib/dri}"
    if ls /run/opengl-driver/lib/libnvidia-*.so >/dev/null 2>&1; then
      export __NV_PRIME_RENDER_OFFLOAD="''${__NV_PRIME_RENDER_OFFLOAD:-1}"
      export __VK_LAYER_NV_optimus="''${__VK_LAYER_NV_optimus:-NVIDIA_only}"
      export LIBVA_DRIVER_NAME="''${LIBVA_DRIVER_NAME:-nvidia}"
      # Electron relies on EGL/ANGLE; forcing a GLX vendor breaks PRIME on NVIDIA (Invalid visual ID).
      if [ -n "''${LOGSEQ_GLX_VENDOR-}" ]; then
        export __GLX_VENDOR_LIBRARY_NAME="''${__GLX_VENDOR_LIBRARY_NAME:-''${LOGSEQ_GLX_VENDOR}}"
      fi
      if [ -z "''${VK_ICD_FILENAMES-}" ] && [ -f /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json ]; then
        export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
      fi
    fi
  else
    export LD_LIBRARY_PATH="$base_ld"
    export LIBGL_DRIVERS_PATH="''${LIBGL_DRIVERS_PATH:-${pkgs.mesa}/lib/dri}"
    export LIBVA_DRIVERS_PATH="''${LIBVA_DRIVERS_PATH:-${pkgs.mesa}/lib/dri}"
  fi
  exec ${logseqFhs}/bin/logseq-fhs "$@"
''
