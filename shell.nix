let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs { overlays = [ (import sources.rust-overlay) ]; };
  rustPlatform = import ./nix/rust.nix { inherit sources; };
  mach-nix = import sources.mach-nix {
    pkgs = pkgs;
    python = "python39";
    # Updated: 2021-03-03
    pypiDataRev = "721e7736180d89f7f49d8f25620ae9d58ae1a8b1";
    pypiDataSha256 = "0r76z0ckqk56779z9f57p5330sgml1s4m4hyvr76iqlx8kjpqs9j";
  };

  customPython = mach-nix.mkPython {
    requirements = ''
      sourmash>=4
    '';
  };
in
  with pkgs;

  mkShell {
    buildInputs = [
      rustPlatform.rust.cargo
      stdenv.cc.cc.lib
      customPython
      wget
      pandoc
      snakemake
    ];

    shellHook = ''
       # workaround for https://github.com/NixOS/nixpkgs/blob/48dfc9fa97d762bce28cc8372a2dd3805d14c633/doc/languages-frameworks/python.section.md#python-setuppy-bdist_wheel-cannot-create-whl
       export SOURCE_DATE_EPOCH=315532800 # 1980
       export LD_LIBRARY_PATH="${stdenv.cc.cc.lib}/lib64:$LD_LIBRARY_PATH";
    '';
  }
