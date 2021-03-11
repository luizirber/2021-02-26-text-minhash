let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs { overlays = [ (import sources.rust-overlay) ]; };
  rustPlatform = import ./nix/rust.nix { inherit sources; };
  mach-nix = import sources.mach-nix {
    pkgs = pkgs;
    python = "python38";
    # Updated: 2021-03-10
    pypiDataRev = "a3b23cd3a838de119208cd8267474a6fffc3eeec";
    pypiDataSha256 = "0v66j1ndz41pnkcr4in05yby7f0q3k9k0v6jrx0v42pq6bp0g74q";
  };

  customPython = mach-nix.mkPython {
    requirements = ''
      sourmash>=4
      matplotlib-venn
      ficus
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
