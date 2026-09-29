





class MemoryLimitSetting {
  MemoryLimitSetting._();

  static const auto = 'auto';
  static const off = 'off';


  static const values = <String>[auto, off, '200', '384', '512', '768'];



  static String normalize(String? raw) => values.contains(raw) ? raw! : auto;
}
