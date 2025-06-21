{
    description = "A flake providing a development shell with Zig compiler.";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs";
    };

    outputs = { self, nixpkgs }:
    let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
     {
        devShell.x86_64-linux = pkgs.mkShellNoCC {
            packages = with pkgs; [
                zig
            ];
        };
    };
}