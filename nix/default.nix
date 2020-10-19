{ sources ? import ./sources.nix
}:
let
  # default nixpkgs
  pkgs = import sources.nixpkgs { };

  # gitignore.nix
  gitignoreSource = (import sources."gitignore.nix" { inherit (pkgs) lib; }).gitignoreSource;

  pre-commit-hooks = (import sources."pre-commit-hooks.nix");

  poetry2nix = (import sources."poetry2nix" { inherit pkgs; poetry = pkgs.poetry; });

  concrexit-src = sources."concrexit";

  src = gitignoreSource ./..;
in
{
  inherit pkgs src;

  # provided by shell.nix
  devTools = {
    inherit (pkgs) niv;
    inherit (pre-commit-hooks) pre-commit;
    nixpkgs-fmt = pre-commit-hooks.nixpkgs-fmt;
  };

  # to be built by github actions
  ci = {
    pre-commit-check = pre-commit-hooks.run {
      inherit src;
      hooks = {
        shellcheck.enable = true;
        nixpkgs-fmt.enable = true;
        nix-linter.enable = true;
      };
      # generated files
      excludes = [ "^nix/sources\.nix$" ];
    };
    concrexit-env = poetry2nix.mkPoetryEnv {
      projectDir = concrexit-src;
      overrides = poetry2nix.overrides.withDefaults (
        _self: super: {
          pillow = super.pillow.overridePythonAttrs (
            old: with pkgs; {
              preConfigure =
                let
                  libinclude' = pkg: ''"${pkg.out}/lib", "${pkg.out}/include"'';
                  libinclude = pkg: ''"${pkg.out}/lib", "${pkg.dev}/include"'';
                in
                ''
                  sed -i "setup.py" \
                      -e 's|^FREETYPE_ROOT =.*$|FREETYPE_ROOT = ${libinclude freetype}|g ;
                          s|^JPEG_ROOT =.*$|JPEG_ROOT = ${libinclude libjpeg}|g ;
                          s|^JPEG2K_ROOT =.*$|JPEG2K_ROOT = ${libinclude openjpeg}|g ;
                          s|^IMAGEQUANT_ROOT =.*$|IMAGEQUANT_ROOT = ${libinclude' libimagequant}|g ;
                          s|^ZLIB_ROOT =.*$|ZLIB_ROOT = ${libinclude zlib}|g ;
                          s|^LCMS_ROOT =.*$|LCMS_ROOT = ${libinclude lcms2}|g ;
                          s|^TIFF_ROOT =.*$|TIFF_ROOT = ${libinclude libtiff}|g ;
                          s|^TCL_ROOT=.*$|TCL_ROOT = ${libinclude' tcl}|g ;
                          s|self\.disable_platform_guessing = None|self.disable_platform_guessing = True|g ;'
                  export LDFLAGS="-L${libwebp}/lib"
                  export CFLAGS="-I${libwebp}/include"
                ''
                # Remove impurities
                + stdenv.lib.optionalString stdenv.isDarwin ''
                  substituteInPlace setup.py \
                    --replace '"/Library/Frameworks",' "" \
                    --replace '"/System/Library/Frameworks"' ""
                '';
              nativeBuildInputs = [ pkgconfig ] ++ old.nativeBuildInputs;
              buildInputs = [ freetype libjpeg openjpeg zlib libtiff libwebp tcl lcms2 ] ++ old.buildInputs;
            }
          );
          uwsgi = { };
        }
      );
    };
  };
}
