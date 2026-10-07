{
  description = "Reproducible QuickNotes builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          appSource = pkgs.lib.fileset.toSource {
            root = ./app;
            fileset = pkgs.lib.fileset.fileFilter (
              file: file.name == "go.mod" || file.name == "go.sum" || file.hasExt "go"
            ) ./app;
          };

          quicknotes = pkgs.buildGoModule {
            pname = "quicknotes";
            version = "0.1.0";
            src = appSource;

            # QuickNotes imports only the Go standard library, so there is no
            # dependency tree for buildGoModule's fixed-output fetcher to hash.
            vendorHash = null;

            env.CGO_ENABLED = "0";
            ldflags = [
              "-s"
              "-w"
            ];
            subPackages = [ "." ];
          };

          imageRoot = pkgs.buildEnv {
            name = "quicknotes-image-root";
            paths = [ quicknotes ];
            pathsToLink = [ "/bin" ];
          };

          docker = pkgs.dockerTools.buildImage {
            name = "quicknotes";
            tag = "nix";
            created = "1970-01-01T00:00:01Z";
            copyToRoot = imageRoot;

            extraCommands = ''
              mkdir -p app etc tmp
              cp ${./app/seed.json} app/seed.json
              chmod 0755 app
              chmod 1777 tmp
              printf '%s\n' \
                'root:x:0:0:root:/root:/sbin/nologin' \
                'nonroot:x:65532:65532:nonroot:/nonexistent:/sbin/nologin' \
                > etc/passwd
              printf '%s\n' \
                'root:x:0:' \
                'nonroot:x:65532:' \
                > etc/group
              chmod 0644 app/seed.json etc/passwd etc/group
            '';

            config = {
              Entrypoint = [ "/bin/quicknotes" ];
              Env = [
                "ADDR=0.0.0.0:8080"
                "DATA_PATH=/tmp/notes.json"
                "SEED_PATH=/app/seed.json"
              ];
              ExposedPorts = {
                "8080/tcp" = { };
              };
              User = "nonroot:nonroot";
              WorkingDir = "/app";
            };
          };
        in
        {
          inherit docker quicknotes;
          default = quicknotes;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              go
              golangci-lint
              gopls
            ];
          };
        }
      );
    };
}
