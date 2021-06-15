import 'package:sqlite3/sqlite3.dart';

import 'services.dart';

class Candidate {
  final String candidate_id;
  final String name;
  final String party;
  int tally;
  BigInt localSubTally;
  BigInt? test = BigInt.one;

  Candidate(
      {required this.candidate_id,
      required this.name,
      required this.party,
      required this.tally,
      required this.localSubTally});

  static Future<List<Candidate>> getCandidatesOfElection(
      String election_id) async {
    final db = await getDB();

    var raw_candidate_list = db.select(
        'SELECT candidate.candidate_id, name, party, tally, local_subTally FROM candidate INNER JOIN election_candidate ON candidate.candidate_id = election_candidate.candidate_id WHERE election_candidate.election_id = "$election_id"');

    var candidate_list = <Candidate>[];

    for (final raw_candidate in raw_candidate_list) {
      candidate_list.add(Candidate(
          candidate_id: raw_candidate['candidate_id'],
          name: raw_candidate['name'],
          party: raw_candidate['party'],
          tally: raw_candidate['tally'],
          localSubTally:
              BigInt.tryParse(raw_candidate['local_subTally'] ?? '0') ??
                  BigInt.zero));
    }

    return candidate_list;
  }

  factory Candidate.fromJson(Map<String, dynamic> json) {
    return Candidate(
        candidate_id: json['candidate_id'],
        name: json['candidate_name'],
        party: json['candidate_party'],
        tally: json['tally'] ?? -2,
        localSubTally: json['local_subTally'] ?? BigInt.from(0));
  }

  Future<void> save(String election_id) async {
    final db = getDB();
    dbInsert('candidate',
        {'candidate_id': candidate_id, 'name': name, 'party': party}, db);
    /*await db.insert(
      'candidate',
      {'candidate_id': candidate_id, 'name': name, 'party': party},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );*/

    /*if (tally! >= 0) {
      handleConflict = 'OR REPLACE';
    } else {
      handleConflict = 'OR ABORT';
    }*/

    var raw_candidate_list = db.select(
        'SELECT * FROM election_candidate WHERE election_id = "$election_id" AND candidate_id = "$candidate_id"');
    if (raw_candidate_list.isEmpty ||
        raw_candidate_list.elementAt(0)['tally'] < 0) {
      dbInsert(
        'election_candidate',
        {
          'election_id': election_id,
          'candidate_id': candidate_id,
          'tally': tally,
          'local_subTally': localSubTally.toString()
        },
        db,
      );
    }

    /*await db.insert(
      'election_candidate',
      {
        'election_id': election_id,
        'candidate_id': candidate_id,
        'tally': tally,
        'local_subTally': localSubTally.toString()
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );*/
  }
}
