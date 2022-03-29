{ mkShell, lib, stdenv

, gdb
, pkg-config
, scdoc
, zig

, glfw
, libX11
, vulkan-headers
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
    glfw
    libX11
    vulkan-headers
  ];
}
