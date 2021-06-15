import 'dart:convert';
import 'dart:typed_data';

import 'paillier_encrpyt/paillier_private_key.dart';
import 'paillier_encrpyt/paillier_public_key.dart';
import 'services.dart';
import 'verifier.dart';

class CandidateShare {
  final String share_id;
  final String candidate_id;
  final BigInt secret_share;
  BigInt? _secret_share;
  final BigInt obfuscator;
  BigInt? _obfuscator;
  final String commitment;
  final bool
      isComplaint; // if isComplaint is false secret_share and obfuscator is encrypted

  CandidateShare(
      {required this.share_id,
      required this.candidate_id,
      required this.secret_share,
      required this.obfuscator,
      required this.commitment,
      this.isComplaint = false});

  factory CandidateShare.write(PaillierPublicKey verifier_paillier_pk,
      String candidate_id, BigInt unencrypted_secret_share, String share_id) {
    //final share_id = getUniqueID();

    final encrypted_secret_share =
        verifier_paillier_pk.encrypt(unencrypted_secret_share);
    final BigInt unencrypted_obfuscator = randomBigInt(512);
    final encrypted_obfuscator =
        verifier_paillier_pk.encrypt(unencrypted_obfuscator);
    String unHashed_commitment =
        unencrypted_secret_share.toString() + unencrypted_obfuscator.toString();
    List<int> str = unHashed_commitment.codeUnits;
    print("str.runtimeType: ${str.runtimeType}");
    final commitment = jsonEncode(
        sha256Digest(Uint8List.fromList(unHashed_commitment.codeUnits)));

    var candidate_share = CandidateShare(
        share_id: share_id,
        candidate_id: candidate_id,
        secret_share: encrypted_secret_share,
        obfuscator: encrypted_obfuscator,
        commitment: commitment);

    candidate_share._secret_share = unencrypted_secret_share;
    candidate_share._obfuscator = unencrypted_obfuscator;

    return candidate_share;
  }

  factory CandidateShare.fromJson(Map<String, dynamic> json,
      {bool isComplaint = false}) {
    return CandidateShare(
        share_id: json['share_id'],
        candidate_id: json['candidate_id'],
        secret_share:
            BigInt.tryParse(json['encrypted_secret_share']) ?? BigInt.zero,
        obfuscator:
            BigInt.tryParse(json['encrypted_obfuscator']) ?? BigInt.zero,
        commitment: json['commitment'],
        isComplaint: isComplaint);
  }

  static Future<List<CandidateShare>> getCandidateSharesByShare(
      String share_id) async {
    final db = getDB();

    var raw_candidateShares =
        db.select('SELECT * FROM candidate_share WHERE share_id = "$share_id"');

    var candidateShares = <CandidateShare>[];

    for (final raw_candidateShare in raw_candidateShares) {
      candidateShares.add(CandidateShare.fromJson(raw_candidateShare));
    }

    return candidateShares;
  }

  Map<String, dynamic> toJson() => {
        'share_id': share_id,
        'candidate_id': candidate_id,
        'encrypted_secret_share': secret_share.toString(),
        'encrypted_obfuscator': obfuscator.toString(),
        'commitment': commitment
      };

  //To be used by the verifier of the share
  Future<bool> isValid() async {
    BigInt decrypted_secret_share, decrypted_obfuscator;

    if (!isComplaint) {
      final private_key = await getMyPaillierPrivateKey();
      decrypted_secret_share = private_key.decrypt(secret_share);
      decrypted_obfuscator = private_key.decrypt(obfuscator);
    } else {
      decrypted_secret_share = secret_share;
      decrypted_obfuscator = obfuscator;
    }

    final unHashed_commitment = '$decrypted_secret_share$decrypted_obfuscator';
    final computedHash = jsonEncode(
        sha256Digest(Uint8List.fromList(unHashed_commitment.codeUnits)));

    return computedHash == commitment;
  }

  Future<CandidateShare> getComplaint() async {
    /*if (isComplaint) {
      return null;
    }*/
    BigInt secret_share, obfuscator;
    if (_secret_share != null) {
      secret_share = _secret_share!;
      obfuscator = _obfuscator!;
    } else {
      var myPaillierPrivatekey = await getMyPaillierPrivateKey();
      secret_share = myPaillierPrivatekey.decrypt(this.secret_share);
      obfuscator = myPaillierPrivatekey.decrypt(this.obfuscator);
    }
    return CandidateShare(
        share_id: share_id,
        candidate_id: candidate_id,
        secret_share: secret_share,
        obfuscator: obfuscator,
        commitment: commitment,
        isComplaint: true);
  }

  bool isComplaintLegit(CandidateShare complaint, Verifier verifier) {
    if (isComplaint) {
      return false;
    }
    if (!complaint.isComplaint) {
      return false;
    }
    if (commitment != complaint.commitment) {
      return false;
    }
    if (secret_share !=
        verifier.paillierPublicKey.encrypt(complaint.secret_share)) {
      return false;
    }
    if (obfuscator !=
        verifier.paillierPublicKey.encrypt(complaint.obfuscator)) {
      return false;
    }
    return true;
  }

  //Intended for the verifier
  Future<BigInt> getDecryptedSecretShare() async {
    if (!isComplaint) {
      final private_key = await getMyPaillierPrivateKey();
      return private_key.decrypt(secret_share);
    } else {
      return secret_share;
    }
  }

  Future<void> save() async {
    final db = getDB();

    dbInsert(
        'candidate_share',
        {
          'share_id': share_id,
          'candidate_id': candidate_id,
          'encrypted_secret_share': secret_share.toString(),
          'encrypted_obfuscator': obfuscator.toString(),
          'commitment': commitment
        },
        db);
  }
}
