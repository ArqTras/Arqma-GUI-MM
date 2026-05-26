/// Matches Electron `src/validators/common.js` `register_service_node`.
bool isValidRegisterServiceNodeCommand(String input) {
  final String trimmed = input.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final List<String> tokens = trimmed.split(RegExp(r'\s+'));
  if (tokens.length != 7) {
    return false;
  }
  if (tokens[0] != 'register_service_node') {
    return false;
  }
  final RegExp alnum = RegExp(r'^[0-9A-Za-z]+$');
  if (!alnum.hasMatch(tokens[2])) {
    return false;
  }
  return true;
}
