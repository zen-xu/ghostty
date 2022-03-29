{ mkShell, lib, stdenv

, pkg-config
, scdoc
, zig

, libX11
}: mkShell rec {
  name = "ghostty";

  nativeBuildInputs = [
    pkg-config
    scdoc
    zig
  ];

  buildInputs = [
  ] ++ lib.optionals stdenv.isLinux [
    libX11
  ];
}
