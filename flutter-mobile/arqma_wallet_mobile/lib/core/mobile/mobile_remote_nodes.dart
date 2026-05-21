/// Official Arqma public remote nodes (mainnet RPC port 19994).
const int kArqmaMainnetRemotePort = 19994;

const List<String> kMobileRemoteNodeHosts = <String>[
  'node1.arqma.com',
  'node2.arqma.com',
  'node3.arqma.com',
  'node4.arqma.com',
];

const String kMobileDefaultRemoteHost = 'node1.arqma.com';

List<Map<String, dynamic>> mobileRemoteNodesJson() {
  return kMobileRemoteNodeHosts
      .map(
        (String host) => <String, dynamic>{
          'host': host,
          'port': kArqmaMainnetRemotePort,
        },
      )
      .toList();
}

bool isAllowedMobileRemoteHost(String host) {
  return kMobileRemoteNodeHosts.contains(host.trim());
}
