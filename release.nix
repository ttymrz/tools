let
  inherit (import ./lib.nix) importPinned;

  # fetch nixpkgs. iohk hydra doesn't provide <nixpkgs>, so we'll have to use
  # a pinned one.
  pkgs = importPinned "nixpkgs" {};

  # cross system settings
  mingwW64 = pkgs.lib.systems.examples.mingwW64;

  leksah-src = pkgs.fetchgit {
      url = "https://github.com/leksah/leksah";
      rev = "a1ba50693c75e0f88a9ea1161e39d2833c08219a";
      sha256 = "0rwk8j3nwbzc26lr9y6n9zxy68b53y6k63g2lrxh753h8bfzlhs9";
      fetchSubmodules = true;
    };

  leksah-mingw32 = import leksah-src { system = "x86_64-linux"; crossSystem = mingwW64; };

  # jobs contain a key -> value mapping that tells hydra which
  # derivations to build.  There are some predefined helpers in
  # https://github.com/NixOS/nixpkgs/tree/master/pkgs/build-support/release
  # which can be accessed via `pkgs.releaseTools`.
  #
  # It is however not necessary to use those.
  #
  jobs = builtins.mapAttrs (_: system:
    let leksah = import leksah-src { inherit system; };
    in builtins.mapAttrs (_: pkgs.recurseIntoAttrs) {
      leksah-plan-nix = leksah.pkgs.haskell-nix.withInputs leksah.plan-nix;
    
      wrapped-leksah = leksah.wrapped-leksah;
      leksah-shells = leksah.shells;
      leksah-haskell-nix-roots = leksah.pkgs.haskell-nix.haskellNixRoots;
    }) {
      linux = "x86_64-linux";
      macos = "x86_64-darwin";
    };
in
  jobs
