





enum BackgroundMode {


  never,




  lazy,




  always;



  String get wireValue => name;



  static bool isValid(String raw) =>
      raw == 'never' || raw == 'lazy' || raw == 'always';



  static BackgroundMode fromNative(String? raw) {
    return switch (raw) {
      'lazy' => lazy,
      'always' => always,
      _ => never,
    };
  }
}
