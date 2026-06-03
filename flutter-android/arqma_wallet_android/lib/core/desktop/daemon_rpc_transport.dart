// Arqma daemon JSON-RPC transport helpers (shared desktop + mobile semantics).
//
// Reference `arqmad` nodes expose JSON-RPC over plain HTTP on the RPC port.
// TLS is not part of the default wire protocol; remote sync metadata may be
// visible on untrusted networks unless the operator terminates TLS upstream.

bool isRemoteDaemonType(String? daemonType) {
  return (daemonType ?? 'local') == 'remote';
}

/// True when the configured daemon entry uses a remote host (cleartext HTTP in app).
bool configUsesRemoteCleartextRpc(Map<String, dynamic> configDaemon) {
  return isRemoteDaemonType(configDaemon['type'] as String?);
}
