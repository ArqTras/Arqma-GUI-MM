use serde::{Deserialize, Serialize};

/// Ścieżki danych użytkownika (odpowiednik `Backend.config_dir` / `wallet_dir` z `backend.js`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArqmaPaths {
    pub config_dir: String,
    pub wallet_dir: String,
}

/// Domyślne węzły zdalne (z `Backend.defaultRemotes` w starym backendzie).
pub fn default_remote_nodes() -> Vec<RemoteNode> {
    (1..=5)
        .map(|n| RemoteNode {
            host: format!("node{n}.arqma.com"),
            port: 19994,
        })
        .collect()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteNode {
    pub host: String,
    pub port: u16,
}

/// Migawka pól, które UI ładowało z `set_app_data` (uproszczona; będzie rozszerzana przy porcie `WalletRPC`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AppConfigSnapshot {
    pub net_type: String,
    pub data_dir: String,
    pub wallet_data_dir: String,
}

impl AppConfigSnapshot {
    pub fn mainnet_default(paths: &ArqmaPaths) -> Self {
        Self {
            net_type: "mainnet".into(),
            data_dir: paths.config_dir.clone(),
            wallet_data_dir: paths.wallet_dir.clone(),
        }
    }
}

/// Oblicz domyślne ścieżki dla bieżącego OS (Windows vs reszta).
pub fn default_paths() -> ArqmaPaths {
    if cfg!(target_os = "windows") {
        let home = std::env::var("USERPROFILE").unwrap_or_else(|_| ".".into());
        ArqmaPaths {
            config_dir: r"C:\ProgramData\arqma".to_string(),
            wallet_dir: format!(r"{home}\Documents\arqma"),
        }
    } else {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
        ArqmaPaths {
            config_dir: format!("{home}/.arqma"),
            wallet_dir: format!("{home}/arqma"),
        }
    }
}
