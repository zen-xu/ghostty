{ mkShell, lib, stdenv

, gdb
, pkg-config
, scdoc
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
  ];

  buildInputs = [
  ] ++ lib.optionals stdenv.isLinux [
    libX11
  ];

  LD_LIBRARY_PATH="${libGL}/lib";
}
