//! Run child processes in the background — on Windows without an extra console window
//! (`CREATE_NO_WINDOW`), matching the expected hidden behaviour of `arqmad` / `wallet-rpc`.

use std::path::Path;
use std::process::Command;

/// `winbase.h` flag — process without its own window (console stays hidden by default).
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// `std::process::Command` for background binaries; on Windows uses
/// `creation_flags(CREATE_NO_WINDOW)`.
pub fn new_child_command (program: impl AsRef<Path>) -> Command {
  let mut cmd = Command::new(program.as_ref());
  #[cfg(windows)]
  {
    use std::os::windows::process::CommandExt;
    cmd.creation_flags(CREATE_NO_WINDOW);
  }
  cmd
}
