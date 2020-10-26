{ sources ? import ./sources.nix
, system
}:
let
  # default nixpkgs
  pkgs = import sources.nixpkgs { localSystem.system = system; };

  poetry2nix = (import sources."poetry2nix" { inherit pkgs; poetry = pkgs.poetry; });

  concrexit-src = pkgs.stdenv.mkDerivation {
    name = "concrexit-src";
    src = sources."concrexit";

    phases = [ "unpackPhase" "patchPhase" "installPhase" ];
    patches = [ ../misc.patch ];
    installPhase = ''
      mkdir -p $out
      mv * $out
    '';
  };

  concrexit-env = poetry2nix.mkPoetryEnv {
    projectDir = concrexit-src;
    overrides = poetry2nix.overrides.withDefaults (
      self: super: {
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
            propagatedBuildInputs = [ self.olefile self.magic ];
            buildInputs = [ freetype libjpeg openjpeg zlib libtiff libwebp tcl lcms2 ] ++ old.buildInputs;
          }
        );
        uwsgi = { };
        python-magic = super.magic;
      }
    );
  };

  manage-py = "${concrexit-src}/website/manage.py";
  concrexit-manage = pkgs.writeScriptBin "concrexit-manage" ''
    set -e
    test -f /run/concrexit.env && source /run/concrexit.env
    ${concrexit-env}/bin/python ${manage-py} $@
  '';
  sudo-concrexit-manage = pkgs.writeScriptBin "concrexit-manage" ''
    sudo -u concrexit ${concrexit-manage}/bin/concrexit-manage $@
  '';

  uwsgi = pkgs.uwsgi.override { plugins = [ "python3" ]; python3 = concrexit-env; };

  concrexit-static = pkgs.runCommand "concrexit-static" { } ''
    export STATIC_ROOT=$out
    export DJANGO_PRODUCTION=1
    export DJANGO_SECRET=a

    ${concrexit-env}/bin/python ${manage-py} collectstatic
    ${concrexit-env}/bin/python ${manage-py} compress
  '';

  concrexit-uwsgi = pkgs.writeScriptBin "concrexit-uwsgi" ''
    ${concrexit-env}/bin/python ${manage-py} migrate

    ${uwsgi}/bin/uwsgi $@ \
      --plugins python3 \
      --socket-timeout 1800 \
      --threads 5 \
      --processes 5 \
      --pythonpath ${concrexit-env}/lib/python3.7/site-packages/ \
      --chdir ${concrexit-src}/website \
      --module thaliawebsite.wsgi:application \
      --log-master \
      --harakiri 1800 \
      --max-requests 5000 \
      --vacuum \
      --limit-post 0 \
      --post-buffering 16384 \
      --thunder-lock \
      --ignore-sigpipe \
      --ignore-write-errors \
      --disable-write-exception
  '';

in
{
  inherit concrexit-env sudo-concrexit-manage concrexit-static concrexit-uwsgi;
}
