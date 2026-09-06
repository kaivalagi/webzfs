# Nix packaging for WebZFS

This directory contains the Nix packaging for [WebZFS](https://github.com/webzfs/webzfs), a
web-based ZFS management interface. The packaging lives in-repo and is exposed through the
flake at the repository root, so you can consume this project directly as a flake input.

## What's here

| File              | Purpose                                                             |
| ----------------- | ------------------------------------------------------------------- |
| `package.nix`     | The WebZFS package (`buildNpmPackage` + Python runtime from `requirements.txt`) |
| `module.nix`      | A NixOS module that runs WebZFS as a systemd service                |
| `dev-shell.nix`   | A development shell with Python, Node.js, npm, and gunicorn         |

The flake at the repository root exposes:

- `nixosModules.webzfs`
- `overlays.default`
- `packages.<system>.webzfs` / `packages.<system>.default`
- `devShells.<system>.default`

Supported systems: `x86_64-linux` and `aarch64-linux`.

---

## Using WebZFS as a NixOS module

Add the flake as an input and import the module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    webzfs.url = "github:kaivalagi/webzfs";
  };

  outputs = { self, nixpkgs, webzfs, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        webzfs.nixosModules.webzfs
        {
          services.webzfs = {
            enable = true;
            # openFirewall = true;               # if you want to expose the port
            settings = {
              SECRET_KEY = "change-me-in-production";
              # HOST, PORT, and other env are also accepted here
            };
          };
        }
      ];
    };
  };
}
```

Enable and start the service with:

```bash
sudo systemctl enable --now webzfs
```

The module creates a dedicated `webzfs` user/group and runs the service under
`systemd` with state kept in `/var/lib/webzfs`.

### What the module sets up for you

The module is self-contained: enabling `services.webzfs.enable` is all you
need, there are no further dependencies to configure. Under the hood it wires
up the full host integration required for WebZFS to actually work on NixOS:

- **Privileged command access** — `sudo` NOPASSWD rules for the commands that
  genuinely need root (`zpool`, `zfs`, `zdb -l *`, `smartctl`, `lsof`/
  `lslocks`, `sanoid`/`syncoid`, `systemctl`, `crontab`, `tee`/`rm` for
  WebZFS-owned systemd unit files, file editing via `cat`/`tee`/`mkdir`, and
  `dmesg` for support bundles). `secure_path` is pinned to
  `/run/current-system/sw/bin` so the rules resolve across rebuilds.
- **Group memberships instead of sudo for read-only tools** — the `webzfs`
  user joins `shadow` (PAM login against `/etc/shadow`), `systemd-journal`
  (`journalctl` log readout), and `disk` (`blkid` block device reads); `lsblk`
  needs no privilege at all.
- **PATH** — the service gets a PATH with `/run/wrappers`, `zfs`,
  `smartmontools`, `sanoid`/`syncoid`, `util-linux`, `lsof`, `systemd`,
  `coreutils`, `gnugrep`, and `cronie`, so both direct tool execution and
  sudo's secure_path resolve correctly.

### Module options

| Option            | Type        | Default         | Description                                    |
| ----------------- | ----------- | --------------- | ---------------------------------------------- |
| `enable`          | bool        | `false`         | Whether to enable the WebZFS service.          |
| `package`         | package     | `pkgs.webzfs`   | The WebZFS package to run.                     |
| `port`            | port        | `26619`         | Port to listen on.                             |
| `host`            | string      | `127.0.0.1`     | Host address to bind to.                       |
| `settings`        | attrsOf str | `{}`            | Extra environment variables for WebZFS.        |
| `openFirewall`    | bool        | `false`         | Open the port in the firewall.                 |
| `user`            | string      | `webzfs`        | System user the service runs as.               |
| `group`           | string      | `webzfs`        | Group for the service user.                    |

> **Note:** WebZFS binds to `127.0.0.1` by default. For remote access, prefer SSH port
> forwarding (`ssh -L 127.0.0.1:26619:127.0.0.1:26619 host`) over exposing it directly.

---

## Using the overlay

If you are not using the NixOS module and just want `pkgs.webzfs` available in your package
set:

```nix
{
  inputs.webzfs.url = "github:kaivalagi/webzfs";

  outputs = { nixpkgs, webzfs, ... }: {
    overlays.default = nixpkgs.lib.composeManyExtensions [
      webzfs.overlays.default
      (final: prev: { /* your other overrides */ })
    ];
  };
}
```

You can then refer to `pkgs.webzfs`.

---

## Installing the package directly

To install WebZFS into your user (or system) profile without a module:

```bash
nix profile install github:kaivalagi/webzfs
```

Or add it to your NixOS config:

```nix
environment.systemPackages = [ pkgs.webzfs ];
```

---

## Using the binary cache (Cachix)

To avoid building WebZFS and its dependencies locally, you can pull pre-built binaries from
the Cachix cache. Add the substituter (as your user or system-wide):

```bash
# one-off per user
nix run nixpkgs#cachix -- use kaivalagi

# or manually
cachix use kaivalagi
```

This adds `https://kaivalagi.cachix.org` to your `nix.conf` substituters and imports its
public key. The GitHub Actions workflow builds on pushes to `main` and `v*` tags and pushes
to this cache, so releases are usually already available.

---

## Development shell

Drop into a shell with the full toolchain (Python runtime + dev tools, Node.js, npm,
gunicorn):

```bash
nix develop
```

Inside the shell:

- `./run_dev.sh` — start the dev server via gunicorn
- `python3 -m config.app` — run the FastAPI app directly
- `npx postcss src/styles.css -o static/css/styles.css` — build the Tailwind CSS
- `pytest` — run the test suite
- `ruff check . && black --check . && isort --check-only .` — lint/format checks

`PYTHONPATH` is set to the repository root and `SETTINGS_MODULE=config.settings.dev`, so the
app runs without a virtualenv.

---

## Building

```bash
# Build the package
nix build .#webzfs        # or: nix build   (uses .#default)

# Check the flake (evaluates + checks all outputs on the host system)
nix flake check

# Show all configureable outputs
nix flake show
```

---

## Development notes

- Python dependencies are derived from `requirements.txt` (the single source of truth) and
  mapped to nixpkgs attribute names with version pins relaxed, since nixpkgs carries its own
  versions.
- The package version is derived from `pyproject.toml` (`tool.poetry.version`), so it is the
  single source of truth for the version. To release a new version, bump it in `pyproject.toml`;
  the Nix package picks it up automatically.
- `ecdsa` is intentionally omitted from the dependency list: `python-jose` falls back to the
  `cryptography` backend, and `ecdsa` is flagged insecure in nixpkgs.
- The package installs to `$out/opt/webzfs/` and provides a `$out/bin/webzfs` wrapper that
  launches `gunicorn` with `PYTHONPATH` set to the source directory.
- Node.js dependencies are pinned via `package-lock.json` in the repository root and prefetched
  during the build.
