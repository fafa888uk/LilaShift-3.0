// SPDX-License-Identifier: MIT
// LilaShift addition: reject a wrong, truncated or malformed TLS 1.2 Finished.
// Kept independent of the transport so host tests exercise the production check.
pub fn matches_server_finished(plaintext: &[u8], expected: &[u8]) -> bool {
    expected.len() == 12
        && plaintext.len() == 16
        && plaintext[..4] == [0x14, 0, 0, 12]
        && plaintext[4..] == *expected
}

#[cfg(test)]
mod tests {
    use super::matches_server_finished;

    fn message() -> Vec<u8> {
        let mut value = vec![0x14, 0, 0, 12];
        value.extend_from_slice(&[7u8; 12]);
        value
    }

    #[test]
    fn accepts_matching_finished() {
        assert!(matches_server_finished(&message(), &[7u8; 12]));
    }

    #[test]
    fn rejects_wrong_proof() {
        assert!(!matches_server_finished(&message(), &[8u8; 12]));
    }

    #[test]
    fn rejects_truncation_wrong_length_and_wrong_message_type() {
        let mut value = message();
        assert!(!matches_server_finished(&value[..15], &[7u8; 12]));
        value[3] = 11;
        assert!(!matches_server_finished(&value, &[7u8; 12]));
        value[3] = 12;
        value[0] = 0x0e;
        assert!(!matches_server_finished(&value, &[7u8; 12]));
    }
}
