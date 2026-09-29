



class PprofProfile {
  const PprofProfile({
    required this.id,
    required this.label,
    required this.pathAndQuery,
    required this.fileBase,
    required this.isText,
    required this.blockingSeconds,
  });


  final String id;


  final String label;


  final String pathAndQuery;


  final String fileBase;


  final bool isText;


  final int blockingSeconds;

  String get fileExt => isText ? 'txt' : 'pb';








  static const all = <PprofProfile>[
    PprofProfile(
      id: 'goroutine',
      label: 'Goroutines (summary)',
      pathAndQuery: 'goroutine?debug=1',
      fileBase: 'goroutines-summary',
      isText: true,
      blockingSeconds: 0,
    ),
    PprofProfile(
      id: 'goroutine',
      label: 'Goroutines (full stacks)',
      pathAndQuery: 'goroutine?debug=2',
      fileBase: 'goroutines',
      isText: true,
      blockingSeconds: 0,
    ),
    PprofProfile(
      id: 'profile',
      label: 'CPU profile (10s)',
      pathAndQuery: 'profile?seconds=10',
      fileBase: 'cpu',
      isText: false,
      blockingSeconds: 10,
    ),
    PprofProfile(
      id: 'heap',
      label: 'Heap (inuse_space)',
      pathAndQuery: 'heap?gc=1',
      fileBase: 'heap',
      isText: false,
      blockingSeconds: 0,
    ),
    PprofProfile(
      id: 'allocs',
      label: 'Allocations',
      pathAndQuery: 'allocs',
      fileBase: 'allocs',
      isText: false,
      blockingSeconds: 0,
    ),
  ];
}
