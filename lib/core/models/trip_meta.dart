import 'trip_driver.dart';
import 'trip_helper.dart';

class TripMeta {
  const TripMeta({
    required this.drivers,
    required this.helpers,
    required this.customers,
  });

  final List<TripDriver> drivers;
  final List<TripHelper> helpers;
  final List<String> customers;
}
