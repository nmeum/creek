{
    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = {
        nixpkgs,
        flake-utils,
        ...
    }: flake-utils.lib.eachSystem ["x86_64-linux"] (system:
        let
            pkgs = import nixpkgs {
                inherit system;
            };

            slstatus = (with pkgs; stdenv.mkDerivation rec {
                pname = "creek";
                version = "4.3";

                src = ./.;
               
                nativeBuildInputs = [
                    zig.hook
                    pkg-config
                    wayland-scanner
                ];
                buildInputs = [
                    fcft
                    pixman
                    wayland
                    wayland-protocols
                ];
               
                deps = pkgs.linkFarm "zig-packages" [
                    {
                        name = "fcft-2.0.0-zcx6C5EaAADIEaQzDg5D4UvFFMjSEwDE38vdE9xObeN9";
                        path = fetchzip {
                          url = "https://git.sr.ht/~novakane/zig-fcft/archive/v2.0.0.tar.gz";
                          hash = "sha256-qDEtiZNSkzN8jUSnZP/itqh8rMf+lakJy4xMB0I8sxQ=";
                        };
                    }
                    {
                        name = "pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX";
                        path = fetchzip {
                            url = "https://codeberg.org/ifreund/zig-pixman/archive/v0.3.0.tar.gz";
                            hash = "sha256-8tA4auo5FEI4IPnomV6bkpQHUe302tQtorFQZ1l14NU=";
                        };
                    }
                    {
                        name = "wayland-0.3.0-lQa1kjPIAQDmhGYpY-zxiRzQJFHQ2VqhJkQLbKKdt5wl";
                        path = fetchzip {
                            url = "https://codeberg.org/ifreund/zig-wayland/archive/v0.3.0.tar.gz";
                            hash = "sha256-ydEavD9z20wRwn9ZVX56ZI2T5i1tnm3LupVxfa30o84=";
                        };
                    }
                ];

                zigBuildFlags = [
                    "--system"
                    "${deps}"
                ];
            });
        in {
          defaultPackage = slstatus;
        }
    );
}
