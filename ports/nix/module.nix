{ config, lib, pkgs, ... }:

let
  cfg = config.services.webzfs;
  webzfsDir = "${cfg.package}/opt/webzfs";
in
{
  options.services.webzfs = {
    enable = lib.mkEnableOption "WebZFS - Web-based ZFS management interface";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.webzfs";
      description = ''
        The WebZFS package to use.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 26619;
      description = "Port to listen on.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address to bind to.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        SECRET_KEY = "your-secret-key-here";
        AUTH_SESSION_EXPIRES_SECONDS = "3600";
      };
      description = "Additional environment variables for WebZFS.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the WebZFS port.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "webzfs";
      description = "User account to run WebZFS as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "webzfs";
      description = "Group for the WebZFS user.";
    };
  };

  config = lib.mkIf cfg.enable {

    # Enable ZFS filesystem support
    boot.supportedFilesystems = [ "zfs" ];
    # Enable Sanoid
    services.sanoid.enable = true;

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "WebZFS service user";
      extraGroups = [
        # Add to shadow group for PAM authentication
        "shadow"
      ];
    };

    users.groups.${cfg.group} = { };


    systemd.services.webzfs = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "zfs-mount.service" ];

       path = with pkgs; [ 
          "/run/wrappers" # Necessary for webzfs to run commands as sudo
          "${config.system.path}" # Put system packages in service environment
          lsof
          smartmontools
          #sanoid # Not necessary due to the package itself adding it to the store for the hardcoded path
        ];

      environment = {
        HOME = "/var/lib/webzfs";
        PYTHONPATH = webzfsDir;
        HOST = cfg.host;
        PORT = toString cfg.port;
        BIND_IP = cfg.host;
        CAPTION = "webzfs ${cfg.package.version or "git"}";
        SETTINGS_MODULE = "config.settings.base";
        SECRET_KEY = cfg.settings.SECRET_KEY or "changeme-in-production";
        WEBZFS_STATE_DIR = "/var/lib/webzfs";
      } // cfg.settings;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "webzfs";
        StateDirectoryMode = "0750";
        WorkingDirectory = webzfsDir;
        Restart = "always";
        RestartSec = "5";
      };

      script = ''
        exec ${cfg.package}/bin/webzfs
      '';
    };

    # NOPASSWD config as per sudoers file config in install_linux.sh
    security.sudo = {
      enable = true;
      extraRules = [
        {
          users = [ cfg.user ];
          commands = map (cmd: { command = cmd; options = [ "NOPASSWD" ]; }) [
            # ZFS commands
            "${config.system.path}/bin/zpool"
            "${config.system.path}/bin/zfs"
            "${config.system.path}/bin/zdb -l *"
            # SMART monitoring
            "${pkgs.smartmontools}/bin/smartctl"
            # Disk utilities
            "${config.system.path}/bin/lsblk"
            "${config.system.path}/bin/blkid"
            # Open file / lock inspection (pool export busy investigation)
            "${pkgs.lsof}/bin/lsof"
            "${config.system.path}/bin/lslocks"
            # Sanoid/Syncoid
            "${pkgs.sanoid}/bin/sanoid"
            "${pkgs.sanoid}/bin/syncoid"
            # Service management (systemctl for system services page)
            "${config.system.path}/bin/systemctl"
            # Crontab editing
            #"${config.system.path}/bin/crontab"
            # Scheduled syncoid job timers.
            # Unit files are created and edited with "sudo tee" (covered by the
            # general tee entry below) and enabled/disabled/reloaded with
            # "sudo systemctl" (covered by the systemctl entry above). The explicit
            # tee entries here document that intent and keep timer management
            # working even if the general tee entry is ever narrowed. rm is
            # restricted to WebZFS-owned unit files only.
            "${config.system.path}/bin/tee /etc/systemd/system/webzfs-syncoid-job-*"
            "${config.system.path}/bin/rm -f /etc/systemd/system/webzfs-syncoid-job-*"
            # Unified Scheduling Hub timers. All scheduled task types (scrub, SMART
            # self-test, health check, and replication) use the webzfs-task-* unit
            # naming scheme managed by services/job_scheduler.py.
            "${config.system.path}/bin/tee /etc/systemd/system/webzfs-task-*"
            "${config.system.path}/bin/rm -f /etc/systemd/system/webzfs-task-*"
            # File editing (for config files like smartd.conf, sanoid.conf)
            "${config.system.path}/bin/cat"
            "${config.system.path}/bin/tee"
            "${config.system.path}/bin/mkdir"
            # Read system journal and plain-text syslog files for the
            # Observability -> System Log page. journalctl needs sudo (or
            # systemd-journal group) on most distros. tail covers Debian/Ubuntu
            # (/var/log/syslog) and old RHEL (/var/log/messages).
            "${config.system.path}/bin/journalctl"
            "${config.system.path}/bin/tail"
            # Support bundle log collection. Reading /var/log/messages and
            # /var/log/syslog (typically mode 640 root:adm) and the kernel ring
            # buffer requires elevated privileges for the unprivileged webzfs user.
            "${config.system.path}/bin/grep"
            "${config.system.path}/bin/dmesg"      
          ];
        }
      ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}