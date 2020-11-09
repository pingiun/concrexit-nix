{ project ? import ./nix { system = builtins.currentSystem; }
}:

project.pkgs.mkShell {
  buildInputs = builtins.attrValues project.devTools ++ project.ec2tools;
  shellHook = ''
    ${project.ci.pre-commit-check.shellHook}
  '';
}
