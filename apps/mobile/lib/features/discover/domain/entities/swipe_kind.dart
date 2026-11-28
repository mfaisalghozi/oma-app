/// The three decisions the deck can send.
enum SwipeKind {
  pass('pass'),
  like('like'),
  superLike('super_like');

  const SwipeKind(this.wire);

  final String wire;

  bool get spendsLike => this == SwipeKind.like;
}
