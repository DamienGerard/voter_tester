import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:sqlite3/sqlite3.dart';
//import 'package:sqlite3/src/api/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'paillier_encrpyt/paillier_private_key.dart';
import 'paillier_encrpyt/paillier_public_key.dart';

const String urlEA = 'https://5b6fdcecf18a.ngrok.io';
String identifier = 'voter';
Database getDB() {
  //WidgetsFlutterBinding.ensureInitialized();
  var dbFile = File('voter_$identifier.db');

  if (!dbFile.existsSync()) {
    var sink = dbFile.openWrite();
    sink.write('');
    sink.close();
    final dbCreator = sqlite3.open('voter_$identifier.db');
    dbCreator.execute(
        'CREATE TABLE election(election_id TEXT PRIMARY KEY, name TEXT, voting_time TEXT, tallying_time TEXT, has_voted INTEGER);');
    dbCreator.execute(
        'CREATE TABLE peer(peer_nid TEXT PRIMARY KEY, ip_address TEXT, responding_port INTEGER);');
    dbCreator.execute(
        'CREATE TABLE registered_voter(voter_nid TEXT PRIMARY KEY, share_num INTEGER, public_key TEXT);');
    dbCreator.execute(
        'CREATE TABLE ballot(ballot_id TEXT PRIMARY KEY, aggregate_polynomial TEXT, sq_aggregate_polynomial TEXT, election_id TEXT, block_id TEXT);');
    dbCreator.execute(
        'CREATE TABLE block(block_id TEXT PRIMARY KEY, voter_nid TEXT, hash TEXT, prev_hash TEXT, digital_signature TEXT, timestamp TEXT);');
    dbCreator.execute(
        'CREATE TABLE share(share_id TEXT PRIMARY KEY, ballot_id TEXT, verifier_nid TEXT, validation TEXT, commitment TEXT);');
    dbCreator.execute(
        'CREATE TABLE candidate_share(share_id TEXT, candidate_id TEXT, encrypted_secret_share TEXT, encrypted_obfuscator TEXT, commitment TEXT, PRIMARY KEY(share_id, candidate_id));');
    dbCreator.execute(
        'CREATE TABLE candidate(candidate_id TEXT PRIMARY KEY, name TEXT, party TEXT);');
    dbCreator.execute(
        'CREATE TABLE election_candidate(election_id TEXT, candidate_id TEXT, tally INTEGER, local_subTally TEXT, PRIMARY KEY(election_id, candidate_id));');
    dbCreator.execute(
        'CREATE TABLE message_log(msg_log_id INTEGER PRIMARY KEY, timestamp TEXT, signature TEXT);');
    dbCreator.execute(
      'CREATE TRIGGER msg_log_trigger AFTER INSERT ON message_log BEGIN DELETE FROM message_log WHERE (CAST((strftime("%s","now") || substr(strftime("%f","now"),4)) AS INTEGER) - CAST(timestamp AS INTEGER)) > 300000 OR (CAST((strftime("%s","now") || substr(strftime("%f","now"),4)) AS INTEGER) - CAST(timestamp AS INTEGER)) < 0 ;END',
      //
    );
  }

  final db = sqlite3.open('voter_$identifier.db');

  return db;
}

void dbInsert(
    String tableName, Map<String, dynamic> columnValuesMap, Database db,
    {String handleConflict = 'OR REPLACE'}) {
  var values = <dynamic>[];

  var columnsStr = '';
  var valuesStr = '';

  columnValuesMap.forEach((column, value) {
    columnsStr = columnsStr + column + ',';
    valuesStr = valuesStr + '?,';
    values.add(value);
  });

  if (columnsStr.isNotEmpty) {
    columnsStr = columnsStr.substring(0, columnsStr.length - 1);
  }

  if (valuesStr.isNotEmpty) {
    valuesStr = valuesStr.substring(0, valuesStr.length - 1);
  }

  var stmt = db.prepare('INSERT ' +
      handleConflict +
      ' INTO ' +
      tableName +
      ' (' +
      columnsStr +
      ') VALUES (' +
      valuesStr +
      ')');
  stmt.execute(values);
}

String getUniqueID() {
  var uuid = Uuid();
  return uuid.v4();
}

Future<void> saveLocalID(String myID) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString('local_nid', myID);
}

class SharedPreferences {
  Map<String, dynamic> prefs;

  SharedPreferences._create(this.prefs);

  static Future<SharedPreferences> getInstance() async {
    var file = File('sharedPreferences_$identifier.json');
    var prefs = <String, dynamic>{};
    if (await file.exists()) {
      var prefsStr = await file.readAsString();
      if (!prefsStr.startsWith('{')) {
        prefsStr = '{}';
      }
      prefs = jsonDecode(prefsStr);
    }
    return SharedPreferences._create(prefs);
  }

  dynamic get(String key) {
    return prefs[key];
  }

  void setString(String key, String value) {
    prefs[key] = value;
    var file = File('sharedPreferences_$identifier.json');
    var sink = file.openWrite();
    sink.write(jsonEncode(prefs));
    sink.close();
  }
}

Future<String> getLocalID() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.get('local_nid') ?? '';
}

String generateRandomString(int len) {
  var r = Random();
  return String.fromCharCodes(
      List.generate(len, (index) => r.nextInt(33) + 89));
}

Future<void> saveMyRSAPrivateKey(RSAPrivateKey rsaPrivateKey) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString('modulus_RSA', rsaPrivateKey.modulus.toString());
  prefs.setString('privateExponent_RSA', rsaPrivateKey.exponent.toString());
  prefs.setString('q_RSA', rsaPrivateKey.q.toString());
  prefs.setString('p_RSA', rsaPrivateKey.p.toString());
}

Future<RSAPrivateKey> getMyRSAPrivateKey() async {
  final prefs = await SharedPreferences.getInstance();
  final modulus =
      BigInt.tryParse(prefs.get('modulus_RSA') as String) ?? BigInt.zero;
  final privateExponent =
      BigInt.tryParse(prefs.get('privateExponent_RSA') as String) ??
          BigInt.zero;
  final q = BigInt.tryParse(prefs.get('q_RSA') as String) ?? BigInt.zero;
  final p = BigInt.tryParse(prefs.get('p_RSA') as String) ?? BigInt.zero;
  return RSAPrivateKey(modulus, privateExponent, q, p);
}

Future<void> saveMyRSAPublicKey(RSAPublicKey rsaPublicKey) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString('modulus_RSA', rsaPublicKey.modulus.toString());
  prefs.setString('publicExponent_RSA', rsaPublicKey.exponent.toString());
}

Future<RSAPublicKey> getMyRSAPublicKey() async {
  final prefs = await SharedPreferences.getInstance();
  final modulus =
      BigInt.tryParse(prefs.get('modulus_RSA') as String) ?? BigInt.zero;
  final privateExponent =
      BigInt.tryParse(prefs.get('publicExponent_RSA') as String) ?? BigInt.zero;
  return RSAPublicKey(modulus, privateExponent);
}

Future<void> saveMyPaillierPrivateKey(
    PaillierPrivateKey paillierPrivateKey) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString('mu_Paillier', paillierPrivateKey.mu.toString());
  prefs.setString('lambda_Paillier', paillierPrivateKey.lambda.toString());
  prefs.setString('n_Paillier', paillierPrivateKey.n.toString());
  prefs.setString('nSquared_Paillier', paillierPrivateKey.nSquared.toString());
}

Future<PaillierPrivateKey> getMyPaillierPrivateKey() async {
  final prefs = await SharedPreferences.getInstance();
  final mu = BigInt.tryParse(prefs.get('mu_Paillier') as String) ?? BigInt.zero;
  final lambda =
      BigInt.tryParse(prefs.get('lambda_Paillier') as String) ?? BigInt.zero;
  final n = BigInt.tryParse(prefs.get('n_Paillier') as String) ?? BigInt.zero;
  final nSquared =
      BigInt.tryParse(prefs.get('nSquared_Paillier') as String) ?? BigInt.zero;
  return PaillierPrivateKey(mu, lambda, n, nSquared);
}

Future<void> saveMyPaillierPublicKey(
    PaillierPublicKey paillierPublicKey) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString('g_Paillier', paillierPublicKey.g.toString());
  prefs.setString('bits_Paillier', paillierPublicKey.bits.toString());
  prefs.setString('n_Paillier', paillierPublicKey.n.toString());
  prefs.setString('nSquared_Paillier', paillierPublicKey.nSquared.toString());
}

Future<PaillierPublicKey> getMyPaillierPublicKey() async {
  final prefs = await SharedPreferences.getInstance();
  final g = BigInt.tryParse(prefs.get('g_Paillier') as String) ?? BigInt.zero;
  final bits = int.tryParse(prefs.get('bits_Paillier') as String) ?? 0;
  final n = BigInt.tryParse(prefs.get('n_Paillier') as String) ?? BigInt.zero;
  final nSquared =
      BigInt.tryParse(prefs.get('nSquared_Paillier') as String) ?? BigInt.zero;
  return PaillierPublicKey(g, n, bits, nSquared);
}

Future<void> saveMyShareNum(BigInt shareNum) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString('share_num', shareNum.toString());
}

Future<BigInt> getMyShareNum() async {
  final prefs = await SharedPreferences.getInstance();
  return BigInt.tryParse(prefs.get('share_num') as String) ?? BigInt.zero;
}

Uint8List sha256Digest(Uint8List dataToDigest) {
  final d = SHA256Digest();
  return d.process(dataToDigest);
}

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateRSAkeyPair(
    {int bitLength = 2048}) {
  final _sGen = Random.secure();
  var secureRandom = SecureRandom('Fortuna');
  secureRandom.seed(KeyParameter(
      Uint8List.fromList(List.generate(32, (_) => _sGen.nextInt(255)))));
  // Create an RSA key generator and initialize it

  final keyGen = RSAKeyGenerator()
    ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(
            BigInt.parse('${generateProbablePrime(255, 55, secureRandom)}'),
            bitLength,
            64),
        secureRandom));

  // Use the generator

  final pair = keyGen.generateKeyPair();

  // Cast the generated key pair into the RSA key types

  final myPublic = pair.publicKey as RSAPublicKey;
  final myPrivate = pair.privateKey as RSAPrivateKey;

  return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(myPublic, myPrivate);
}

Uint8List rsaEncrypt(RSAPublicKey myPublic, Uint8List dataToEncrypt) {
  final encryptor = OAEPEncoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(myPublic)); // true=encrypt

  return _processInBlocks(encryptor, dataToEncrypt);
}

Uint8List rsaDecrypt(RSAPrivateKey myPrivate, Uint8List cipherText) {
  final decryptor = OAEPEncoding(RSAEngine())
    ..init(
        false, PrivateKeyParameter<RSAPrivateKey>(myPrivate)); // false=decrypt

  return _processInBlocks(decryptor, cipherText);
}

Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List input) {
  final numBlocks = input.length ~/ engine.inputBlockSize +
      ((input.length % engine.inputBlockSize != 0) ? 1 : 0);

  final output = Uint8List(numBlocks * engine.outputBlockSize);

  var inputOffset = 0;
  var outputOffset = 0;
  while (inputOffset < input.length) {
    final chunkSize = (inputOffset + engine.inputBlockSize <= input.length)
        ? engine.inputBlockSize
        : input.length - inputOffset;

    outputOffset += engine.processBlock(
        input, inputOffset, chunkSize, output, outputOffset);

    inputOffset += chunkSize;
  }

  return (output.length == outputOffset)
      ? output
      : output.sublist(0, outputOffset);
}

bool rsaVerify(
    RSAPublicKey publicKey, Uint8List signedData, Uint8List signature) {
  final sig = RSASignature(signature);

  final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');

  verifier.init(
      false, PublicKeyParameter<RSAPublicKey>(publicKey)); // false=verify

  try {
    return verifier.verifySignature(signedData, sig);
  } on ArgumentError {
    return false; // for Pointy Castle 1.0.2 when signature has been modified
  }
}

Uint8List rsaSign(RSAPrivateKey privateKey, Uint8List dataToSign) {
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201');

  signer.init(
      true, PrivateKeyParameter<RSAPrivateKey>(privateKey)); // true=sign

  final sig = signer.generateSignature(dataToSign);

  return sig.bytes;
}

/*Future<String> rsaSign(Uint8List dataToSign, RSAPrivateKey privateKey) async {
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201');

  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey)); // true=sign

  return String.fromCharCodes(signer.generateSignature(dataToSign).bytes);
}*/

bool isInteger(String s) {
  if (s == null) {
    return false;
  }
  return int.tryParse(s) != null;
}

BigInt generateLargePrime(int bits) {
  final _sGen = Random.secure();
  var ran = SecureRandom('Fortuna');
  ran.seed(KeyParameter(
      Uint8List.fromList(List.generate(32, (_) => _sGen.nextInt(255)))));
  return generateProbablePrime(bits, 55, ran);
}

/*BigInt bigintGcd(BigInt a, BigInt b){
  while (b != BigInt.from(0)) {
    var t = b;
    b = a % t;
    a = t;
  }
  return a;
}*/

BigInt bigintLcm(BigInt a, BigInt b) => (a * b) ~/ a.gcd(b);

/*BigInt decodeBigInt(List<int> bytes) {
  var negative = bytes.isNotEmpty && bytes[0] & 0x80 == 0x80;

  BigInt result;

  if (bytes.length == 1) {
    result = BigInt.from(bytes[0]);
  } else {
    result = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      var item = bytes[bytes.length - i - 1];
      result |= (BigInt.from(item) << (8 * i));
    }
  }
  return result != BigInt.zero
      ? negative
          ? result.toSigned(result.bitLength)
          : result
      : BigInt.zero;
}*/

BigInt randomBigInt(int bits) {
  /*int size = bits;
  final random = Random.secure();
  final builder = BytesBuilder();
  for (var i = 0; i < size; i=i+8) {
    builder.addByte(random.nextInt(255));
  }
  final bytes = builder.toBytes();
  var result = decodeBigInt(bytes);
  if(result < BigInt.zero){
    result = result*BigInt.from(-1);
  }
  return result;*/

  final _sGen = Random.secure();
  var n = BigInt.from(1);
  var ran = SecureRandom('Fortuna');
  ran.seed(KeyParameter(
      Uint8List.fromList(List.generate(32, (_) => _sGen.nextInt(255)))));
  n = ran.nextBigInteger(bits);
  return n;
}

List<Map<String, dynamic>> makeModifiableResults(ResultSet results) {
  // Generate modifiable
  return List<Map<String, dynamic>>.generate(results.length,
      (index) => Map<String, dynamic>.from(results.elementAt(index)),
      growable: true);
}

Future<int> getUnusedPort(String address) {
  return ServerSocket.bind(address, 0).then((socket) {
    var port = socket.port;
    socket.close();
    return port;
  });
}

//for test purpose only
/*Future<void> deleteAllRecord() async {
  final db = await getDB();
  await db.delete('election', where: null, whereArgs: null);
  await db.delete('registered_voter', where: null, whereArgs: null);
  await db.delete('ballot', where: null, whereArgs: null);
  await db.delete('block', where: null, whereArgs: null);
  await db.delete('share', where: null, whereArgs: null);
  await db.delete('candidate_share', where: null, whereArgs: null);
  await db.delete('candidate', where: null, whereArgs: null);
  await db.delete('election_candidate', where: null, whereArgs: null);
  await db.delete('peer', where: null, whereArgs: null);
  await db.delete('message_log', where: null, whereArgs: null);
}*/
