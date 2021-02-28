# Using sourmash with text

This is an experiment about using [sourmash](sourmash) for working with natural
language (instead of genomic _k_-mers). The goal is to use books for explaining
how MinHash works, and make analogies to why we use _k_-mers for genomic data.

[sourmash]: http://sourmash.bio

## Code organization

There are two pieces in this repo:
- [`ansible`](./ansible), a very minimal CLI written in Rust for transforming a text file
  into a sourmash signature.
- A [Snakemake pipeline](./Snakefile) for downloading data, building signature with
 `ansible`,  and running sourmash `compare` and `plot` commands to generate
 pretty pictures.

## Setup

This projects depends on Snakemake, sourmash, pandoc, wget and a Rust compiler.
If you don't want to download and install them yourself, you can use Nix
to manage it for you:
- Clone the repo.
- [Install nix](https://nixos.org/guides/install-nix.html).
- run `nix-shell` in the repo directory to open a shell with all deps installed.
- run `snakemake -j1` to process the pipeline and generate figures
