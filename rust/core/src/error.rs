use thiserror::Error;

/// Błędy domeny core (I/O, konfiguracja, walidacja). RPC zwraca własne kody; tutaj tylko warstwa rdzenia.
#[derive(Error, Debug)]
pub enum CoreError {
    #[error("JSON: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("IO: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid configuration: {0}")]
    InvalidConfig(String),
}
