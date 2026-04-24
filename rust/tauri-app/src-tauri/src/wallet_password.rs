//! PBKDF2 (SHA-512, 1000 iterations) — matches `crypto.pbkdf2Sync` in `wallet-rpc.js`.

use hmac::Hmac;
use pbkdf2::pbkdf2;
use sha2::Sha512;

const PBKDF2_ROUNDS: u32 = 1000;
const KEY_LEN: usize = 64;

type HmacSha512 = Hmac<Sha512>;

/// Returns 128-char hex (64 bytes), same as `buffer.toString("hex")` in Node.
pub fn pbkdf2_password_hex (password: &str, salt_hex: &str) -> Result<String, String> {
  if salt_hex.len() != 64 {
    return Err("salt: expected 64 hex characters (32 B)".to_string());
  }
  let salt = hex::decode(salt_hex).map_err(|e| e.to_string())?;
  if salt.len() != 32 {
    return Err("salt: expected 32 bytes".to_string());
  }
  let mut out = [0u8; KEY_LEN];
  pbkdf2::<HmacSha512>(password.as_bytes(), &salt, PBKDF2_ROUNDS, &mut out).map_err(|e| {
    format!("pbkdf2: {e}")
  })?;
  Ok(hex::encode(out))
}