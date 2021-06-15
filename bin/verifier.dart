import 'dart:convert';

import 'package:pointycastle/export.dart';
import 'package:sqlite3/sqlite3.dart';

import 'candidate.dart';
import 'paillier_encrpyt/paillier_public_key.dart';
import 'services.dart';

class Verifier {
  final String verifierNid;
  final BigInt shareNum;
  final RSAPublicKey rsaPublicKey;
  final PaillierPublicKey paillierPublicKey;
  Map<String, BigInt> mapCandidatesEncryptedSubTally = <String, BigInt>{};
  //Map<String, BigInt> mapCandidatesSubTally;

  Verifier(
      {required this.verifierNid,
      required this.shareNum,
      required this.rsaPublicKey,
      required this.paillierPublicKey});

  factory Verifier.fromJson(Map<String, dynamic> json) {
    return Verifier(
        verifierNid: json['voter_nid'],
        shareNum: BigInt.from(json['share_num']),
        rsaPublicKey: RSAPublicKey(
            BigInt.parse(json['public_key']['rsa']['modulus'] as String),
            BigInt.parse(json['public_key']['rsa']['exponent'] as String)),
        paillierPublicKey: PaillierPublicKey(
            BigInt.parse(json['public_key']['paillier']['g'] as String),
            BigInt.parse(json['public_key']['paillier']['n'] as String),
            json['public_key']['paillier']['bits'] as int,
            BigInt.parse(
                json['public_key']['paillier']['nSquared'] as String)));
  }

  static Future<Verifier?> getVerifier(String verifier_nid) async {
    final db = getDB();

    var rawVerifiers = db.select(
        'SELECT * FROM registered_voter WHERE public_key IS NOT NULL AND voter_nid = "$verifier_nid"');
    var rawModifiableVerifiers = makeModifiableResults(rawVerifiers);

    if (rawModifiableVerifiers.isEmpty) {
      return null;
    }

    var rawVerifier = rawModifiableVerifiers.elementAt(0);
    rawVerifier['public_key'] =
        jsonDecode(rawModifiableVerifiers.elementAt(0)['public_key']);
    return Verifier.fromJson(rawVerifier);
  }

  static Future<Map<String, Verifier>> mapAllVerifiers(
      {required List<Candidate> candidates}) async {
    final db = getDB();

    var rawVerifiers = db
        .select('SELECT * FROM registered_voter WHERE public_key IS NOT NULL');
    var rawVerifiersModifiable = makeModifiableResults(rawVerifiers);

    var mapVerifiers = <String, Verifier>{};

    for (var raw_verifier in rawVerifiersModifiable) {
      raw_verifier['public_key'] = jsonDecode(raw_verifier['public_key']);
      mapVerifiers[raw_verifier['voter_nid']] = Verifier.fromJson(raw_verifier);
      if (candidates != null) {
        mapVerifiers[raw_verifier['voter_nid']]!
            .initMapCandidatesEncryptedSubTally(candidates);
      }
    }

    return mapVerifiers;
  }

  static Future<List<Verifier>> listAllVerifiers() async {
    final db = await getDB();

    var rawVerifiers = db
        .select('SELECT * FROM registered_voter WHERE public_key IS NOT NULL');
    var rawVerifiersModifiable = makeModifiableResults(rawVerifiers);
    var listVerifiers = <Verifier>[];

    for (var raw_verifier in rawVerifiersModifiable) {
      raw_verifier['public_key'] = jsonDecode(raw_verifier['public_key']);
      listVerifiers.add(Verifier.fromJson(raw_verifier));
    }

    return listVerifiers;
  }

  void initMapCandidatesEncryptedSubTally(List<Candidate> candidates) {
    for (final candidate in candidates) {
      mapCandidatesEncryptedSubTally[candidate.candidate_id] = BigInt.one;
    }
  }

  void incEncryptedSubTally(String candidateId, BigInt encryptedShare) {
    mapCandidatesEncryptedSubTally[candidateId] =
        (mapCandidatesEncryptedSubTally[candidateId]! * encryptedShare) %
            paillierPublicKey.nSquared;
  }

  bool isSubTallyCorrect(
      String candidateId, BigInt subTally, int blockchainLength) {
    //print(
    //    'paillierPublicKey.encrypt($subTally) = ${paillierPublicKey.encrypt(subTally)}');
    //print(
    //    'mapCandidatesEncryptedSubTally[$candidateId] = ${mapCandidatesEncryptedSubTally[candidateId]}');
    if (paillierPublicKey.encrypt(subTally, rPow: blockchainLength - 1) ==
        mapCandidatesEncryptedSubTally[candidateId]) {
      //mapCandidatesSubTally[candidateId] = subTally;
      print('subtally from ${verifierNid} is CORRECT!!!');
      return true;
    }
    print('subtally from ${verifierNid} is incorrect!!!');
    return false;
  }

  Future<void> save() async {
    final db = await getDB();
    String publicKeyJson =
        """{"rsa": {"modulus": "${rsaPublicKey.modulus}", "exponent": "${rsaPublicKey.exponent}"}, "paillier": {"g": "${paillierPublicKey.g}", "n": "${paillierPublicKey.n}", "bits": ${paillierPublicKey.bits}, "nSquared":"${paillierPublicKey.nSquared}"}}""";

    dbInsert(
        'registered_voter',
        {
          'voter_nid': verifierNid,
          'share_num': shareNum.toString(),
          'public_key': publicKeyJson,
        },
        db);

    /*await db
        .insert(
          'registered_voter',
          {
            'voter_nid': verifierNid,
            'share_num': shareNum.toString(),
            'public_key': publicKeyJson,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        )
        .then((value) => print('saveVerifier'));*/
    //await db.close();
  }
}
