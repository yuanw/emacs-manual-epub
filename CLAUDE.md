# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project generates Emacs and Elisp manuals in EPUB format using Nix. It provides shell scripts that convert the `.texi` source files from the Emacs source tree to EPUB using `makeinfo`.

## Development Commands

Enter the development environment:
```bash
nix develop
```

Generate Emacs manual (outputs to ~/emacs-manual.epub):
```bash
emacs-manual-to-epub
```

Generate Elisp manual (outputs to ~/elisp-manual.epub):
```bash
elisp-manual-to-epub
```

## Architecture

The entire project is defined in `flake.nix`:
- Uses `flake-parts` for Nix flake structure
- Pulls Emacs source from `nix-community/emacs-overlay` (emacs-git)
- Defines two shell scripts in the devShell that convert `.texi` files to EPUB using `texinfoInteractive` and `perlPackages.ArchiveZip`
- Pre-commit hooks configured via `git-hooks-nix` (runs `nixpkgs-fmt`)

## Pre-commit Hooks

The project uses `nixpkgs-fmt` for Nix file formatting. Hooks are automatically set up when entering `nix develop`.
