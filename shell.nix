let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs { overlays = [ (import sources.rust-overlay) ]; };
  rustPlatform = import ./nix/rust.nix { inherit sources; };
  mach-nix = import sources.mach-nix {
    pkgs = pkgs;
    python = "python39";
    pypiDataRev = "3b6187edccd2d800ab3eeadc3abb726ed952c24d";
    pypiDataSha256 = "020jnjj8vh8z9n5iy7swx1ai2pjz18xxq96i3m9lzvq3dq9f12hn";
  };

  customPython = mach-nix.mkPython {
    requirements = ''
      sourmash
      screed
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
