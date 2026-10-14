// M1 corpus program (Rust): std collections, formatting, iterators, errors.
use std::collections::HashMap;
use std::io::{self, BufRead};

#[derive(Debug)]
enum Op { Add(i64), Mul(i64), Neg }

fn parse(line: &str) -> Result<Op, String> {
    let mut it = line.split_whitespace();
    match (it.next(), it.next()) {
        (Some("add"), Some(n)) => n.parse().map(Op::Add).map_err(|e| e.to_string()),
        (Some("mul"), Some(n)) => n.parse().map(Op::Mul).map_err(|e| e.to_string()),
        (Some("neg"), None) => Ok(Op::Neg),
        _ => Err(format!("bad line: {line}")),
    }
}

fn main() {
    let mut acc: i64 = 0;
    let mut seen: HashMap<String, usize> = HashMap::new();
    for line in io::stdin().lock().lines().map_while(Result::ok) {
        match parse(&line) {
            Ok(op) => {
                *seen.entry(format!("{op:?}").split('(').next().unwrap().to_string()).or_default() += 1;
                acc = match op { Op::Add(n) => acc + n, Op::Mul(n) => acc * n, Op::Neg => -acc };
            }
            Err(e) => eprintln!("{e}"),
        }
    }
    let mut v: Vec<_> = seen.into_iter().collect();
    v.sort();
    println!("{acc} {v:?}");
}
