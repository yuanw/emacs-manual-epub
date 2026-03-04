{
  description = "Generate emacs manual in epub format";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      imports = [
        inputs.git-hooks-nix.flakeModule
      ];
      perSystem = { config, pkgs, system, ... }:
        let
          emacs-src-info = builtins.fromJSON (builtins.readFile ./emacs-src.json);
          emacs-src = pkgs.fetchgit {
            url = "https://git.savannah.gnu.org/git/emacs.git";
            inherit (emacs-src-info) rev hash;
            sparseCheckout = [ "doc" "configure.ac" ];
          };
          emacs-cover = pkgs.fetchurl {
            url = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/41/GNU_Emacs_manual_cover_design.png/500px-GNU_Emacs_manual_cover_design.png";
            hash = "sha256-ZZC+CiWCZrA/Ayzl37XJNGNttmVQb7SMmfqggqqZ+bM=";
          };
          elisp-cover = pkgs.fetchurl {
            url = "https://www.gnu.org/graphics/use-gnu.png";
            hash = "sha256-f8RM2D4xODOiznCNxXW1vEvW7HEZHx7b45RvupBaI1M=";
          };
          add-epub-cover = pkgs.writeText "add-epub-cover.py" ''
            import zipfile, sys, os, re
            epub_path, cover_path, out_path = sys.argv[1:4]
            cover_ext = os.path.splitext(cover_path)[1].lower()
            cover_name = 'cover' + cover_ext
            media_type = {'png': 'image/png', 'jpg': 'image/jpeg'}.get(cover_ext[1:], 'image/png')
            with zipfile.ZipFile(epub_path, 'r') as zin:
                names = zin.namelist()
                contents = {n: zin.read(n) for n in names}
            container = contents['META-INF/container.xml'].decode()
            opf_path = re.search('full-path="([^"]+\\.opf)"', container).group(1)
            opf_dir = os.path.dirname(opf_path)
            opf = contents[opf_path].decode()
            item = '<item id="cover-image" properties="cover-image" media-type="' + media_type + '" href="' + cover_name + '"/>'
            opf = re.sub(r'(<manifest[^>]*>)', r'\1\n      ' + item, opf)
            opf = re.sub(r'(</metadata>)', '      <meta name="cover" content="cover-image"/>\n   ' + r'\1', opf)
            cover_epub_path = (opf_dir + "/" if opf_dir else "") + cover_name
            with open(cover_path, 'rb') as f:
                cover_data = f.read()
            with zipfile.ZipFile(out_path, 'w') as zout:
                zout.writestr('mimetype', contents['mimetype'], compress_type=zipfile.ZIP_STORED)
                for name in names:
                    if name == 'mimetype':
                        continue
                    data = opf.encode() if name == opf_path else contents[name]
                    zout.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)
                zout.writestr(cover_epub_path, cover_data, compress_type=zipfile.ZIP_DEFLATED)
          '';
        in
        {
          pre-commit.settings.hooks = {
            nixpkgs-fmt.enable = true;
          };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              texinfoInteractive # For makeinfo command to convert .texi to EPUB
              perlPackages.ArchiveZip # Required by makeinfo for EPUB generation
              (pkgs.writeShellScriptBin "update-emacs-src" ''
                #!/usr/bin/env bash
                set -euo pipefail

                JSON_FILE="''${1:-./emacs-src.json}"

                if [ ! -f "$JSON_FILE" ]; then
                  echo "Error: $JSON_FILE not found"
                  exit 1
                fi

                echo "Fetching latest Emacs commit..."
                NEW_REV=$(${pkgs.git}/bin/git ls-remote https://git.savannah.gnu.org/git/emacs.git HEAD | cut -f1)
                echo "Latest commit: $NEW_REV"

                CURRENT_REV=$(${pkgs.jq}/bin/jq -r '.rev' "$JSON_FILE")
                if [ "$NEW_REV" = "$CURRENT_REV" ]; then
                  echo "Already up to date!"
                  exit 0
                fi

                echo "Current commit: $CURRENT_REV"
                echo "Prefetching new source (this may take a while)..."

                PREFETCH_OUTPUT=$(${pkgs.nix-prefetch-git}/bin/nix-prefetch-git \
                  --url https://git.savannah.gnu.org/git/emacs.git \
                  --rev "$NEW_REV" \
                  --sparse-checkout "$(printf 'doc\nconfigure.ac')" \
                  2>/dev/null)

                NEW_HASH=$(echo "$PREFETCH_OUTPUT" | ${pkgs.jq}/bin/jq -r '.hash')
                echo "New hash: $NEW_HASH"

                echo "Updating $JSON_FILE..."
                ${pkgs.jq}/bin/jq -n \
                  --arg rev "$NEW_REV" \
                  --arg hash "$NEW_HASH" \
                  '{rev: $rev, hash: $hash}' > "$JSON_FILE"

                echo "Done! Updated emacs-src to $NEW_REV"
              '')
              (pkgs.writeShellScriptBin "emacs-manual-to-epub" ''
                #!/usr/bin/env bash
                set -euo pipefail

                OUTPUT="''${1:-$HOME/emacs-manual.epub}"
                # Convert to absolute path before changing directories
                OUTPUT=$(realpath -m "$OUTPUT")
                mkdir -p "$(dirname "$OUTPUT")"
                echo "📚 Converting local Emacs manual to EPUB..."

                # Use the Emacs source derivation directly (much faster than find!)
                SOURCE_DIR="${emacs-src}/doc/emacs"

                if [ ! -d "$SOURCE_DIR" ]; then
                  echo "❌ Error: Could not find emacs.texi source files at $SOURCE_DIR"
                  exit 1
                fi

                echo "Found source at: $SOURCE_DIR"

                # Create temp directory
                TMPDIR=$(mktemp -d)
                trap "rm -rf $TMPDIR" EXIT

                # Get Emacs version from configure.ac
                EMACS_VERSION=$(grep -oP 'AC_INIT\(\[GNU Emacs\], \[\K[^\]]+' ${emacs-src}/configure.ac)

                # Generate emacsver.texi
                cat > "$TMPDIR/emacsver.texi" <<EOF
                @set EMACSVER $EMACS_VERSION
                EOF

                # Copy to source directory (read-only, so we work in temp)
                cp -r "$SOURCE_DIR"/* "$TMPDIR/"
                cd "$TMPDIR"

                # Provide htmlxref.cnf entries for external manuals referenced by emacs.texi
                cat > "$TMPDIR/htmlxref.cnf" <<EOF
                eintr node https://www.gnu.org/software/emacs/manual/html_node/eintr/
                eintr mono https://www.gnu.org/software/emacs/manual/eintr/eintr.html
                EOF

                echo "🔄 Converting to EPUB..."
                # Convert to EPUB with Archive::Zip available
                export PERL5LIB="${pkgs.perlPackages.ArchiveZip}/lib/perl5/site_perl"
                ${pkgs.texinfoInteractive}/bin/makeinfo --epub \
                  --output="$OUTPUT" \
                  emacs.texi

                echo "📖 Adding cover image..."
                ${pkgs.python3}/bin/python3 ${add-epub-cover} "$OUTPUT" "${emacs-cover}" "$OUTPUT.tmp"
                mv "$OUTPUT.tmp" "$OUTPUT"

                echo "✅ Emacs manual saved to: $OUTPUT"
                ls -lh "$OUTPUT"
              '')
              (pkgs.writeShellScriptBin "elisp-manual-to-epub" ''
                #!/usr/bin/env bash
                set -euo pipefail

                OUTPUT="''${1:-$HOME/elisp-manual.epub}"
                # Convert to absolute path before changing directories
                OUTPUT=$(realpath -m "$OUTPUT")
                mkdir -p "$(dirname "$OUTPUT")"
                echo "📚 Converting local Elisp manual to EPUB..."

                # Use the Emacs source derivation directly (much faster than find!)
                SOURCE_DIR="${emacs-src}/doc/lispref"

                if [ ! -d "$SOURCE_DIR" ]; then
                  echo "❌ Error: Could not find elisp.texi source files at $SOURCE_DIR"
                  exit 1
                fi

                echo "Found source at: $SOURCE_DIR"

                # Create temp directory
                TMPDIR=$(mktemp -d)
                trap "rm -rf $TMPDIR" EXIT

                # Get Emacs version from configure.ac
                EMACS_VERSION=$(grep -oP 'AC_INIT\(\[GNU Emacs\], \[\K[^\]]+' ${emacs-src}/configure.ac)

                # Generate emacsver.texi (elisp manual also uses this)
                cat > "$TMPDIR/emacsver.texi" <<EOF
                @set EMACSVER $EMACS_VERSION
                @set YEAR $(date +%Y)
                EOF

                # Copy to source directory
                cp -r "$SOURCE_DIR"/* "$TMPDIR/"
                # Copy docstyle.texi from emacs directory (shared file)
                cp "${emacs-src}/doc/emacs/docstyle.texi" "$TMPDIR/"
                cd "$TMPDIR"

                echo "🔄 Converting to EPUB..."
                # Convert to EPUB with Archive::Zip available
                export PERL5LIB="${pkgs.perlPackages.ArchiveZip}/lib/perl5/site_perl"
                ${pkgs.texinfoInteractive}/bin/makeinfo --epub \
                  --output="$OUTPUT" \
                  elisp.texi

                echo "📖 Adding cover image..."
                ${pkgs.python3}/bin/python3 ${add-epub-cover} "$OUTPUT" "${elisp-cover}" "$OUTPUT.tmp"
                mv "$OUTPUT.tmp" "$OUTPUT"

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
