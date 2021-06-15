import 'dart:convert';
import 'dart:typed_data';

import 'ballot.dart';
import 'candidate.dart';
import 'election.dart';
import 'services.dart';
import 'verifier.dart';

class Block implements Comparable<Block> {
  final String block_id;
  String hash;
  String prev_hash;
  final String voter_nid;
  final DateTime timestamp;
  final String digital_signature;
  final Ballot? ballot;

  Block._preCreate(
      {required this.block_id,
      required this.hash,
      required this.prev_hash,
      required this.voter_nid,
      required this.timestamp,
      required this.digital_signature,
      required this.ballot});

  static Future<Block> write(Ballot ballot, String block_id,
      {String prev_hash = ''}) async {
    final voter_nid = await getLocalID();
    final timestamp = DateTime.now();
    final dataToSign = '$block_id$voter_nid$timestamp${jsonEncode(ballot)}';
    final digital_signature = /*String.fromCharCodes*/ jsonEncode(rsaSign(
        await getMyRSAPrivateKey(), Uint8List.fromList(dataToSign.codeUnits)));
    final dataToHash =
        '$block_id$voter_nid$prev_hash$timestamp${jsonEncode(ballot)}$digital_signature';
    final hash = /*String.fromCharCodes*/ jsonEncode(
        sha256Digest(Uint8List.fromList(dataToHash.codeUnits)));
    return Block._preCreate(
        block_id: block_id,
        hash: hash,
        prev_hash: prev_hash,
        voter_nid: voter_nid,
        timestamp: timestamp,
        digital_signature: digital_signature,
        ballot: ballot);
  }

  factory Block.getGenesis(Election election) {
    final block_id = election.election_id;
    final voter_nid = '';
    final prev_hash = '';
    final timestamp = election.voting_time;
    final digital_signature = '';
    final dataToHash =
        '$block_id$voter_nid$prev_hash$timestamp$digital_signature';
    final hash = /*String.fromCharCodes*/ jsonEncode(
        sha256Digest(Uint8List.fromList(dataToHash.codeUnits)));
    return Block._preCreate(
        block_id: block_id,
        hash: hash,
        prev_hash: prev_hash,
        voter_nid: voter_nid,
        timestamp: timestamp,
        digital_signature: digital_signature,
        ballot: null);
  }

  factory Block.fromJson(Map<String, dynamic> json) {
    return Block._preCreate(
        block_id: json['block_id'],
        hash: json['hash'],
        prev_hash: json['prev_hash'],
        voter_nid: json['voter_nid'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(json['timestamp'] as String) ?? 0),
        digital_signature: json['digital_signature'],
        ballot: Ballot.fromJson(json['ballot']));
  }

  Map<String, dynamic> toJson() {
    return {
      'block_id': block_id,
      'hash': hash,
      'prev_hash': prev_hash,
      'timestamp': '${timestamp.millisecondsSinceEpoch}',
      'voter_nid': voter_nid,
      'digital_signature': digital_signature,
      'ballot': ballot!.toJson()
    };
  }

  void display() {
    print("'block_id': $block_id,");
    print("'hash': $hash,");
    print("'prev_hash': $prev_hash,");
    print("'timestamp': $timestamp,");
    print("'voter_nid': $voter_nid,");
    print("'digital_signature': $digital_signature,");
    //print("'ballot_id': ${ballot!.ballot_id},");
  }

  String computeHash(String prev_hash) {
    this.prev_hash = prev_hash;
    final dataToHash =
        '$block_id$voter_nid$prev_hash$timestamp${jsonEncode(ballot!.toJson())}$digital_signature';
    final hash = /*String.fromCharCodes*/ jsonEncode(
        sha256Digest(Uint8List.fromList(dataToHash.codeUnits)));
    this.hash = hash;
    return this.hash;
  }

  void setPrevHash(String prev_hash) {
    this.prev_hash = prev_hash;
  }

  Future<bool> isUnapprovedValid(List<Candidate> candidates) async {
    if (!(await ballot!.isValid(candidates)) ||
        !(await ballot!.isValidated())) {
      return false;
    }

    final voter = await Verifier.getVerifier(voter_nid);

    final signedData =
        '$block_id$voter_nid$timestamp${jsonEncode(ballot!.toJson())}';
    return !rsaVerify(
        voter!.rsaPublicKey,
        Uint8List.fromList(signedData.codeUnits),
        Uint8List.fromList(digital_signature.codeUnits));
  }

  Future<bool> isValid(List<Candidate> candidates) async {
    if (!(await isUnapprovedValid(candidates))) {
      return false;
    }

    final hashedData =
        '$block_id$voter_nid$prev_hash$timestamp${jsonEncode(ballot!.toJson())}$digital_signature';
    if (hash !=
        /*String.fromCharCodes*/ jsonEncode(
            sha256Digest(Uint8List.fromList(hashedData.codeUnits)))) {
      return false;
    }

    return true;
  }

  static Future<List<Block>> getBlocksByElection(String election_id) async {
    final db = getDB();
    var raw_ballots = db.select(
        'SELECT * FROM block INNER JOIN ballot ON block.block_id = ballot.block_id WHERE ballot.election_id = "$election_id"');
    var blocks = <Block>[];
    for (final raw_ballot in raw_ballots) {
      blocks.add(Block._preCreate(
          block_id: raw_ballot['block_id'],
          hash: raw_ballot['hash'],
          prev_hash: raw_ballot['prev_hash'],
          voter_nid: raw_ballot['voter_nid'],
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              int.parse(raw_ballot['timestamp'])),
          digital_signature: raw_ballot['digital_signature'],
          ballot: await Ballot.getBallotByBlock(raw_ballot['block_id'])));
    }
    blocks.sort();
    return blocks;
  }

  static List<Block> getBlocksFromJson(
      List<Map<String, dynamic>> jsonBlockList) {
    var blocks = <Block>[];
    for (final jsonBlock in jsonBlockList) {
      blocks.add(Block.fromJson(jsonBlock));
    }
    blocks.sort();
    return blocks;
  }

  @override
  int compareTo(Block other) {
    if (timestamp.compareTo(other.timestamp) != 0) {
      return timestamp.compareTo(other.timestamp);
    } else {
      return digital_signature.compareTo(other.digital_signature);
    }
  }

  Future<void> save() async {
    final db = getDB();
    if (ballot != null) {
      await ballot!.save();
    }

    dbInsert(
        'block',
        {
          'block_id': block_id,
          'voter_nid': voter_nid,
          'hash': hash,
          'prev_hash': prev_hash,
          'digital_signature': digital_signature,
          'timestamp': '${timestamp.millisecondsSinceEpoch}'
        },
        db);

    /*db.insert(
      'block',
      {
        'block_id': block_id,
        'voter_nid': voter_nid,
        'hash': hash,
        'prev_hash': prev_hash,
        'digital_signature': digital_signature,
        'timestamp': '${timestamp.millisecondsSinceEpoch}'
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );*/
  }
}
