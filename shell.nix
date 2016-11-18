{ nixpkgs ? import <nixpkgs> {}, compiler ? "ghc801" }:
with (import <nixpkgs> {}).pkgs;
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
