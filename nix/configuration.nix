{ config, pkgs, ... }:
let
  vars = import ./vars.nix;

  concrexit = import ./concrexit.nix { system = config.nixpkgs.localSystem.system; };

in
{
  config = {
    environment.systemPackages = [ concrexit.sudo-concrexit-manage ];
    # Make concrexit user
    users.users.${vars.concrexit-user} = { };

    systemd.services = {
      concrexit = {
        after = [ "networkig.target" "postgresql.service" "concrexit-env.service" ];
        partOf = [ "concrexit-env.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          User = vars.concrexit-user;
          KillSignal = "SIGQUIT";
        };

        script = ''
          if [ -f /run/concrexit.env ]; then
            source /run/concrexit.env
          else
            export ALLOWED_HOSTS="concrexit.pingiun.com"
            export DJANGO_SECRET=$(hostid)
            export DJANGO_PRODUCTION=1
            export POSTGRES_USER=concrexit
            export POSTGRES_DB=concrexit
            export ENABLE_LOGFILE=0
          fi

          export STATIC_ROOT=${concrexit.concrexit-static}
          ${concrexit.concrexit-uwsgi}/bin/concrexit-uwsgi --socket :${toString vars.concrexit-port}
        '';
      };
      self-deploy =
        let
          workingDirectory = "/var/lib/self-deploy";

          owner = "pingiun";

          repository = "concrexit-nix";

          repositoryDirectory = "${workingDirectory}/${repository}";

          build = "${repositoryDirectory}/result";

        in
        {
          wantedBy = [ "multi-user.target" ];

          after = [ "network-online.target" ];

          path = [ pkgs.gnutar pkgs.gzip ];

          serviceConfig.X-RestartIfChanged = false;

          script = ''
            if [ ! -e ${workingDirectory} ]; then
              ${pkgs.coreutils}/bin/mkdir --parents ${workingDirectory}
            fi
            if [ ! -e ${repositoryDirectory} ]; then
              cd ${workingDirectory}
              ${pkgs.git}/bin/git clone https://github.com/${owner}/${repository}.git
            fi
            cd ${repositoryDirectory}
            ${pkgs.git}/bin/git fetch https://github.com/${owner}/${repository}.git master
            ${pkgs.git}/bin/git checkout FETCH_HEAD
            ${pkgs.nix}/bin/nix-build --attr machine ${repositoryDirectory}
            ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --set ${build}
            ${pkgs.git}/bin/git gc --prune=all
            ${build}/bin/switch-to-configuration switch
          '';
        };
    };

    services = {
      nginx = {
        enable = true;

        recommendedGzipSettings = true;

        recommendedOptimisation = true;

        recommendedTlsSettings = true;

        enableReload = true;

        virtualHosts = {
          "${vars.domain}" = {
            # enableACME = true;
            # forceSSL = true;
            locations."/".extraConfig = ''
              uwsgi_pass 127.0.0.1:${toString vars.concrexit-port};
            '';
            locations."/static/".alias = "${concrexit.concrexit-static}/";
          };
        };
      };
      postgresql = {
        enable = true;
        ensureDatabases = [ vars.concrexit-user ];
        ensureUsers = [
          {
            name = vars.concrexit-user;
            ensurePermissions = {
              "DATABASE ${vars.concrexit-user}" = "ALL PRIVILEGES";
            };
          }
        ];
      };
    };

    networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  };
}
