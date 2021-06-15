import 'services.dart';

class Polynomial {
  late List<BigInt> terms;
  static BigInt n = BigInt.parse('2305843009213693951');
  int? _degree;

  Polynomial(this.terms) {
    _degree = terms.length - 1;
    if (_degree! < 0) {
      _degree = 0;
    }
  }

  factory Polynomial.generate(int degree, {required BigInt constant_term}) {
    List<BigInt> terms = <BigInt>[];
    if (constant_term != null) {
      terms.add(constant_term);
    } else {
      terms.add(randomBigInt(8));
    }
    for (var i = 0; i < degree; i++) {
      terms.add(randomBigInt(8));
    }
    return Polynomial(terms);
  }

  factory Polynomial.fromListOfStringifiedTerms(List<String> termsStr) {
    List<BigInt> terms = <BigInt>[];
    for (final termStr in termsStr) {
      terms.add(BigInt.parse(termStr));
    }
    return Polynomial(terms);
  }

  List<String> toListOfStringifiedTerms() {
    List<String> termsStr = <String>[];
    for (final term in terms) {
      termsStr.add(term.toString());
    }
    return termsStr;
  }

  static Polynomial sum(List<Polynomial> polynoms) {
    int highestNumTerms = 0;
    for (final polynom in polynoms) {
      if (polynom.terms.length > highestNumTerms) {
        highestNumTerms = polynom.terms.length;
      }
    }
    var terms = <BigInt>[];
    for (var i = 0; i < highestNumTerms; i++) {
      terms.add(BigInt.zero);
      for (final polynom in polynoms) {
        if (i < polynom.terms.length) {
          terms[i] = (terms[i] + polynom.terms[i]) % n;
        }
      }
    }
    return Polynomial(terms);
  }

  Polynomial square() {
    var terms = List<BigInt>.filled((2 * _degree!) + 1, BigInt.zero);
    for (var i = 0; i < this.terms.length; i++) {
      for (var j = 0; j < this.terms.length; j++) {
        terms[i + j] += (this.terms[i] * this.terms[j]) % n;
      }
    }
    return Polynomial(terms);
  }

  BigInt valueOf(BigInt x) {
    var result = BigInt.zero;
    for (var i = 0; i < terms.length; i++) {
      result = (result + (terms[i] * x.modPow(BigInt.from(i), n)) % n) % n;
    }
    return result;
  }

  static int recoverSecret(Map<BigInt, BigInt>? mapCandidateSubTallies) {
    //final BigInt n = BigInt.parse('2305843009213693951');
    double result = 0;
    mapCandidateSubTallies!.forEach((xn, yn) {
      print('$xn, $yn');
      BigInt numerator = BigInt.one;
      BigInt denominator = BigInt.one;
      numerator = yn % n;
      mapCandidateSubTallies.forEach((xi, yi) {
        if (xi != xn) {
          numerator *= xi;
          denominator *= (xi - xn);
        }
      });
      result = (result + (numerator / denominator));
      result = double.parse(result.toStringAsFixed(2));
      //print('term: ${((numerator)/denominator)}');
      //print('result: $result');
    });
    return (BigInt.from(result.round()) % n).toInt();
  }
}
