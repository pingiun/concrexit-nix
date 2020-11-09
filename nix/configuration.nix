{ config, pkgs, ... }:
let
  vars = import ./vars.nix;

  concrexit = import ./concrexit.nix { system = config.nixpkgs.localSystem.system; };

in
{
  config = {
    environment.systemPackages = [ concrexit.sudo-concrexit-manage ];

    security.acme.email = "jelle@pingiun.com";
    security.acme.acceptTerms = true;

    nix = {
      gc.automatic = true;
      trustedUsers = [ "root" "deploy" ];
    };

    security.sudo.wheelNeedsPassword = false;
    users.mutableUsers = false;
    users.users.jelle = {
      isNormalUser = true;
      description = "Jelle Besseling";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICunYiTe1MOJsGC5OBn69bewMBS5bCCE1WayvM4DZLwE jelle@Jelles-Macbook-Pro.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID+/7ktPyg4lYL0b6j3KQqfVE6rGLs5hNK3Q175th8cq jelle@foon"
      ];
    };
    users.users.deploy = {
      isNormalUser = true;
      description = "Deploy user";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIGc4W1uY5cNNSCZRMYwShRtcNsw3qXvvY7HSFbGNhWw deploykey"
      ];
    };

    services.openssh.enable = true;

    # Make concrexit user
    users.users.${vars.concrexit-user} = { };

    systemd.services = {
      concrexit-dir = {
        wantedBy = [ "multi-user.target" ];
        script = ''
          mkdir --parents /var/lib/concrexit/media
          chown ${vars.concrexit-user} /var/lib/concrexit/media
        '';
      };

      concrexit = {
        after = [ "networkig.target" "postgresql.service" "concrexit-dir.service" "set-route53-dns.service" ];
        partOf = [ "concrexit-env.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          User = vars.concrexit-user;
          KillSignal = "SIGQUIT";
        };

        script = ''
          if [ -f /var/lib/concrexit/concrexit.env ]; then
            source /var/lib/concrexit/concrexit.env
          else
            export DJANGO_SECRET=$(hostid)
            export DJANGO_PRODUCTION=1
            export POSTGRES_USER=concrexit
            export POSTGRES_DB=concrexit
            export ENABLE_LOGFILE=0
            echo "You should set the secrets in the env file" >&2
          fi

          export ALLOWED_HOSTS="${vars.domain}"
          export MEDIA_ROOT=/var/lib/concrexit/media
          export STATIC_ROOT=${concrexit.concrexit-static}
          ${concrexit.concrexit-uwsgi}/bin/concrexit-uwsgi --socket :${toString vars.concrexit-port}
        '';
      };

      "acme-staging-nix.thalia.nu".after = [ "set-route53-dns.service" ];

      set-route53-dns = {
        after = [ "networking.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          PrivateUsers = true;
        };

        script = ''
          set -x
          ZONE_ID="Z20YH0HYTRRRNK"
          TTL=300
          SELF_META_URL="http://169.254.169.254/latest/meta-data"
          PUBLIC_DNS=$(${pkgs.curl}/bin/curl $SELF_META_URL/public-hostname 2>/dev/null)

          cat << EOT > /tmp/aws_r53_batch.json
          {
            "Comment": "Assign AWS Public DNS as a CNAME",
            "Changes": [
              {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                  "Name": "staging-nix",
                  "Type": "CNAME",
                  "TTL": $TTL,
                  "ResourceRecords": [
                    {
                      "Value": "$PUBLIC_DNS"
                    }
                  ]
                }
              }
            ]
          }
          EOT

          ${pkgs.awscli}/bin/aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file:///tmp/aws_r53_batch.json
          rm -f /tmp/aws_r53_batch.json
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
            enableACME = true;
            forceSSL = true;
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

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
