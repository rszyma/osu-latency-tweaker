{
  stdenv,
  glibc,
}:

stdenv.mkDerivation {
  pname = "basscallwrap";
  version = "0";

  src = ../../../src;

  buildInputs = [ glibc.dev ];

  buildPhase = ''
    $CC -shared -fPIC basscallwrap.c -o basscallwrap.so -ldl
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp basscallwrap.so $out/lib/
  '';
}
