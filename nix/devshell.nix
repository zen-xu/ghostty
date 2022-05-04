{ mkShell, lib, stdenv

, gdb
, glxinfo
, pkg-config
, scdoc
, tracy
, vulkan-loader
, vttest
, zig

, bzip2
, fontconfig
, freetype
, libpng
, libGL
, libX11
, libXcursor
, libXext
, libXi
, libXinerama
, libXrandr
}: mkShell rec {
  name = "ghostty";

  nativeBuildInputs = [
    # For builds
    pkg-config
    scdoc
    zig

    # Utilities
    glxinfo
    vttest

    # Testing
    gdb
    tracy
  ];

  buildInputs = [
    # TODO: non-linux
  ] ++ lib.optionals stdenv.isLinux [
    libGL

    libX11
    libXcursor
    libXext
    libXi
    libXinerama
    libXrandr
  ];

  LD_LIBRARY_PATH = "${vulkan-loader}/lib:${libGL}/lib";
}
