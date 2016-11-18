{ nixpkgs ? import <nixpkgs> {}, compiler ? "ghc801" }:
let nixpkgs_source = nixpkgs.fetchFromGitHub {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "8ef3eaeb4e531929ec29a880cb4c67f790e5eb70";
      sha256 = "1v9lgk3j394i91qz1h7cv6mbg6xkdllfccc902ydb1gvp6bzmh6z";
    };
    nixpkgs' = (import nixpkgs_source){};
in with nixpkgs'.pkgs;
let hp = haskell.packages.${compiler}.override{
    overrides = self: super: {
      };};
   ghc = hp.ghcWithPackages (ps: with ps; [pandoc lhs2tex]);
   tex = texlive.combine {
                       inherit (texlive)
                         # collection-fontutils
                         # tex-gyre tex-gyre-math
                         cmll
                         lm
                         todonotes
                         stmaryrd lazylist polytable # for lhs2tex
                         xargs
                         biblatex
                         logreq
                         scheme-small wrapfig marvosym wasysym wasy cm-super unicode-math filehook lm-math capt-of
                         xstring ucharcat;
                     };
in
pkgs.stdenv.mkDerivation {
  name = "my-haskell-env-0";
  buildInputs = [ ghc tex ];
  shellHook = "eval $(egrep ^export ${ghc}/bin/ghc)";
}
