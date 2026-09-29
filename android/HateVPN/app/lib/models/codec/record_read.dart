
library;


final class RecordRead<T> {
  const RecordRead.ok(T this.value, {this.unknownKeys = const []})
      : dropped = null;
  const RecordRead.drop(String this.dropped)
      : value = null,
        unknownKeys = const [];

  final T? value;


  final String? dropped;



  final List<String> unknownKeys;
}
