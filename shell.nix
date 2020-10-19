{ project ? import ./nix { system = builtins.currentSystem; }
}:

project.pkgs.mkShell {
  buildInputs = builtins.attrValues project.devTools;
  shellHook = ''
    ${project.ci.pre-commit-check.shellHook}
  '';
}
