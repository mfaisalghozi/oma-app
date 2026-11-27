enum DiscoverMode {
  swipe,
  describe;

  static DiscoverMode fromQuery(String? value) =>
      value == describe.name ? describe : swipe;

  String get query => name;
}
