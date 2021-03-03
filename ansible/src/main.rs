use std::collections::{HashSet, VecDeque};
use std::fs::File;
use std::hash::{BuildHasher, BuildHasherDefault, Hash, Hasher};
use std::io::{BufRead, BufReader, BufWriter};
use std::iter::FromIterator;
use std::path::Path;

use anyhow::{anyhow, Result};
use camino::Utf8PathBuf as PathBuf;
use rayon::prelude::*;
use rust_stemmers::{Algorithm, Stemmer};
use sourmash::index::storage::ToWriter;
use sourmash::signature::{Signature, SigsTrait};
use sourmash::sketch::minhash::{max_hash_for_scaled, KmerMinHash};
use sourmash::sketch::Sketch;
use structopt::StructOpt;
use vtext::tokenize::{RegexpTokenizer, Tokenizer};

#[derive(StructOpt, Debug)]
enum Cli {
    /// Build a new MinHash sketch for the dataset
    Sketch {
        /// Input dataset to be sketched
        #[structopt(parse(from_str))]
        dataset: PathBuf,

        /// n-gram size (how many words to group as one element)
        #[structopt(short = "n", long = "ngram-size", default_value = "1")]
        ngram: u8,

        /// scaled (what ratio of n-grams to keep for analysis)
        #[structopt(short = "s", long = "scaled", default_value = "100")]
        scaled: usize,

        /// Output location
        #[structopt(parse(from_str), short = "o", long = "output")]
        output: Option<PathBuf>,
    },
    /// Create a new signature containing the hashes present in all signatures
    Intersect {
        /// List of signatures to intersect (one path per line)
        #[structopt(parse(from_str))]
        signatures: PathBuf,

        /// select sketches with this n-gram size
        #[structopt(short = "n", long = "ngram-size", default_value = "1")]
        ngram: u8,

        /// select sketches with this scaled parameter
        #[structopt(short = "s", long = "scaled", default_value = "100")]
        scaled: usize,

        /// Output location
        #[structopt(parse(from_str), short = "o", long = "output")]
        output: Option<PathBuf>,
    },
    Subtract {
        /// Signature to remove hashes from
        #[structopt(parse(from_str))]
        signature: PathBuf,

        /// Signature containing hashes to be subtracted
        #[structopt(parse(from_str))]
        to_remove: PathBuf,

        /// select sketches with this n-gram size
        #[structopt(short = "n", long = "ngram-size", default_value = "1")]
        ngram: u8,

        /// scaled
        #[structopt(short = "s", long = "scaled", default_value = "10")]
        scaled: usize,

        /// The path for output
        #[structopt(parse(from_str), short = "o", long = "output")]
        output: Option<PathBuf>,
    },
}

fn subtract<P: AsRef<Path> + std::fmt::Debug>(
    mut query_sig: Signature,
    to_remove: P,
    template: &Sketch,
) -> Result<Signature> {
    // select sketch using template
    let mut query_mh = None;
    if let Some(Sketch::MinHash(mh)) = query_sig.select_sketch(&template) {
        query_mh = Some(mh);
    }
    let mut query_mh = query_mh.unwrap().clone();

    // Load hashes to remove
    let to_remove_sig = Signature::from_path(&to_remove)
        .map_err(|_| anyhow!("Error processing {:?}", to_remove))?
        .swap_remove(0);
    // select sketch using template
    let mut to_remove_mh = None;
    if let Some(Sketch::MinHash(mh)) = to_remove_sig.select_sketch(&template) {
        to_remove_mh = Some(mh);
    }
    let to_remove_mh = to_remove_mh.unwrap();

    let hashes_to_remove = to_remove_mh.mins();

    query_mh.remove_many(&hashes_to_remove)?;

    query_sig.reset_sketches();
    query_sig.push(Sketch::MinHash(query_mh));

    Ok(query_sig)
}

fn sketch_fancy<P: AsRef<Path>>(dataset: P, template: &Sketch) -> Result<Sketch> {
    // Init sketch
    let mut mh = template.clone();
    let ngram_size = template.ksize();

    // Open dataset as text
    let file = File::open(dataset)?;
    let reader = BufReader::new(file);

    let common_words: HashSet<String> = HashSet::from_iter(stop_words::get("english"));

    let s = BuildHasherDefault::<twox_hash::Xxh3Hash128>::default();
    let mut hasher = s.build_hasher();
    let mut current_ngram: VecDeque<String> = VecDeque::with_capacity(ngram_size);
    let tokenizer = RegexpTokenizer::default();
    let en_stemmer = Stemmer::create(Algorithm::English);

    for line in reader.lines() {
        let line = line?;
        // use the vtext tokenizer
        for word in tokenizer.tokenize(&line) {
            let word: String = en_stemmer.stem(word).into();
            //let word: String = word.into();

            if !word.is_empty() && !common_words.contains(&word) {
                current_ngram.push_back(word.to_lowercase());
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

fn intersect<P: AsRef<Path>>(signatures: P, template: &Sketch) -> Result<Sketch> {
    // Load sig paths into a vector
    let paths: Vec<PathBuf> = BufReader::new(File::open(signatures)?)
        .lines()
        .map(|line| {
            let mut path = PathBuf::new();
            path.push(line.unwrap());
            path
        })
        .collect();

    let mh: Option<KmerMinHash> = paths
        .par_iter()
        // Map vector for loading the data
        .map(|filename| {
            // load sig
            let search_sig = Signature::from_path(&filename)
                .map_err(|_| anyhow!("Error processing {:?}", filename))
                .ok()?
                .swap_remove(0);
            // select sketch using template
            let mut search_mh = None;
            if let Some(Sketch::MinHash(mh)) = search_sig.select_sketch(&template) {
                search_mh = Some(mh);
            }
            let search_mh = search_mh.unwrap();
            Some(search_mh.clone())
        })
        // Reduce by keeping only intersection
        .reduce(
            || None,
            |a: Option<KmerMinHash>, b: Option<KmerMinHash>| {
                if a.is_none() {
                    return b;
                } else if b.is_none() {
                    return a;
                };

                let mut a = a.unwrap();
                let b = b.unwrap();
                let common = a.intersection(&b).unwrap();
                a.clear();
                a.add_many(&common.0).unwrap();
                Some(a)
            },
        );

    Ok(Sketch::MinHash(mh.unwrap()))
}

fn build_template(scaled: usize, ngram: u8) -> Sketch {
    let max_hash = max_hash_for_scaled(scaled as u64);
    let template_mh = KmerMinHash::builder()
        .num(0)
        .ksize(ngram as u32)
        .max_hash(max_hash)
        .abunds(Some(vec![]))
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
            let mh = sketch_fancy(&dataset, &template)?;

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
        Cli::Intersect {
            signatures,
            output,
            ngram,
            scaled,
        } => {
            let template = build_template(scaled, ngram);
            let mh = intersect(&signatures, &template)?;

            // save mh
            let sig = Signature::builder()
                .name(Some("Intersection".into()))
                .hash_function("0.xxhash_ngram")
                .filename(None)
                .signatures(vec![mh])
                .build();

            let outpath: PathBuf = if let Some(p) = output {
                p
            } else {
                let path: PathBuf = "intersection.sig".into();
                path
            };
            let mut out = BufWriter::new(File::create(outpath)?);
            sig.to_writer(&mut out)?;
        }
        Cli::Subtract {
            signature,
            to_remove,
            output,
            ngram,
            scaled,
        } => {
            let template = build_template(scaled, ngram);
            let query = Signature::from_path(&signature)
                .map_err(|_| anyhow!("Error processing {:?}", signature))?
                .swap_remove(0);
            let sig = subtract(query, &to_remove, &template)?;

            // save sig
            let outpath: PathBuf = if let Some(p) = output {
                p
            } else {
                let mut path: PathBuf = signature;
                path.set_extension("subtracted.sig");
                path
            };
            let mut out = BufWriter::new(File::create(outpath)?);
            sig.to_writer(&mut out)?;
        }
    };

    Ok(())
}

/* This is the initial try, where I'm tokenizing and trimming punctuation myself

fn trim_punctuation(c: char) -> bool {
    matches!(c, '(' | ')' | '-' | '"' | ',' | '?' | '!' | '“' | '”' | '.')
}

fn sketch_naive<P: AsRef<Path>>(dataset: P, template: &Sketch) -> Result<Sketch> {
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
*/
