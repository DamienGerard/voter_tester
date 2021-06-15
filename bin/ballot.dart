import 'dart:convert';
import 'dart:math';

import 'candidate.dart';
import 'polynomial.dart';
import 'services.dart';
import 'share.dart';
import 'verifier.dart';

class Ballot {
  final String ballot_id;
  final Polynomial aggregate_polynomial;
  final Polynomial sq_aggregate_polynomial;
  final String election_id;
  final String block_id;
  final Map<String, Share> map_shares;

  Ballot._preCreate(
      this.ballot_id,
      this.aggregate_polynomial,
      this.sq_aggregate_polynomial,
      this.election_id,
      this.map_shares,
      this.block_id);

  static Future<Ballot> write(
      String election_id,
      Map<String, Candidate> map_candidates,
      String chosen_candidateId,
      String blockId) async {
    final ballot_id = getUniqueID();
    var map_polynom = <String, Polynomial>{};
    var polynomial_list = <Polynomial>[];
    var squared_polynomial_list = <Polynomial>[];
    Polynomial polynom_temp;
    final verifiers = await Verifier.mapAllVerifiers(candidates: []);
    map_candidates.forEach((candidate_id, candidate_obj) {
      var const_term = BigInt.zero;
      if (candidate_id == chosen_candidateId) {
        const_term = BigInt.one;
      } else {
        const_term = BigInt.zero;
      }
      final degree =
          (verifiers.length * pow(0.7, log(verifiers.length))).toInt() /*+1*/;
      polynom_temp = Polynomial.generate(degree, constant_term: const_term);
      map_polynom[candidate_id] = polynom_temp;
      polynomial_list.add(polynom_temp);
      squared_polynomial_list.add(polynom_temp.square());
    });

    var map_shares = <String, Share>{};

    var verifierIds = <String>[];
    verifiers.forEach((verifier_nid, verifier_obj) async {
      verifierIds.add(verifier_nid);
    });

    for (final verifierid in verifierIds) {
      map_shares[verifierid] =
          await Share.write(ballot_id, verifiers[verifierid]!, map_polynom);
    }

    return Ballot._preCreate(
        ballot_id,
        Polynomial.sum(polynomial_list),
        Polynomial.sum(squared_polynomial_list),
        election_id,
        map_shares,
        blockId);
  }

  factory Ballot.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map_share_json = json['shares'];
    var map_shares = <String, Share>{};
    map_share_json.forEach((verifierNid, rawShare) {
      map_shares[verifierNid] = Share.fromJson(rawShare);
    });
    return Ballot._preCreate(
        json['ballot_id'],
        Polynomial.fromListOfStringifiedTerms(
            List<String>.from(json['aggregate_polynomial'])),
        Polynomial.fromListOfStringifiedTerms(
            List<String>.from(json['sq_aggregate_polynomial'])),
        json['election_id'],
        map_shares,
        json['block_id']);
  }

  Map<String, dynamic> toJson() {
    var map_share_json = <String, dynamic>{};
    map_shares.forEach((verifiers_nid, share_obj) {
      map_share_json[verifiers_nid] = share_obj.toJson();
    });

    return {
      'ballot_id': ballot_id,
      'aggregate_polynomial': aggregate_polynomial.toListOfStringifiedTerms(),
      'sq_aggregate_polynomial':
          sq_aggregate_polynomial.toListOfStringifiedTerms(),
      'shares': map_share_json,
      'block_id': block_id,
      'election_id': election_id
    };
  }

  Future<bool> isShareValid(Share share) async {
    if (!await share.isValid()) {
      return false;
    }
    final shareVerifier = await Verifier.getVerifier(share.verifier_nid);
    if ((await share.getAggregateDecryptedSecretShare()) % Polynomial.n !=
        aggregate_polynomial.valueOf(shareVerifier!.shareNum)) {
      return false;
    }
    if ((await share.getAggregateSquaredDecryptedSecretShare()) %
            Polynomial.n !=
        sq_aggregate_polynomial.valueOf(shareVerifier.shareNum)) {
      return false;
    }
    return true;
  }

  Future<bool> isValid(List<Candidate> candidates) async {
    if (aggregate_polynomial.terms[0] != BigInt.one) {
      return false;
    }
    if (sq_aggregate_polynomial.terms[0] != BigInt.one) {
      return false;
    }
    final verifiers = await Verifier.listAllVerifiers();
    final numTerms =
        (verifiers.length * pow(0.7, log(verifiers.length))).toInt() + 1;
    if (aggregate_polynomial.terms.length > numTerms) {
      return false;
    }
    if (sq_aggregate_polynomial.terms.length > (2 * numTerms) + 1) {
      return false;
    }
    if (verifiers.length != map_shares.length) {
      return false;
    }
    for (final verifier in verifiers) {
      if (!map_shares.containsKey(verifier.verifierNid)) {
        return false;
      }
      if (!map_shares[verifier.verifierNid]!.hasCorrectCandidates(candidates)) {
        return false;
      }
    }
    return true;
  }

  Future<String> validate() async {
    final prefs = await SharedPreferences.getInstance();
    final local_nid = prefs.get('local_nid') as String;
    var myShare = map_shares[local_nid];
    if (!await isShareValid(myShare!)) {
      return '';
    }
    return await myShare.validate();
  }

  Future<bool> isValidated() async {
    final numVerifiers = (await Verifier.listAllVerifiers()).length;
    var numValidations = 0;
    var share_list = <Share>[];
    map_shares.forEach((verifiers_nid, share_obj) {
      share_list.add(share_obj);
    });
    for (final share in share_list) {
      if (await share.isValidated()) {
        numValidations++;
      }
    }
    final minValidation =
        (numVerifiers * pow(0.95, log(numVerifiers))).toInt() + 1;
    if (numValidations < minValidation) {
      return false;
    }
    return true;
  }

  static Future<Ballot> getBallotByBlock(String block_id) async {
    final db = getDB();

    var raw_ballot =
        db.select('SELECT * FROM ballot WHERE block_id = "$block_id"');

    final map_shares =
        await Share.getSharesByBallot(raw_ballot.elementAt(0)['ballot_id']);
    final aggregate_polynomial = Polynomial.fromListOfStringifiedTerms(
        List<String>.from(
            jsonDecode(raw_ballot.elementAt(0)['aggregate_polynomial'])
                .map((el) => el.toString())
                .toList()));
    final sq_aggregate_polynomial = Polynomial.fromListOfStringifiedTerms(
        List<String>.from(
            jsonDecode(raw_ballot.elementAt(0)['sq_aggregate_polynomial'])
                .map((el) => el.toString())
                .toList()));

    return Ballot._preCreate(
        raw_ballot.elementAt(0)['ballot_id'],
        aggregate_polynomial,
        sq_aggregate_polynomial,
        raw_ballot.elementAt(0)['election_id'],
        map_shares,
        raw_ballot.elementAt(0)['block_id']);
  }

  Future<void> save() async {
    final db = getDB();
    var verifierIds = <String>[];

    map_shares.forEach((verifierId, share) async {
      verifierIds.add(verifierId);
    });

    for (final verifierId in verifierIds) {
      await map_shares[verifierId]!.save();
    }

    /*map_shares.forEach((verifierId, share) async {
      await share.save();
    });*/

    dbInsert(
        'ballot',
        {
          'ballot_id': ballot_id,
          'election_id': election_id,
          'block_id': block_id,
          'aggregate_polynomial':
              aggregate_polynomial.toListOfStringifiedTerms().toString(),
          'sq_aggregate_polynomial':
              sq_aggregate_polynomial.toListOfStringifiedTerms().toString()
        },
        db);
  }
}
