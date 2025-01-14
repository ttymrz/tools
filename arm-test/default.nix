let
  sources = import ./nix/sources.nix {};
  # Fetch the latest haskell.nix and import its default.nix
  haskellNix = import sources."haskell.nix" {};
  # haskell.nix provides access to the nixpkgs pins which are used by our CI, hence
  # you will be more likely to get cache hits when using these.
  # But you can also just use your own, e.g. '<nixpkgs>'
  nixpkgsSrc = sources.nixpkgs-2111-patched; #haskellNix.sources.nixpkgs-2111;
  #nixpkgsSrc = sources.nixpkgs-m1; #haskellNix.sources.nixpkgs-2009; #sources.nixpkgs; #
  # haskell.nix provides some arguments to be passed to nixpkgs, including some patches
  # and also the haskell.nix functionality itself as an overlay.
  nixpkgsArgs = haskellNix.nixpkgsArgs;
in
{ system ? __currentSystem
, nativePkgs ? import nixpkgsSrc (nixpkgsArgs // { overlays =
    # [ (import ./rust.nix)] ++
    nixpkgsArgs.overlays ++
    [
      (final: prev: { libsodium-vrf = final.callPackage ./libsodium.nix {}; })
      (final: prev: { llvmPackages_13 = prev.llvmPackages_13 // {
          compiler-rt-libc = prev.llvmPackages_13.compiler-rt-libc.overrideAttrs (old: {
            cmakeFlags = with old.stdenv.hostPlatform; old.cmakeFlags ++ [ "-DCOMPILER_RT_BUILD_MEMPROF=OFF" ];
          });}; })
    ]
    ;
    inherit system;
    })
, haskellCompiler ? "ghc8107"
, cardano-node-info ? sources.cardano-node
, cardano-node-src ? cardano-node-info
, cardano-wallet-src ? sources.cardano-wallet
# , cardano-rt-view-json
# , cardano-rt-view-info ? __fromJSON (__readFile cardano-rt-view-json)
# , cardano-rt-view-src ? nativePkgs.fetchgit (removeAttrs cardano-rt-view-info [ "date" ])
# , wstunnel-json
# , wstunnel-info ? __fromJSON (__readFile wstunnel-json)
# , wstunnel-src ? nativePkgs.fetchgit (removeAttrs wstunnel-info [ "date" ])
# , ghcup-src ? ./ghcup-hs
}:
let toBuild = with nativePkgs.pkgsCross; {
  # x86-gnu32 = gnu32;
  native = nativePkgs; #gnu64; # should be == nativePkgs
  # x86-musl32 = musl32;
  x86-musl64 = musl64;
  x86-win64 = mingwW64;
  rpi1-gnu = raspberryPi;
  rpi1-musl = muslpi;
  rpi32-gnu = armv7l-hf-multiplatform;
  # sadly this one is missing from the nixpkgs system examples
  rpi32-musl = import nixpkgsSrc (nativePkgs.lib.recursiveUpdate nixpkgsArgs
    { crossSystem = nativePkgs.lib.systems.examples.armv7l-hf-multiplatform
                  // { config = "armv7l-unknown-linux-musleabihf"; }; });
  rpi64-gnu = aarch64-multiplatform;
  rpi64-musl = aarch64-multiplatform-musl;

  inherit ghcjs aarch64-android;
}; in
# 'cabalProject' generates a package set based on a cabal.project (and the corresponding .cabal files)
nativePkgs.lib.mapAttrs (_: pkgs: rec {
  # nativePkgs.lib.recurseIntoAttrs, just a bit more explicilty.
  recurseForDerivations = true;

  hello = (pkgs.haskell-nix.hackage-package {
      name = "hello";
      version = "1.0.0.2";
      ghc = pkgs.buildPackages.pkgs.haskell-nix.compiler.${haskellCompiler};
    }).components.exes.hello;

  cabal-install = (pkgs.haskell-nix.hackage-package {
      name = "cabal-install";
      # can't build 3.0 or 3.2, we seem to pass in the lib Cabal from our GHC :-/
      version = "3.2.0.0";
      ghc = pkgs.buildPackages.pkgs.haskell-nix.compiler.${haskellCompiler};

      modules = [
        # haddock can't find haddock m(
        { doHaddock = false; }
        # lukko breaks hsc2hs
        { packages.lukko.patches = [ ./cabal-install-patches/19.patch ]; }
        # Remove Cabal from nonReinstallablePkgs to be able to pick Cabal-3.2.
        { nonReinstallablePkgs = [
          "rts" "ghc-heap" "ghc-prim" "integer-gmp" "integer-simple" "base"
          "deepseq" "array" "ghc-boot-th" "pretty" "template-haskell"
          # ghcjs custom packages
          "ghcjs-prim" "ghcjs-th"
          "ghc-boot"
          "ghc" "Win32" "array" "binary" "bytestring" "containers"
          "directory" "filepath" "ghc-boot" "ghc-compact" "ghc-prim"
          # "ghci" "haskeline"
          "hpc"
          "mtl" "parsec" "process" "text" "time" "transformers"
          "unix" "xhtml"
          # "stm" "terminfo"
        ]; }
      ];
    }).components.exes.cabal;

  cardano-node = nativePkgs.lib.mapAttrs (_: cardano-node-info:
    let cardano-node-src = cardano-node-info; in rec {
    __cardano-node = (pkgs.haskell-nix.cabalProject {
        cabalProjectLocal  =  pkgs.lib.optionalString (pkgs.stdenv.targetPlatform != pkgs.stdenv.buildPlatform) ''
    -- When cross compiling we don't have a `ghc` package
    package plutus-tx-plugin
      flags: +use-ghc-stub
    '';
        compiler-nix-name = haskellCompiler;
        # pkgs.haskell-nix.haskellLib.cleanGit { name = "cardano-node"; src = ... } <- this doesn't work with fetchgit results
        src = cardano-node-src;
        # ghc = pkgs.buildPackages.pkgs.haskell-nix.compiler.${haskellCompiler};
        modules = [
          # Allow reinstallation of Win32
          { nonReinstallablePkgs =
            [ "rts" "ghc-heap" "ghc-prim" "integer-gmp" "integer-simple" "base"
              "deepseq" "array" "ghc-boot-th" "pretty" "template-haskell"
              # ghcjs custom packages
              "ghcjs-prim" "ghcjs-th"
              "ghc-boot"
              "ghc" "array" "binary" "bytestring" "containers"
              "filepath" "ghc-boot" "ghc-compact" "ghc-prim"
              # "ghci" "haskeline"
              "hpc"
              "mtl" "parsec" "text" "transformers"
              "xhtml"
              # "stm" "terminfo"
            ];
          }
          # haddocks are useless (lol);
          # and broken for cross compilers!
          { doHaddock = false; }
          { compiler.nix-name = haskellCompiler; }
          { packages.cardano-config.flags.systemd = false;
            packages.cardano-node.flags.systemd = false; }
          { packages.terminal-size.patches = [ ./cardano-node-patches/terminal-size-0.3.2.1.patch ];
            packages.unix-bytestring.patches = [ ./cardano-node-patches/unix-bytestring-0.3.7.3.patch ];
            packages.plutus-core.patches = [ ./cardano-node-patches/plutus-core.patch ];

            # We need the following patch to work around this grat failure :(
            # src/Cardano/Config/Git/Rev.hs:33:35: error:
            #     • Exception when trying to run compile-time code:
            #         git: readCreateProcessWithExitCode: posix_spawn_file_actions_adddup2(child_end): invalid argument (Invalid argument)
            #       Code: gitRevFromGit
            #     • In the untyped splice: $(gitRevFromGit)
            #    |
            # 33 |         fromGit = T.strip (T.pack $(gitRevFromGit))
            #    |
            packages.cardano-config.patches = [ ./cardano-node-patches/cardano-config-no-git-rev.patch ];
            # packages.typerep-map.patches = [ ./cardano-node-patches/typerep-map-PR82.patch ];
            # packages.streaming-bytestring.patches = [ ./cardano-node-patches/streaming-bytestring-0.1.6.patch ];
            # packages.byron-spec-ledger.patches = [ ./cardano-node-patches/byron-ledger-spec-no-goblins.patch ];
            packages.byron-spec-ledger.flags.goblins = false;
            # this one will disable gitRev; which fails (due to a linker bug) for armv7
            # packages.cardano-config.patches = [ ./cardano-node-patches/1036.patch ];

            # Disable cabal-doctest tests by turning off custom setups
            packages.comonad.package.buildType = nativePkgs.lib.mkForce "Simple";
            packages.distributive.package.buildType = nativePkgs.lib.mkForce "Simple";
            packages.lens.package.buildType = nativePkgs.lib.mkForce "Simple";
            packages.nonempty-vector.package.buildType = nativePkgs.lib.mkForce "Simple";
            packages.semigroupoids.package.buildType = nativePkgs.lib.mkForce "Simple";

            # Remove hsc2hs build-tool dependencies (suitable version will be available as part of the ghc derivation)
            packages.Win32.components.library.build-tools = nativePkgs.lib.mkForce [];
            packages.terminal-size.components.library.build-tools = nativePkgs.lib.mkForce [];
            packages.network.components.library.build-tools = nativePkgs.lib.mkForce [];
          }
          ({ pkgs, lib, ... }: lib.mkIf (pkgs.stdenv.hostPlatform.isAndroid) {
            packages.iohk-monitoring.patches = [ ./cardano-node-patches/iohk-monitoring-framework-625.diff ];
            # android default inlining threshold seems to be too high for closure_sizeW to be inlined properly.
            packages.cardano-prelude.ghcOptions = [ "-optc=-mllvm" "-optc-inlinehint-threshold=500" ];
            packages.cardano-node.ghcOptions = [ "-pie" ];
          })
          ({ pkgs, lib, ... }: lib.mkIf (!pkgs.stdenv.hostPlatform.isGhcjs) {
            packages = {
              # See https://github.com/input-output-hk/iohk-nix/pull/488
              cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ pkgs.libsodium-vrf ] ];
              cardano-crypto-class.components.library.pkgconfig = lib.mkForce [ [ pkgs.libsodium-vrf ] ];
            };
          })
          ({ pkgs, lib, ... }: lib.mkIf (pkgs.stdenv.hostPlatform.isGhcjs) {
            packages =
              let libsodium-vrf = pkgs.libsodium-vrf.overrideAttrs (attrs: {
                    nativeBuildInputs = attrs.nativeBuildInputs or [ ] ++ (with pkgs.buildPackages.buildPackages; [ emscripten python2 ]);
                    prePatch = ''
                      export HOME=$(mktemp -d)
                      export PYTHON=${pkgs.buildPackages.buildPackages.python2}/bin/python
                    '' + attrs.prePatch or "";
                    configurePhase = ''
                      emconfigure ./configure --prefix=$out --enable-minimal --disable-shared --without-pthreads --disable-ssp --disable-asm --disable-pie CFLAGS=-Os
                    '';
                    CC = "emcc";
                  });
                  emzlib = pkgs.zlib.overrideAttrs (attrs: {
                    # makeFlags in nixpks zlib derivation depends on stdenv.cc.targetPrefix, which we don't have :(
                    prePatch = ''
                      export HOME=$(mktemp -d)
                      export PYTHON=${pkgs.buildPackages.buildPackages.python2}/bin/python
                    '' + attrs.prePatch or "";
                    makeFlags = "PREFIX=js-unknown-ghcjs-";
                    # We need the same patching as macOS
                    postPatch = ''
                      substituteInPlace configure \
                        --replace '/usr/bin/libtool' 'emar' \
                        --replace 'AR="libtool"' 'AR="emar"' \
                        --replace 'ARFLAGS="-o"' 'ARFLAGS="-r"'
                    '';
                    configurePhase = ''
                      emconfigure ./configure --prefix=$out --static
                    '';

                    nativeBuildInputs = (attrs.nativeBuildInputs or [ ]) ++ (with pkgs.buildPackages.buildPackages; [ emscripten python2 ]);

                    CC = "emcc";
                    AR = "emar";

                    # prevent it from passing `-lc`, which emcc doesn't like.
                    LDSHAREDLIBC = "";
                  });
              in {
                cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ libsodium-vrf ] ];
                cardano-crypto-class.components.library.pkgconfig = lib.mkForce [ [ libsodium-vrf ] ];
                digest.components.library.libs = lib.mkForce [ emzlib.static emzlib ];
              };
          })
          # {
          #   packages.cardano-node-capi.components.library = {
          #   };
          # }
        ];
      });
      __cardano-wallet = (pkgs.haskell-nix.cabalProject {
        cabalProjectLocal  =  pkgs.lib.optionalString (pkgs.stdenv.targetPlatform != pkgs.stdenv.buildPlatform) ''
    -- When cross compiling we don't have a `ghc` package
    package plutus-tx-plugin
      flags: +use-ghc-stub
    '';
        compiler-nix-name = haskellCompiler;
        src = cardano-wallet-src;
        modules = [
          # Allow reinstallation of Win32
          { nonReinstallablePkgs =
            [ "rts" "ghc-heap" "ghc-prim" "integer-gmp" "integer-simple" "base"
              "deepseq" "array" "ghc-boot-th" "pretty" "template-haskell"
              # ghcjs custom packages
              "ghcjs-prim" "ghcjs-th"
              "ghc-boot"
              "ghc" "array" "binary" "bytestring" "containers"
              "filepath" "ghc-boot" "ghc-compact" "ghc-prim"
              # "ghci" "haskeline"
              "hpc"
              "mtl" "parsec" "text" "transformers"
              "xhtml"
              # "stm" "terminfo"
            ];
          }
          { doHaddock = false; }
          { compiler.nix-name = haskellCompiler; }
          { packages.cardano-config.flags.systemd = false;
            packages.cardano-node.flags.systemd = false; }
          { packages.terminal-size.patches = [ ./cardano-node-patches/terminal-size-0.3.2.1.patch ];
            packages.unix-bytestring.patches = [ ./cardano-node-patches/unix-bytestring-0.3.7.3.patch ];
            packages.plutus-core.patches = [ ./cardano-node-patches/plutus-core.patch ];
            packages.scrypt.patches = [ ./cardano-wallet-patches/scrypt-0.5.0.patch ];
          }
          {
            # Disable cabal-doctest tests by turning off custom setups
            packages.comonad.package.buildType = nativePkgs.lib.mkForce "Simple";
            packages.distributive.package.buildType = nativePkgs.lib.mkForce "Simple";
            packages.lens.package.buildType = nativePkgs.lib.mkForce "Simple";
            packages.nonempty-vector.package.buildType = nativePkgs.lib.mkForce "Simple";
            packages.semigroupoids.package.buildType = nativePkgs.lib.mkForce "Simple";

            # Remove hsc2hs build-tool dependencies (suitable version will be available as part of the ghc derivation)
            packages.Win32.components.library.build-tools = nativePkgs.lib.mkForce [];
            packages.terminal-size.components.library.build-tools = nativePkgs.lib.mkForce [];
            packages.network.components.library.build-tools = nativePkgs.lib.mkForce [];
          }
        ];
      });

      inherit (__cardano-wallet.cardano-wallet.components.exes) cardano-wallet;
      inherit (__cardano-node.cardano-node.components.exes) cardano-node;
      inherit (__cardano-node.cardano-cli.components.exes)  cardano-cli;
      cardano-node-capi = __cardano-node.cardano-node-capi.components.library.override {
              smallAddressSpace = true; enableShared = false;
              ghcOptions = [ "-staticlib" ];
              postInstall = ''
                ${nativePkgs.tree}/bin/tree $out
                mkdir -p $out/_pkg
                # copy over includes, we might want those, but maybe not.
                # cp -r $out/lib/*/*/include $out/_pkg/
                # find the libHS...ghc-X.Y.Z.a static library; this is the
                # rolled up one with all dependencies included.
                find ./dist -name "libHS*-ghc*.a" -exec cp {} $out/_pkg \;

                find ${pkgs.libffi.overrideAttrs (old: { dontDisableStatic = true; })}/lib -name "*.a" -exec cp {} $out/_pkg \;
                find ${pkgs.gmp6.override { withStatic = true; }}/lib -name "*.a" -exec cp {} $out/_pkg \;
                find ${pkgs.libiconv}/lib -name "*.a" -exec cp {} $out/_pkg \;
                find ${pkgs.libffi}/lib -name "*.a" -exec cp {} $out/_pkg \;

                ${nativePkgs.tree}/bin/tree $out/_pkg
                (cd $out/_pkg; ${nativePkgs.zip}/bin/zip -r -9 $out/pkg.zip *)
                rm -fR $out/_pkg

                mkdir -p $out/nix-support
                echo "file binary-dist \"$(echo $out/*.zip)\"" \
                    > $out/nix-support/hydra-build-products
              '';
      };

      tarball = nativePkgs.stdenv.mkDerivation {
        name = "${pkgs.stdenv.targetPlatform.config}-tarball";
        buildInputs = with nativePkgs; [ patchelf zip ];

        phases = [ "buildPhase" "installPhase" ];

        buildPhase = ''
          mkdir -p cardano-node
          cp ${cardano-cli}/bin/*cardano-cli* cardano-node/
          cp ${cardano-node.override { enableTSanRTS = false; }}/bin/*cardano-node* cardano-node/
        '' + pkgs.lib.optionalString (pkgs.stdenv.targetPlatform.isLinux && pkgs.stdenv.targetPlatform.isGnu) ''
          for bin in cardano-node/*; do
            mode=$(stat -c%a $bin)
            chmod +w $bin
            patchelf --set-interpreter /lib/ld-linux-armhf.so.3 $bin
            chmod $mode $bin
          done
        '' + pkgs.lib.optionalString (pkgs.stdenv.targetPlatform.isWindows) ''
          cp ${pkgs.libffi}/bin/*.dll cardano-node/
        '' + pkgs.lib.optionalString (pkgs.stdenv.targetPlatform.isLinux && pkgs.stdenv.targetPlatform.isGnu) ''
          cp ${pkgs.libffi}/lib/*.so* cardano-node/
          cp ${pkgs.gmp}/lib/*.so* cardano-node/
          cp ${pkgs.ncurses}/lib/*.so* cardano-node/
          cp ${pkgs.zlib}/lib/*.so* cardano-node/
          echo ${pkgs.stdenv.cc}/lib
          ls cardano-node/
        '';
        installPhase = ''
          mkdir -p $out/
          zip -r -9 $out/${pkgs.stdenv.hostPlatform.config}-cardano-node-${cardano-node-info.rev or "unknown"}.zip cardano-node

          mkdir -p $out/nix-support
          echo "file binary-dist \"$(echo $out/*.zip)\"" \
            > $out/nix-support/hydra-build-products
        '';
      };
    }) { "mainnet" = sources.cardano-node-mainnet; };

}) toBuild
