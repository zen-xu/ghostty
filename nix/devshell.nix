{ mkShell, lib, stdenv

, gdb
, pkg-config
, scdoc
, vulkan-loader
, vttest
, zig

, libepoxy
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

    vttest
  ];

  buildInputs = [
    # TODO: non-linux
  ] ++ lib.optionals stdenv.isLinux [
    libepoxy
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
