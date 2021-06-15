import 'dart:convert';
import 'dart:typed_data';

import 'candidate.dart';
import 'candidate_share.dart';
import 'polynomial.dart';
import 'services.dart';
import 'verifier.dart';

class Share {
  final String share_id;
  final String verifier_nid;
  final String ballot_id;
  String validation = "";
  final String commitment;
  final bool isComplaint;
  final List<CandidateShare> candidate_shares;

  Share._preCreate(
      {required this.share_id,
      required this.verifier_nid,
      required this.ballot_id,
      required this.validation,
      this.isComplaint = false,
      required this.commitment,
      required this.candidate_shares});

  static Future<Share> write(String ballot_id, Verifier verifier,
      Map<String, Polynomial> map_polynom) async {
    final share_id = getUniqueID();
    var candidate_shares = <CandidateShare>[];
    map_polynom.forEach((candidate_id, polynomial) {
      candidate_shares.add(CandidateShare.write(verifier.paillierPublicKey,
          candidate_id, polynomial.valueOf(verifier.shareNum), share_id));
    });

    var unhashed_commitment = '';
    for (final candidate_share in candidate_shares) {
      unhashed_commitment =
          '$unhashed_commitment${candidate_share.candidate_id}:${candidate_share.commitment},';
    }

    return Share._preCreate(
        share_id: share_id,
        verifier_nid: verifier.verifierNid,
        ballot_id: ballot_id,
        commitment: jsonEncode(
            sha256Digest(Uint8List.fromList(unhashed_commitment.codeUnits))),
        candidate_shares: candidate_shares,
        validation: jsonEncode(
            rsaSign(await getMyRSAPrivateKey(), Uint8List.fromList([0]))));
  }

  String computeCommitment() {
    var unhashed_commitment = '';
    for (final candidate_share in candidate_shares) {
      unhashed_commitment =
          '$unhashed_commitment${candidate_share.candidate_id}:${candidate_share.commitment},';
    }
    return jsonEncode(
        sha256Digest(Uint8List.fromList(unhashed_commitment.codeUnits)));
  }

  factory Share.fromJson(Map<String, dynamic> json,
      {bool isComplaint = false}) {
    var candidate_shares = <CandidateShare>[];
    for (final raw_candidate_share in json['candidate_shares']) {
      candidate_shares.add(CandidateShare.fromJson(raw_candidate_share));
    }
    return Share._preCreate(
        share_id: json['share_id'],
        verifier_nid: json['verifier_nid'],
        validation: json['validation'],
        commitment: json['commitment'],
        isComplaint: isComplaint,
        candidate_shares: candidate_shares,
        ballot_id: json['ballot_id']);
  }

  Map<String, dynamic> toJson() {
    var candidate_shares_json = <Map<String, dynamic>>[];

    for (final candidate_share in candidate_shares) {
      candidate_shares_json.add(candidate_share.toJson());
    }

    return {
      'commitment': commitment,
      'share_id': share_id,
      'verifier_nid': verifier_nid,
      'validation': validation,
      'candidate_shares': candidate_shares_json,
      'ballot_id': ballot_id
    };
  }

  Future<Share?> getComplaint() async {
    if (isComplaint) {
      return null;
    }
    var candidate_shares_complaints = <CandidateShare>[];
    for (final candidate_share in candidate_shares) {
      candidate_shares_complaints.add(await candidate_share.getComplaint());
    }
    return Share._preCreate(
        share_id: share_id,
        verifier_nid: verifier_nid,
        validation: validation,
        isComplaint: true,
        commitment: commitment,
        candidate_shares: candidate_shares_complaints,
        ballot_id: ballot_id);
  }

  Future<bool> isComplaintLegit(Share complaint) async {
    if (isComplaint) {
      return false;
    }
    if (!complaint.isComplaint) {
      return false;
    }
    if (verifier_nid != complaint.verifier_nid) {
      return false;
    }
    if (commitment != complaint.commitment) {
      return false;
    }
    if (candidate_shares.length != complaint.candidate_shares.length) {
      return false;
    }
    final verifier = await Verifier.getVerifier(verifier_nid);
    for (int i = 0; i < candidate_shares.length; i++) {
      if (!candidate_shares[i]
          .isComplaintLegit(complaint.candidate_shares[i], verifier!)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> isValid({String commitment_test = ''}) async {
    if (commitment != computeCommitment()) {
      return false;
    }
    if (isComplaint && commitment != commitment_test) {
      return false;
    }
    for (final candidate_share in candidate_shares) {
      if (!await candidate_share.isValid()) {
        return false;
      }
    }
    return true;
  }

  bool hasCorrectCandidates(List<Candidate> candidates) {
    if (candidates.length != candidate_shares.length) {
      return false;
    }
    bool isCandidateFound = false;
    for (final candidate_share in candidate_shares) {
      isCandidateFound = false;
      for (final candidate in candidates) {
        if (candidate.candidate_id == candidate_share.candidate_id) {
          isCandidateFound = true;
          break;
        }
      }
      if (!isCandidateFound) {
        return false;
      }
    }
    return true;
  }

  Future<bool> isValidationCorrect(String proposedValidation) async {
    final verifier = await Verifier.getVerifier(verifier_nid);
    var unsigned_validation = '';
    for (final candidate_share in candidate_shares) {
      unsigned_validation =
          '$unsigned_validation${candidate_share.candidate_id}:${candidate_share.commitment},';
    }
    return rsaVerify(
        verifier!.rsaPublicKey,
        Uint8List.fromList(unsigned_validation.codeUnits),
        Uint8List.fromList(List<int>.from(jsonDecode(proposedValidation))));
  }

  Future<void> setValidation(String proposedValidation) async {
    if (!await isValidationCorrect(proposedValidation)) {
      return;
    }
    validation = proposedValidation;
  }

  Future<bool> isValidated() async {
    final verifier = await Verifier.getVerifier(verifier_nid);
    var unsigned_validation = '';
    for (final candidate_share in candidate_shares) {
      unsigned_validation =
          '$unsigned_validation${candidate_share.candidate_id}:${candidate_share.commitment},';
    }
    return rsaVerify(
        verifier!.rsaPublicKey,
        Uint8List.fromList(unsigned_validation.codeUnits),
        Uint8List.fromList(List<int>.from(jsonDecode(validation))));
  }

  //Intended for the verifier of this share
  Future<String> validate() async {
    if (await isValid() && !isComplaint) {
      var unsigned_validation = '';
      for (final candidate_share in candidate_shares) {
        unsigned_validation =
            '$unsigned_validation${candidate_share.candidate_id}:${candidate_share.commitment},';
      }
      return jsonEncode(rsaSign(await getMyRSAPrivateKey(),
          Uint8List.fromList(unsigned_validation.codeUnits)));
    }
    return '';
  }

  static Future<Map<String, Share>> getSharesByBallot(String ballot_id) async {
    final db = getDB();

    var raw_shares =
        db.select('SELECT * FROM share WHERE ballot_id = "$ballot_id"');

    var map_shares = <String, Share>{};
    List<CandidateShare> candidate_shares_temp;

    for (final raw_share in raw_shares) {
      candidate_shares_temp =
          await CandidateShare.getCandidateSharesByShare(raw_share['share_id']);
      map_shares[raw_share['verifier_nid']] = Share._preCreate(
          share_id: raw_share['share_id'],
          verifier_nid: raw_share['verifier_nid'],
          validation: raw_share['validation'],
          commitment: raw_share['commitment'],
          candidate_shares: candidate_shares_temp,
          ballot_id: raw_share['ballot_id']);
    }

    return map_shares;
  }

  Future<BigInt> getAggregateDecryptedSecretShare() async {
    var result = BigInt.zero;
    for (final candidateShare in candidate_shares) {
      result += await candidateShare.getDecryptedSecretShare();
    }
    return result;
  }

  Future<BigInt> getAggregateSquaredDecryptedSecretShare() async {
    var result = BigInt.zero;
    for (final candidateShare in candidate_shares) {
      result += (await candidateShare.getDecryptedSecretShare()).pow(2);
    }
    return result;
  }

  Future<void> save() async {
    final db = getDB();
    for (var candidateShare in candidate_shares) {
      await candidateShare.save();
    }

    dbInsert(
        'share',
        {
          'share_id': share_id,
          'ballot_id': ballot_id,
          'verifier_nid': verifier_nid,
          'validation': validation,
          'commitment': commitment
        },
        db);
    /*db.insert(
      'share',
      {
        'share_id': share_id,
        'ballot_id': ballot_id,
        'verifier_nid': verifier_nid,
        'validation': validation,
        'commitment': commitment
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );*/
  }
}
