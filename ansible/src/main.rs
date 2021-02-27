use std::collections::VecDeque;
use std::fs::File;
use std::hash::{BuildHasher, BuildHasherDefault, Hash, Hasher};
use std::io::{BufRead, BufReader, BufWriter};
use std::path::Path;

use anyhow::Result;
use camino::Utf8PathBuf as PathBuf;
use sourmash::index::storage::ToWriter;
use sourmash::signature::{Signature, SigsTrait};
use sourmash::sketch::minhash::{max_hash_for_scaled, KmerMinHash};
use sourmash::sketch::Sketch;
use structopt::StructOpt;

#[derive(StructOpt, Debug)]
enum Cli {
    Sketch {
        /// Input dataset to be sketched
        #[structopt(parse(from_str))]
        dataset: PathBuf,

        /// n-gram size (how many words to group as one element)
        #[structopt(short = "n", long = "ngram-size", default_value = "3")]
        ngram: u8,

        /// scaled (what ratio of n-grams to keep for analysis)
        #[structopt(short = "s", long = "scaled", default_value = "100")]
        scaled: usize,

        /// Output location
        #[structopt(parse(from_str), short = "o", long = "output")]
        output: Option<PathBuf>,
    },
}

fn trim_punctuation(c: char) -> bool {
    matches!(c, '(' | ')' | '-' | '"' | ',' | '?' | '!' | '“' | '”' | '.')
}

fn sketch<P: AsRef<Path>>(dataset: P, template: &Sketch) -> Result<Sketch> {
    // Init sketch
    let mut mh = template.clone();
    let ngram_size = template.ksize();

    // Open dataset as text
    let file = File::open(dataset)?;
    let reader = BufReader::new(file);

    let s = BuildHasherDefault::<twox_hash::Xxh3Hash128>::default();
    let mut hasher = s.build_hasher();
    let mut current_ngram: VecDeque<String> = VecDeque::with_capacity(ngram_size);

    for line in reader.lines() {
        let line = line?;
        // split on spaces and for each word
        for word in line.split(' ') {
            // trim punctuation ( ) - " , ?
            let word = word.trim_matches(trim_punctuation).to_lowercase();

            if !word.is_empty() {
                current_ngram.push_back(word);
            };

            if current_ngram.len() == ngram_size {
                current_ngram.hash(&mut hasher);
                let hash = hasher.finish();
                hasher = s.build_hasher();
                current_ngram.pop_front();

                // add to sketch (skip add_word, use add_hash directly)
                if let Sketch::MinHash(ref mut mh) = mh {
                    mh.add_hash(hash);
                };
            }
        }
    }

    Ok(mh)
}

fn build_template(scaled: usize, ngram: u8) -> Sketch {
    let max_hash = max_hash_for_scaled(scaled as u64);
    let template_mh = KmerMinHash::builder()
        .num(0)
        .ksize(ngram as u32)
        .max_hash(max_hash)
        .build();
    Sketch::MinHash(template_mh)
}

fn main() -> Result<()> {
    match Cli::from_args() {
        Cli::Sketch {
            dataset,
            output,
            ngram,
            scaled,
        } => {
            let template = build_template(scaled, ngram);
            let mh = sketch(&dataset, &template)?;

            // save mh
            let sig = Signature::builder()
                .name(Some(dataset.file_name().unwrap().into()))
                .hash_function("0.xxhash_ngram")
                .filename(None)
                .signatures(vec![mh])
                .build();

            let outpath: PathBuf = if let Some(p) = output {
                p
            } else {
                let mut path: PathBuf = dataset;
                path.set_extension("sig");
                path
            };
            let mut out = BufWriter::new(File::create(outpath)?);
            sig.to_writer(&mut out)?;
        }
    };

    Ok(())
}
