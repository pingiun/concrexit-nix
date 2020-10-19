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
      overrides = poetry2nix.overrides.withDefaults (_self: super: {
        pillow = super.pillow.overridePythonAttrs (
          old: {
            setupPyBuildFlags = "--disable-xcb";
            nativeBuildInputs = [ pkgs.pkgconfig ] ++ old.nativeBuildInputs;
            buildInputs = with pkgs; [ freetype libjpeg openjpeg zlib libtiff libwebp tcl lcms2 ] ++ old.buildInputs;
          }
        );
      });
    };
  };
}
