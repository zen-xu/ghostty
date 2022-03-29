{ mkShell

, pkg-config
, scdoc
, zig
}: mkShell rec {
  name = "ghostty";

  nativeBuildInputs = [
    pkg-config
    scdoc
    zig
  ];

  buildInputs = [
  ];
}
