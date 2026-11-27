// SPDX-License-Identifier: GPL-3.0-only
//! Bounded framing; discard the whole oversized record, including its tail.
pub struct LineFramer {
    bytes: Vec<u8>,
    maximum: usize,
    discarding: bool,
}

impl LineFramer {
    pub fn new(maximum: usize) -> Self {
        Self { bytes: Vec::new(), maximum, discarding: false }
    }

    pub fn feed(&mut self, input: &[u8], mut emit: impl FnMut(&[u8])) {
        for &byte in input {
            if byte == b'\n' || byte == 0 {
                if !self.discarding && !self.bytes.is_empty() { emit(&self.bytes); }
                self.bytes.clear();
                self.discarding = false;
            } else if byte != b'\r' && !self.discarding {
                if self.bytes.len() == self.maximum {
                    self.bytes.clear();
                    self.discarding = true;
                } else {
                    self.bytes.push(byte);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::LineFramer;

    #[test]
    fn joins_partial_records_and_accepts_both_terminators() {
        let mut framer = LineFramer::new(8);
        let mut lines = Vec::new();
        framer.feed(b"fir", |line| lines.push(line.to_vec()));
        framer.feed(b"st\r\nnext\0", |line| lines.push(line.to_vec()));
        assert_eq!(lines, [b"first".to_vec(), b"next".to_vec()]);
    }

    #[test]
    fn drops_oversized_tail_until_terminator() {
        let mut framer = LineFramer::new(4);
        let mut lines = Vec::new();
        framer.feed(b"12345", |line| lines.push(line.to_vec()));
        framer.feed(b"fake\nreal\n", |line| lines.push(line.to_vec()));
        assert_eq!(lines, [b"real".to_vec()]);
    }

    #[test]
    fn accepts_exact_limit_without_emitting_unterminated_data() {
        let mut framer = LineFramer::new(4);
        let mut lines = Vec::new();
        framer.feed(b"1234", |line| lines.push(line.to_vec()));
        assert!(lines.is_empty());
        framer.feed(b"\0", |line| lines.push(line.to_vec()));
        assert_eq!(lines, [b"1234".to_vec()]);
    }
}
