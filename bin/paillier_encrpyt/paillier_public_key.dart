import '../services.dart';

class PaillierPublicKey {
  final BigInt g;
  final BigInt n;
  final int bits;
  final BigInt nSquared;

  PaillierPublicKey(this.g, this.n, this.bits, this.nSquared);

  BigInt encrypt(BigInt m, {int rPow = 1}) {
    BigInt r;
    /*do {
      r = randomBigInt(bits);
    } while (r >= n || r < BigInt.zero || r.gcd(n)!=BigInt.one);*/

    r = (n - BigInt.one).modPow(BigInt.from(rPow), nSquared);

    var result = g.modPow(m, nSquared);
    var x = r.modPow(n, nSquared);

    result = (result * x) % nSquared;

    return result;
  }
}
