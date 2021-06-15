import 'paillier_encrpyt/paillier_key_pair.dart';

void main() {
  var num1 = BigInt.parse('56756754654650');
  var num2 = BigInt.parse('3675674656656867697865');
  var num3 = BigInt.parse('36756746566568676978653675674656656867697865');
  var num4 = BigInt.parse('876543234567890987654345678906789876546543489');
  var num5 = BigInt.parse('567536568967453234546786980986513535656807898');
  var num6 = BigInt.parse('345645786879656685674677696356688978984269564');

  final paillierKeyPair = PaillierKeyPair.generate(2048);
  final privateKey = paillierKeyPair.privateKey;
  final publicKey = paillierKeyPair.publicKey;
  final encryptNum1 = publicKey.encrypt(num1);
  final encryptNum2 = publicKey.encrypt(num2);
  final encryptNum3 = publicKey.encrypt(num3);
  final encryptNum4 = publicKey.encrypt(num4);
  final encryptNum5 = publicKey.encrypt(num5);
  final encryptNum6 = publicKey.encrypt(num6);
  /*print('num1 = $num1');
  print(' encrypted num1 = $encryptNum1');
  print('num2 = $num2');
  print(' encrypted num2 = $encryptNum2');*/
  final sum = (num1 + num2 + num3 + num4 + num5 + num6) % publicKey.n;
  if ((encryptNum1 *
              encryptNum2 *
              encryptNum3 *
              encryptNum4 *
              encryptNum5 *
              encryptNum6) %
          privateKey.nSquared ==
      publicKey.encrypt(sum, rPow: 6)) {
    print('Homomorphic Works');
  } else {
    print('shit T_T');
  }

  /*if (num1 == privateKey.decrypt(encryptNum1)) {
    print('make sense');
  }

  print('encrypted sum = ${publicKey.encrypt(sum1_2, rPow: 2)}');
  print(
      'product encrypted = ${(encryptNum1 * encryptNum2) % privateKey.nSquared}');
  print(
      'diff: ${(publicKey.encrypt(sum1_2, rPow: 2)) - ((encryptNum1 * encryptNum2) % privateKey.nSquared)}');*/
}
