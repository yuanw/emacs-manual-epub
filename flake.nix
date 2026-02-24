{
  description = "Generate emacs manual in epub format";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";


    emacs = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
      ];
      imports = [
        inputs.git-hooks-nix.flakeModule
      ];
      perSystem = { config, pkgs, system, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.emacs.overlay
            (final: prev: {
              # ... things you need to patch ...
            })
          ];
          config = { };
        };
        pre-commit.settings.hooks = {
          nixpkgs-fmt.enable = true;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            texinfoInteractive # For makeinfo command to convert .texi to EPUB
            perlPackages.ArchiveZip # Required by makeinfo for EPUB generation
            (pkgs.writeShellScriptBin "emacs-manual-to-epub" ''
              #!/usr/bin/env bash
              set -euo pipefail

              OUTPUT="$HOME/emacs-manual.epub"
              echo "📚 Converting local Emacs manual to EPUB..."

              # Use the Emacs source derivation directly (much faster than find!)
              SOURCE_DIR="${pkgs.emacs-git.src}/doc/emacs"

              if [ ! -d "$SOURCE_DIR" ]; then
                echo "❌ Error: Could not find emacs.texi source files at $SOURCE_DIR"
                exit 1
              fi

              echo "Found source at: $SOURCE_DIR"

              # Create temp directory
              TMPDIR=$(mktemp -d)
              trap "rm -rf $TMPDIR" EXIT

              # Get Emacs version
              EMACS_VERSION=$(${pkgs.emacs-git.src}/bin/emacs --version | head -1 | awk '{print $3}')

              # Generate emacsver.texi
              cat > "$TMPDIR/emacsver.texi" <<EOF
              @set EMACSVER $EMACS_VERSION
              EOF

              # Copy to source directory (read-only, so we work in temp)
              cp -r "$SOURCE_DIR"/* "$TMPDIR/"
              cd "$TMPDIR"

              echo "🔄 Converting to EPUB..."
              # Convert to EPUB with Archive::Zip available
              export PERL5LIB="${pkgs.perlPackages.ArchiveZip}/lib/perl5/site_perl"
              ${pkgs.texinfoInteractive}/bin/makeinfo --epub \
                --output="$OUTPUT" \
                emacs.texi

              echo "✅ Emacs manual saved to: $OUTPUT"
              ls -lh "$OUTPUT"
            '')
            (pkgs.writeShellScriptBin "elisp-manual-to-epub" ''
              #!/usr/bin/env bash
              set -euo pipefail

              OUTPUT="$HOME/elisp-manual.epub"
              echo "📚 Converting local Elisp manual to EPUB..."

              # Use the Emacs source derivation directly (much faster than find!)
              SOURCE_DIR="${pkgs.emacs-git.src}/doc/lispref"

              if [ ! -d "$SOURCE_DIR" ]; then
                echo "❌ Error: Could not find elisp.texi source files at $SOURCE_DIR"
                exit 1
              fi

              echo "Found source at: $SOURCE_DIR"

              # Create temp directory
              TMPDIR=$(mktemp -d)
              trap "rm -rf $TMPDIR" EXIT

              # Get Emacs version
              EMACS_VERSION=$(${pkgs.emacs-git}/bin/emacs --version | head -1 | awk '{print $3}')

              # Generate emacsver.texi (elisp manual also uses this)
              cat > "$TMPDIR/emacsver.texi" <<EOF
              @set EMACSVER $EMACS_VERSION
              @set YEAR $(date +%Y)
              EOF

              # Copy to source directory
              cp -r "$SOURCE_DIR"/* "$TMPDIR/"
              # Copy docstyle.texi from emacs directory (shared file)
              cp "${pkgs.emacs-git.src}/doc/emacs/docstyle.texi" "$TMPDIR/"
              cd "$TMPDIR"

              echo "🔄 Converting to EPUB..."
              # Convert to EPUB with Archive::Zip available
              export PERL5LIB="${pkgs.perlPackages.ArchiveZip}/lib/perl5/site_perl"
              ${pkgs.texinfoInteractive}/bin/makeinfo --epub \
                --output="$OUTPUT" \
                elisp.texi

              echo "✅ Elisp manual saved to: $OUTPUT"
              ls -lh "$OUTPUT"
            '')
          ];
          shellHook = ''
            ${config.pre-commit.shellHook}
          '';
        };
      };

    };
}
