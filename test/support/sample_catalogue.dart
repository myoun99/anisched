import 'package:anisched/src/services/catalogue_store.dart';
import 'package:anisched/src/services/database.dart';
import 'package:anisched/src/services/sample_data.dart';

/// The app's example catalogue ([fillSample]) in an in-memory database
/// whose clock is [now].
CatalogueStore sampleCatalogue(DateTime now) {
  final store = CatalogueStore(openAppDatabase(':memory:'), clock: () => now);
  fillSample(store, now);
  return store;
}
