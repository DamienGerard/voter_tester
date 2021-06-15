class PaillierPrivateKey {
  final BigInt mu;
  final BigInt lambda;
  final BigInt n;
  final BigInt nSquared;

  PaillierPrivateKey(this.mu, this.lambda, this.n, this.nSquared);

  static BigInt _calculateL(BigInt u, BigInt n) => (u - BigInt.one) ~/ (n);

  BigInt decrypt(BigInt c) =>
      (_calculateL(c.modPow(lambda, nSquared), n) * mu) % n;
  //((((c.modPow(lambda, nSquared) - BigInt.one) ~/ n) % nSquared) * mu) % n;
}
