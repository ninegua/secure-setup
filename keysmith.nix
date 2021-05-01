{ pkgs ? import <nixpkgs> { } }:
with pkgs;
buildGoModule rec {
  pname = "keysmith";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "dfinity";
    repo = "keysmith";
    rev = "v1.4.0";
    sha256 = "1l5y3xr5jvbah2szxxsmzx6mqkbd96r84v3g5bg1shlr5a1z8654";
  };

  subPackages = [ "." ];

  vendorSha256 = "1p0r15ihmnmrybf12cycbav80sdj2dv2kry66f4hjfjn6k8zb0dc";

  runVend = false;
  meta = with lib; {
    description =
      "Hierarchical Deterministic Key Derivation for the Internet Computer";
    homepage = "https://github.com/dfinity/keysmith";
    license = licenses.mit;
  };
  buildFlags = [ "-ldflags='-extldflags=-static'" ];
  CGO_ENABLED = "0";
}
