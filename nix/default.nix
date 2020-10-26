{ sources ? import ./sources.nix
, system
}:
let
  # default nixpkgs
  pkgs = import sources.nixpkgs { localSystem.system = system; };

  # gitignore.nix
  gitignoreSource = (import sources."gitignore.nix" { inherit (pkgs) lib; }).gitignoreSource;

  pre-commit-hooks = (import sources."pre-commit-hooks.nix");

  src = gitignoreSource ./..;

  concrexit = import ./concrexit.nix { inherit sources system; };

  vm = (import "${sources.nixpkgs}/nixos" {
    configuration = {
      imports = [ ./configuration.nix "${sources.nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];

      networking.hostName = "concrexit";

      users = {
        mutableUsers = false;

        users.root.password = "";
      };

      virtualisation = {
        cores = 2;

        memorySize = "4096";
      };
    };
    system = "x86_64-linux";
  }).vm;

  machine = (import "${sources.nixpkgs}/nixos" {
    configuration = {
      imports = [ ./configuration.nix ./hardware.nix "${sources.nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];

      networking.hostName = "concrexit";
    };
    system = "x86_64-linux";
  }).system;
in
{
  inherit pkgs src;

  # provided by shell.nix
  devTools = {
    inherit (pkgs) niv;
    inherit (pre-commit-hooks) pre-commit;
    inherit (pre-commit-hooks) nixpkgs-fmt;
    inherit (pkgs) uwsgi;
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
    inherit (concrexit) concrexit-env sudo-concrexit-manage concrexit-uwsgi concrexit-static;
    inherit vm machine;
  };
}
