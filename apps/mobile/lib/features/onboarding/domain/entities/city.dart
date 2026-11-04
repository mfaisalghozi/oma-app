/// M10 fallback when location is off. City centres are client-side for now:
/// the BE doc has no cities endpoint. Move to master data when it does.
class City {
  const City(this.name, this.latitude, this.longitude);

  final String name;
  final double latitude;
  final double longitude;
}

const fallbackCities = [
  City('Jakarta Selatan', -6.26, 106.81),
  City('Bandung', -6.92, 107.62),
  City('Surabaya', -7.26, 112.75),
  City('Yogyakarta', -7.80, 110.37),
  City('Medan', 3.60, 98.67),
  City('Denpasar', -8.67, 115.21),
];
