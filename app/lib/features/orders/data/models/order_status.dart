enum OrderStatus {
  placed('placed'),
  accepted('accepted'),
  preparing('preparing'),
  ready('ready'),
  pickedUp('picked_up'),
  delivered('delivered'),
  cancelled('cancelled');

  const OrderStatus(this.wire);

  /// The value the API uses for this status.
  final String wire;

  static OrderStatus fromWire(String wire) => values.firstWhere((status) => status.wire == wire);
}
