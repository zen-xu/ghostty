{ mkShell, lib, stdenv

, gdb
, glxinfo
, pkg-config
, scdoc
, vulkan-loader
, vttest
, zig

, bzip2
, fontconfig
, freetype
, libepoxy
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
    gdb
    pkg-config
    scdoc
    zig

    glxinfo
    vttest
  ];

  buildInputs = [
    # TODO: non-linux
  ] ++ lib.optionals stdenv.isLinux [
    libepoxy
    libGL

    fontconfig
    freetype
    libpng
    bzip2

    libX11
    libXcursor
    libXext
    libXi
    libXinerama
    libXrandr
  ];

  LD_LIBRARY_PATH = "${vulkan-loader}/lib:${libGL}/lib";
}
