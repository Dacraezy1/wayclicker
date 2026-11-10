{
  description = "Wayclicker - simple autoclicker for Linux (Wayland & X11)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).package.version;
    in
    {
      packages = forAll (pkgs: rec {
        # Command-line program only (always builds from source with cargo).
        wayclicker-cli = pkgs.rustPlatform.buildRustPackage {
          pname = "wayclicker";
          inherit version;
          src = self;
          cargoLock.lockFile = ./Cargo.lock;
          meta = {
            description = "Simple autoclicker for Linux (Wayland & X11)";
            homepage = "https://github.com/Dacraezy1/wayclicker";
            license = pkgs.lib.licenses.gpl3Only;
            mainProgram = "wayclicker";
            platforms = pkgs.lib.platforms.linux;
          };
        };

        # Graphical front-end (Flutter). It finds the CLI through PATH.
        wayclicker-gui = pkgs.flutter.buildFlutterApplication {
          pname = "wayclicker_gui";
          inherit version;
          src = ./gui;
          autoPubspecLock = ./gui/pubspec.lock;
          extraWrapProgramArgs = "--prefix PATH : ${pkgs.lib.makeBinPath [ wayclicker-cli ]}";
          meta = {
            description = "GUI for Wayclicker";
            license = pkgs.lib.licenses.gpl3Only;
            mainProgram = "wayclicker_gui";
            platforms = pkgs.lib.platforms.linux;
          };
        };

        # GUI + CLI together, with the "wayclicker-gui" launcher name.
        wayclicker = pkgs.symlinkJoin {
          name = "wayclicker-${version}";
          paths = [ wayclicker-cli wayclicker-gui ];
          postBuild = ''
            ln -s $out/bin/wayclicker_gui $out/bin/wayclicker-gui
            mkdir -p $out/share/applications $out/share/icons/hicolor/scalable/apps
            install -Dm644 ${./wayclicker.desktop} $out/share/applications/wayclicker.desktop
            install -Dm644 ${./assets/wayclicker.svg} $out/share/icons/hicolor/scalable/apps/wayclicker.svg
          '';
          meta.mainProgram = "wayclicker";
        };

        default = wayclicker;
      });

      apps = forAll (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.wayclicker}/bin/wayclicker-gui";
        };
        cli = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.wayclicker-cli}/bin/wayclicker";
        };
      });

      # NixOS: programs.wayclicker.enable = true; then add your user to "input".
      nixosModules.default = { config, lib, pkgs, ... }: {
        options.programs.wayclicker.enable = lib.mkEnableOption "Wayclicker autoclicker";
        config = lib.mkIf config.programs.wayclicker.enable {
          environment.systemPackages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
          boot.kernelModules = [ "uinput" ];
          services.udev.extraRules = ''
            KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
          '';
        };
      };

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.cargo pkgs.rustc pkgs.clippy pkgs.rustfmt pkgs.flutter ];
        };
      });
    };
}
