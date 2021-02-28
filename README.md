# Using sourmash with text

This is an experiment about using [sourmash] for working with natural
language (instead of genomic _k_-mers). The goal is to use books for explaining
how MinHash works, and make analogies to why we use _k_-mers for genomic data.

[sourmash]: http://sourmash.bio

## Example 1: The Dispossessed

Plotting the similarity between chapters in [The Dispossessed](http://self.gutenberg.org/articles/The_Dispossessed),
by Ursula K. Le Guin.

I wanted to check this because the book alternates between two different places
(Anarres and Urras) and timeframes (past and present), so do they also cluster
together (even and odd chapters numbers)?

![](https://github.com/luizirber/2021-02-26-text-minhash/raw/gh-pages/n1-s1.matrix.png)

Seems like they do, and even chapter 13 (which is in another place) also
separates from the other two clusters.

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
