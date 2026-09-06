{
  description = "WebZFS - Web-based ZFS management interface and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in
    {
      nixosModules = rec {
        webzfs = import ./ports/nix/module.nix;
        default = { ... }: {
          imports = [ webzfs ];
        };
      };

      devShells.x86_64-linux.default = import ./ports/nix/dev-shell.nix { inherit pkgs; };
    };
}
