{ mkShell, lib, stdenv

, gdb
, pkg-config
, scdoc
, vulkan-loader
, vttest
, zig

, libGL
, libX11
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
    libX11
  ];

  LD_LIBRARY_PATH = "${vulkan-loader}/lib:${libGL}/lib";
}
