{
    description = "A flake providing a development shell with Zig compiler.";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs";
    };

    outputs = { self, nixpkgs }:
    let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        zigVersion = builtins.readFile ./.zigversion;
        zigVersionTrimmed = builtins.replaceStrings ["\n"] [""] zigVersion;
    in
     {
        devShell.x86_64-linux = pkgs.mkShellNoCC {
            packages = with pkgs; [
                (zig.overrideAttrs (oldAttrs: {
                    version = zigVersionTrimmed;
                    src = pkgs.fetchurl {
                        url = "https://ziglang.org/download/${zigVersionTrimmed}/zig-x86_64-linux-${zigVersionTrimmed}.tar.xz";
                        sha256 = "24aeeec8af16c381934a6cd7d95c807a8cb2cf7df9fa40d359aa884195c4716c"; # sha256 for 0.14.1
                    };
                }))
                nvme-cli
                qemu_full
                gdb
            ];
        };
    };
}