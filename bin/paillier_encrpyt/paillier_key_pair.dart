import '../services.dart';
import 'paillier_private_key.dart';
import 'paillier_public_key.dart';

class PaillierKeyPair {
  final PaillierPrivateKey privateKey;
  final PaillierPublicKey publicKey;

  PaillierKeyPair(this.privateKey, this.publicKey);

  static BigInt _calculateL(BigInt u, BigInt n) => (u - BigInt.one) ~/ (n);

  static PaillierKeyPair generate(int bits) {
    var p, q, n, nSquared, pMinusOne, qMinusOne;
    do {
      p = generateLargePrime(bits);
      q = generateLargePrime(bits);
      n = p * q;
      pMinusOne = p - BigInt.one;
      qMinusOne = q - BigInt.one;
    } while (n.gcd(pMinusOne * qMinusOne) != BigInt.one);

    nSquared = n * n;

    final lambda = /*bigintLcm(pMinusOne, qMinusOne)*/ pMinusOne * qMinusOne;
    var g, helper;
    /*do {
      g = randomBigInt(2 * bits);

      ///helper = _calculateL(g.modPow(lambda, nSquared), n);
    } while (g.gcd(nSquared) != BigInt.one || g >= nSquared);*/
    g = n + BigInt.one;
    final mu = (_calculateL(g.modPow(lambda, nSquared), n)).modInverse(n);
    return PaillierKeyPair(PaillierPrivateKey(mu, lambda, n, nSquared),
        PaillierPublicKey(g, n, bits, nSquared));
  }
}
