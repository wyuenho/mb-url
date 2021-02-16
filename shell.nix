with import <nixpkgs> {};
stdenv.mkDerivation {
  name = "mb-url";
  buildInputs = [
    curl
    httpie
  ];
}
