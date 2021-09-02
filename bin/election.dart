import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'ballot.dart';
import 'block.dart';
import 'blockchain.dart';
import 'candidate.dart';
import 'message.dart';
import 'peer.dart';
import 'polynomial.dart';
import 'services.dart';
import 'share.dart';
import 'verifier.dart';

class Election {
  final String election_id;
  final DateTime voting_time;
  final DateTime tallying_time;
  final String name;
  int hasVoted;
  List<Candidate> _candidate_list = <Candidate>[];
  Blockchain? _blockchain;
  Map<String, Ballot> unvalidatedBallots = <String, Ballot>{};
  List<Block> unapprovedBlocks = <Block>[];
  Map<String, List<String>> _mapLastHashListResponder =
      <String, List<String>>{}; // last_hash, list_of_approver
  Map<String, String> _mapResponderLastHash =
      Map<String, String>(); //approver_nid, last_hash
  Map<String, Verifier> mapVerifier = Map<String, Verifier>();
  Map<String, Map<BigInt, BigInt>> mapCandidateSubTallies =
      Map<String, Map<BigInt, BigInt>>();

  Ballot? myBallot; //In case i'm voting

  String mostApprovedHash = '';

  Election._create(
      {required this.election_id,
      required this.voting_time,
      required this.tallying_time,
      required this.name,
      this.hasVoted = 0});

  static Future<Election?> construct(String election_id, DateTime voting_time,
      DateTime tallying_time, String name, int hasVoted) async {
    if (voting_time.compareTo(tallying_time) >= 0) {
      return null;
    }
    var election = Election._create(
        election_id: election_id,
        voting_time: voting_time,
        tallying_time: tallying_time,
        name: name,
        hasVoted: hasVoted);
    await election._initCandidates();
    await election._initBlockchain();

    if (DateTime.now().compareTo(tallying_time) < 0) {
      Timer(tallying_time.difference(DateTime.now()), () {
        election.computeTally();
      });
    }
    if (DateTime.now().compareTo(voting_time) < 0) {
      Timer(voting_time.difference(DateTime.now()), () {
        Timer.periodic(Duration(minutes: 1), (Timer t) {
          election.approveBlocks(t);
        });
      });
    } else if (DateTime.now().compareTo(voting_time) >= 0 &&
        DateTime.now().compareTo(tallying_time) < 0) {
      var numMinSoFar = DateTime.now().difference(voting_time).inMinutes;
      var untilNextApproval =
          voting_time.add(Duration(minutes: numMinSoFar + 1));
      Timer(untilNextApproval.difference(DateTime.now()), () {
        Timer.periodic(Duration(minutes: 1), (Timer t) {
          election.approveBlocks(t);
        });
      });
    }
    /*else if (DateTime.now().compareTo(tallying_time) >= 0) {
      if (!election.isTallySet()) {
        await Message.broadcast(
            'Blockchain_Last_Hash_Request', {'election_id': election_id});
        await Future.delayed(const Duration(seconds: 15), () => "1");
        //sleep(Duration(seconds: 30));
        election._getMostApprovedHash();
        print('Most approved last hash: ${election.mostApprovedHash}');
        final mapLastHashListResponder =
            Map<String, List<String>>.from(election._mapLastHashListResponder);
        election._mapLastHashListResponder.clear();
        election._mapResponderLastHash.clear();
        /*if (mostCommonLastHash == '') {
          return null;
        }*/
        if (election._blockchain!.getLastBlock().hash !=
                election.mostApprovedHash &&
            mapLastHashListResponder.isNotEmpty) {
          Peer responder;
          var responders = List<String>.from(
              mapLastHashListResponder[election.mostApprovedHash] ??
                  <String>[]);
          for (final responderNid in responders) {
            responder = (await Peer.getPeer(responderNid))!;
            if (responder == null) {
              continue;
            }
            await election.makeBlockchainUpdateRequest(
                responder, election.mostApprovedHash);
          }
        }
        /*await*/ election.computeTally();
      }
    }*/

    return election;
  }

  Future<void> postConstructionTallying() async {
    if (DateTime.now().compareTo(tallying_time) >= 0) {
      if (!isTallySet()) {
        await Message.broadcast(
            'Blockchain_Last_Hash_Request', {'election_id': election_id});
        await Future.delayed(const Duration(seconds: 60), () => "1");
        //sleep(Duration(seconds: 30));
        _getMostApprovedHash();
        print('Most approved last hash: $mostApprovedHash');
        final mapLastHashListResponder =
            Map<String, List<String>>.from(_mapLastHashListResponder);
        if (_mapLastHashListResponder.isEmpty) {
          print('Nobody responded to Blockchain_Last_Hash_Request');
        } else {
          _mapResponderLastHash.forEach((key, value) {
            print('$key : $value');
          });
        }
        _mapLastHashListResponder.clear();
        _mapResponderLastHash.clear();
        /*if (mostCommonLastHash == '') {
          return null;
        }*/
        if (_blockchain!.getLastBlock().hash != mostApprovedHash &&
            mapLastHashListResponder.isNotEmpty) {
          Peer responder;
          var responders = List<String>.from(
              mapLastHashListResponder[mostApprovedHash] ?? <String>[]);
          for (final responderNid in responders) {
            responder = (await Peer.getPeer(responderNid))!;
            if (responder == null) {
              continue;
            }
            await makeBlockchainUpdateRequest(responder, mostApprovedHash);
          }
        }
        await computeTally();
      }
    }
  }

  static Future<Election?> fromJson(Map<String, dynamic> json,
      {bool toConstruct = true}) async {
    if (toConstruct) {
      return await Election.construct(
          json['election_id'],
          DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(json['voting_time']) ?? 0),
          DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(json['tallying_time']) ?? 0),
          json['name'] as String,
          json['has_voted'] as int);
    }
    return Election._create(
        election_id: json['election_id'],
        voting_time: DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(json['voting_time']) ?? 0),
        tallying_time: DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(json['tallying_time']) ?? 0),
        name: json['name']);
  }

  /*Map<String, dynamic> toJson() => {
    'election_id': election_id,
    'voting_time': voting_time.toString(),
    'tallying_time': tallying_time.toString(),
    'name': name
  };*/

  Future<void> handleBlockchainLastHashRequest(Message req) async {
    if (req.message_title != 'Blockchain_Last_Hash_Request') {
      return;
    }
    if (req.content['election_id'] != election_id) {
      return;
    }
    await makeBlockchainLastHashResponse(req);
  }

  Future<void> makeBlockchainLastHashResponse(Message req) async {
    final res = await Message.write(
        req.sender_nid, 'Blockchain_Last_Hash_Response', {
      'election_id': election_id,
      'last_hash': _blockchain!.getLastBlock().hash
    });
    final requester = await Peer.getPeer(req.sender_nid);
    try {
      var socket = await Socket.connect(
          requester!.ip_address, requester.responding_port);
      socket.write(jsonEncode(res.toJson()));
      await socket.close();
    } on SocketException {
      print(
          'Fail to connect to ${requester!.peer_nid} for Blockchain_Last_Hash_Response');
    }
  }

  void handleBlockchainLastHashResponse(Message res) {
    if (res.message_title != 'Blockchain_Last_Hash_Response') {
      return;
    }
    if (res.content['election_id'] != election_id) {
      return;
    }
    if (!_mapResponderLastHash.containsKey(res.sender_nid)) {
      if (_mapLastHashListResponder[res.content['last_hash']] == null) {
        _mapLastHashListResponder[res.content['last_hash']] = <String>[];
      }
      _mapLastHashListResponder[res.content['last_hash']]!.add(res.sender_nid);
      _mapResponderLastHash[res.sender_nid] = res.content['last_hash'];
    }
  }

  void handlePreapprovedBlocks(Message msg) {
    if (msg.message_title != 'Preapproved_Blocks') {
      return;
    }
    if (msg.content['election_id'] != election_id) {
      return;
    }
    if (!_mapResponderLastHash.containsKey(msg.sender_nid)) {
      if (_mapLastHashListResponder[msg.content['last_hash']] == null) {
        _mapLastHashListResponder[msg.content['last_hash']] = <String>[];
      }
      _mapLastHashListResponder[msg.content['last_hash']]!.add(msg.sender_nid);
      _mapResponderLastHash[msg.sender_nid] = msg.content['last_hash'];
    }
  }

  void approveBlocks(Timer t) async {
    if (DateTime.now().compareTo(tallying_time) >= 0) {
      t.cancel();
      return;
    }
    //this._mapBlocksListApprover.clear();
    //this._mapApprover.clear();
    var unapprovedBlocks = List<Block>.from(this.unapprovedBlocks);
    this.unapprovedBlocks.clear();
    unapprovedBlocks.sort();
    var prev_hash = _blockchain!.getLastBlock().hash;
    for (int i = 0; i < unapprovedBlocks.length; i++) {
      prev_hash = unapprovedBlocks[i].computeHash(prev_hash);
    }
    await Message.broadcast('Preapproved_Blocks',
        {'election_id': election_id, 'last_hash': prev_hash});
    await Future.delayed(const Duration(seconds: 15), () => "1");
    //sleep(Duration(seconds: 30));
    _getMostApprovedHash();
    final mapLastHashListResponder =
        Map<String, List<String>>.from(_mapLastHashListResponder);
    _mapLastHashListResponder.clear();
    _mapResponderLastHash.clear();
    if (mostApprovedHash == '') {
      return;
    }
    if (prev_hash == mostApprovedHash) {
      _blockchain!.addList(unapprovedBlocks, false);
    } else {
      Peer? approver;
      var responders = mapLastHashListResponder[mostApprovedHash] ?? <String>[];
      for (final approverNid in responders) {
        approver = await Peer.getPeer(approverNid);
        if (approver == null) {
          continue;
        }
        await makeBlockchainUpdateRequest(approver, mostApprovedHash);
      }
    }
  }

  Future<void> makeBlockchainUpdateRequest(
      Peer peer, String mostCommonLastHash) async {
    var req = await Message.write(peer.peer_nid, 'Blockchain_Update_Request', {
      'election_id': election_id,
      'last_hash': _blockchain!.getLastBlock().hash
    });

    try {
      var socket = await Socket.connect(peer.ip_address, peer.responding_port);
      socket.write(jsonEncode(req.toJson()));
      await socket.close();
    } on SocketException {
      print(
          'Fail to connect to ${peer.peer_nid} for Blockchain_Update_Request');
    }
  }

  Future<void> handleBlockchainUpdateRequest(Message msg) async {
    if (msg.message_title != 'Blockchain_Update_Request') {
      return;
    }
    if (msg.content['election_id'] != election_id) {
      return;
    }
    final lastHash = msg.content['last_hash'];
    if (lastHash == null) {
      return;
    }
    final jsonBlocks = _blockchain!.toJsonAsFrom(lastHash);
    await makeBlockchainUpdateResponse(msg.sender_nid, jsonBlocks);
  }

  Future<void> makeBlockchainUpdateResponse(
      String requesterNid, List<Map<String, dynamic>> blocks) async {
    var res = await Message.write(requesterNid, 'Blockchain_Update_Response',
        {'election_id': election_id, 'blocks': blocks});
    final requester = await Peer.getPeer(requesterNid);

    try {
      var socket = await Socket.connect(
          requester!.ip_address, requester.responding_port);
      socket.write(jsonEncode(res.toJson()));
      await socket.close();
    } on SocketException {
      print(
          'Fail to connect to ${requester!.peer_nid} for Blockchain_Update_Response');
    }
  }

  Future<void> handleBlockchainUpdateResponse(Message msg) async {
    if (msg.message_title != 'Blockchain_Update_Response') {
      return;
    }
    if (msg.content['election_id'] != election_id) {
      return;
    }

    final receivedBlocks = Block.getBlocksFromJson(
        List<Map<String, dynamic>>.from(msg.content['blocks']));
    if (receivedBlocks.isEmpty) {
      return;
    }
    if (receivedBlocks.last.hash != mostApprovedHash) {
      return;
    }
    if (!(await _blockchain!
        .isBlockListValid(receivedBlocks, _blockchain!.getLastBlock()))) {
      return;
    }
    await _blockchain!.addList(receivedBlocks, false);
  }

  String _getMostApprovedHash() {
    final mapBlocksListApprover =
        Map<String, List<String>>.from(_mapLastHashListResponder);
    //final mapApprover = this._mapResponderLastHash;
    //this._mapLastHashListResponder.clear();
    //this._mapResponderLastHash.clear();
    int numApprover = 0;
    mostApprovedHash = '';
    mapBlocksListApprover.forEach((hash, listApprover) {
      if (listApprover.length > numApprover) {
        numApprover = listApprover.length;
        mostApprovedHash = hash;
      }
    });
    return mostApprovedHash;
  }

  bool isTallySet() {
    for (final candidate in _candidate_list) {
      if (candidate.tally < 0) {
        return false;
      }
    }
    return true;
  }

  static Future<List<Election?>> elections({bool toConstruct = true}) async {
    final db = await getDB();

    var raw_election_list = db.select('SELECT * FROM election');

    var election_list = <Election?>[];

    for (final raw_election in raw_election_list) {
      election_list
          .add(await Election.fromJson(raw_election, toConstruct: toConstruct));
    }
    //await db.close();
    return election_list;
  }

  static Future<Election?> getElection(String election_id,
      {bool toConstrut = false}) async {
    final db = await getDB();
    var raw_election = db
        .select('SELECT * FROM election WHERE election_id = ?', [election_id]);
    final election_json = raw_election.elementAt(0);
    return await Election.fromJson(election_json, toConstruct: toConstrut);
  }

  Future<void> _initCandidates() async {
    _candidate_list = await Candidate.getCandidatesOfElection(election_id);
  }

  Future<void> _initBlockchain() async {
    _blockchain = await Blockchain.fromElection(this);
  }

  Future<bool> isBlockValid(Block block) async {
    return await _blockchain!.isBlockValid(block, _blockchain!.getLastBlock());
  }

  List<Candidate> getCandidates() => _candidate_list;

  Future<void> initVerifierMap() async {
    final blocks = _blockchain!.getBlocks();
    mapVerifier = await Verifier.mapAllVerifiers(candidates: _candidate_list);
    for (final block in blocks) {
      if (block.ballot == null) {
        continue;
      }
      block.ballot!.map_shares.forEach((verifierId, share) {
        for (final candidateShare in share.candidate_shares) {
          mapVerifier[verifierId]!.incEncryptedSubTally(
              candidateShare.candidate_id, candidateShare.secret_share);
        }
      });
    }
  }

  Future<void> computeMySubTally() async {
    final blocks = _blockchain!.getBlocks();
    final localNid = await getLocalID();
    final myPaillierPrivateKey = await getMyPaillierPrivateKey();
    for (var candidate in _candidate_list) {
      candidate.localSubTally = BigInt.zero;
    }
    for (final block in blocks) {
      if (block.ballot == null) {
        continue;
      }
      for (final candidateShare
          in block.ballot!.map_shares[localNid]!.candidate_shares) {
        for (var i = 0; i < _candidate_list.length; i++) {
          if (_candidate_list[i].candidate_id == candidateShare.candidate_id) {
            _candidate_list[i].localSubTally = (_candidate_list[i]
                        .localSubTally +
                    myPaillierPrivateKey.decrypt(candidateShare.secret_share)) %
                myPaillierPrivateKey.n;
            _candidate_list[i].test = (_candidate_list[i].test! *
                    (await getMyPaillierPublicKey()).encrypt(
                        myPaillierPrivateKey
                            .decrypt(candidateShare.secret_share))) %
                myPaillierPrivateKey.nSquared;
            break;
          }
        }
      }
    }
    /*for (final candidate in _candidate_list) {
      if ((await getMyPaillierPublicKey())
              .encrypt(candidate.localSubTally, rPow: blocks.length - 1) ==
          candidate.test) {
        print('HOMOMORPHIC WORKS!!!');
      } else {
        print('homomorphic DON\'T works');
      }
    }*/
  }

  Future<void> computeTally() async {
    await initVerifierMap();
    await computeMySubTally();
    final polynomDegree =
        (mapVerifier.length * pow(0.7, log(mapVerifier.length + 1))).toInt();
    final numTerms = polynomDegree + 1;
    final minimalNumOfPoint = numTerms /*+*/ - 1;
    var attempts = 0;
    while (!isTallySet() && attempts < 3) {
      await Message.broadcast('SubTally_Request', {'election_id': election_id});
      await Future.delayed(const Duration(seconds: 20), () => "1");
      //sleep(Duration(seconds: 5));
      for (var i = 0; i < _candidate_list.length; i++) {
        if (_candidate_list[i].tally < 0 &&
            mapCandidateSubTallies
                .containsKey(_candidate_list[i].candidate_id) &&
            mapCandidateSubTallies[_candidate_list[i].candidate_id]!.length >
                minimalNumOfPoint) {
          _candidate_list[i].tally = Polynomial.recoverSecret(
              mapCandidateSubTallies[_candidate_list[i].candidate_id]);
        }
      }
      attempts++;
    }
    await save();
  }

  Future<void> handleSubTallyRequest(Message req) async {
    if (req.message_title != 'SubTally_Request') {
      return;
    }
    if (req.content['election_id'] != election_id) {
      return;
    }
    await makeSubTallyResponse(req);
  }

  Future<void> makeSubTallyResponse(Message req) async {
    /*await initVerifierMap();
    await computeMySubTally();*/
    Map<String, String> mapCandidateSubTally = Map<String, String>();
    for (final candidate in _candidate_list) {
      mapCandidateSubTally[candidate.candidate_id] =
          candidate.localSubTally.toString();
    }
    final res = await Message.write(req.sender_nid, 'SubTally_Response', {
      'election_id': election_id,
      'map_candidate_subTally': mapCandidateSubTally
    });
    final requester = await Peer.getPeer(req.sender_nid);

    try {
      var socket = await Socket.connect(
          requester!.ip_address, requester.responding_port);
      socket.write(jsonEncode(res.toJson()));
    } on SocketException {
      print('Fail to connect to ${requester!.peer_nid} for SubTally_Response');
    }
  }

  void handleSubTallyResponse(Message res) {
    if (res.message_title != 'SubTally_Response') {
      return;
    }
    if (res.content['election_id'] != election_id) {
      return;
    }
    //try {
    var mapCandidateSubTally =
        Map<String, String>.from(res.content['map_candidate_subTally']);
    if (mapCandidateSubTally.length != _candidate_list.length) {
      return;
    }
    mapCandidateSubTally.forEach((candidateId, subTally) {
      var subTallyNum = BigInt.tryParse(subTally) ?? BigInt.zero;
      if (mapVerifier[res.sender_nid]!.isSubTallyCorrect(
          candidateId, subTallyNum, _blockchain!.getBlocks().length)) {
        if (mapCandidateSubTallies[candidateId] == null) {
          mapCandidateSubTallies[candidateId] = <BigInt, BigInt>{};
        }
        mapCandidateSubTallies[candidateId]![
            mapVerifier[res.sender_nid]!.shareNum] = subTallyNum;
      } else {
        print('Tallying segment from ${res.sender_nid} is NOT valid!!!');
      }
    });
    /*} catch (e) {
      print('Fail to handle SubTally response');
      print(e);
    }*/
  }

  Future<void> castVote(String chosenCandidateId) async {
    if (DateTime.now().compareTo(voting_time) < 0 ||
        DateTime.now().compareTo(tallying_time) > 0) {
      return;
    }
    if (hasVoted == 1) {
      return;
    }
    hasVoted = 2; //means vote being cast
    var isCandidatePresent = false;
    var mapCandidates = <String, Candidate>{};
    for (final candidate in _candidate_list) {
      mapCandidates[candidate.candidate_id] = candidate;
      if (candidate.candidate_id == chosenCandidateId) {
        isCandidatePresent = true;
      }
    }
    if (!isCandidatePresent) {
      hasVoted = 0;
      return;
    }
    final blockId = getUniqueID();
    myBallot = await Ballot.write(
        election_id, mapCandidates, chosenCandidateId, blockId);
    var ballotValidationAttempt = 0;
    while (!await myBallot!.isValidated()) {
      if (ballotValidationAttempt >= 5) {
        hasVoted = 0;
        return;
      }
      //print(myBallot!.toJson());
      await Message.broadcast('Ballot_Validation_Request',
          {'election_id': election_id, 'ballot': myBallot!.toJson()});
      await Future.delayed(const Duration(seconds: 30), () => "1");
      //sleep(Duration(seconds: 60));
      ballotValidationAttempt++;
    }
    var myBlock = await Block.write(myBallot!, blockId);
    var blockApprovalAttempt = 0;
    while (!_blockchain!.contains(myBlock)) {
      if (blockApprovalAttempt >= 4) {
        hasVoted = 0;
        return;
      }
      await Message.broadcast('Block_Approval_Request',
          {'block': myBlock.toJson(), 'election_id': election_id});
      await Future.delayed(const Duration(seconds: 30), () => "1");
      //sleep(Duration(seconds: 30));
      blockApprovalAttempt++;
    }
    hasVoted = 1;
    await save();
  }

  Future<void> handleBallotValidationRequest(Message req) async {
    if (req.message_title != 'Ballot_Validation_Request') {
      return;
    }
    if (req.content['election_id'] != election_id) {
      return;
    }
    var ballotToValidate = Ballot.fromJson(req.content['ballot']);
    if (unvalidatedBallots.containsKey(ballotToValidate.ballot_id)) {
      return;
    }
    //print('ballotToValidate: ${ballotToValidate.toJson()}');
    if (await ballotToValidate.isValid(_candidate_list)) {
      //print('ballotToValidate: is valid}');
      var validation = await ballotToValidate.validate();
      //print('validation: $validation}');
      if (validation != '') {
        unvalidatedBallots[ballotToValidate.ballot_id] = ballotToValidate;
        Timer(Duration(seconds: 30), () {
          makeBallotValidationResponse(req, validation);
        });
      } else {
        print(
            'Ballot with id: ${ballotToValidate.ballot_id} from ${req.sender_nid} contains INVALID share');
        await Message.broadcast('Ballot_Share_Complaint', {
          'election_id': election_id,
          'ballot_id': ballotToValidate.ballot_id,
          'share': (await ballotToValidate.map_shares[await getLocalID()]!
                  .getComplaint())!
              .toJson()
        });
      }
    } else {
      print(
          'Ballot with id: ${ballotToValidate.ballot_id} from ${req.sender_nid} is NOT valid!!!');
    }
  }

  Future<void> handleBallotShareComplaint(Message compl) async {
    if (compl.message_title != 'Ballot_Share_Complaint') {
      return;
    }
    if (compl.content['election_id'] != election_id) {
      return;
    }
    String complainingBallotId = compl.content['ballot_id'];
    if (!unvalidatedBallots.containsKey(complainingBallotId)) {
      return;
    }
    var complainingShare = Share.fromJson(compl.content['share']);
    if (!await unvalidatedBallots[complainingBallotId]!
        .map_shares[complainingShare.share_id]!
        .isComplaintLegit(complainingShare)) {
      return;
    }
    if (await complainingShare.isValid(
        commitment_test: unvalidatedBallots[complainingBallotId]!
            .map_shares[complainingShare.share_id]!
            .commitment)) {
      return;
    }
    unvalidatedBallots.remove(complainingBallotId);
  }

  Future<void> makeBallotValidationResponse(
      Message req, String validation) async {
    if (!unvalidatedBallots.containsKey(req.content['ballot']['ballot_id'])) {
      return;
    }
    var ballotToValidate = Ballot.fromJson(req.content['ballot']);
    var res =
        await Message.write(req.sender_nid, 'Ballot_Validation_Response', {
      'election_id': election_id,
      'ballot_id': ballotToValidate.ballot_id,
      'validation': validation
    });
    var requester = await Peer.getPeer(req.sender_nid);

    try {
      var socket = await Socket.connect(
          requester!.ip_address, requester.responding_port);
      socket.write(jsonEncode(res.toJson()));
    } on SocketException {
      print(
          'Fail to connect to ${requester!.peer_nid} for Ballot_Validation_Response');
    }
  }

  Future<void> handleBallotValidationResponse(Message res) async {
    if (res.message_title != 'Ballot_Validation_Response') {
      return;
    }
    if (res.content['election_id'] != election_id) {
      return;
    }
    if (res.content['ballot_id'] != myBallot!.ballot_id) {
      return;
    }
    await myBallot!.map_shares[res.sender_nid]!
        .setValidation(res.content['validation']);
  }

  Future<void> handleBlockApprovalRequest(Message req) async {
    if (req.message_title != 'Block_Approval_Request') {
      return;
    }
    if (req.content['election_id'] != election_id) {
      return;
    }
    var blockToApprove = Block.fromJson(req.content['block']);
    if (!await blockToApprove.isUnapprovedValid(_candidate_list)) {
      print(
          'Block with id: ${blockToApprove.block_id} from ${req.sender_nid} has an invalid digital signature');
      return;
    }
    for (final stagedBlock in unapprovedBlocks) {
      if (stagedBlock.block_id == blockToApprove.block_id) {
        return;
      }
    }
    unapprovedBlocks.add(blockToApprove);
  }

  Future<void> save() async {
    final db = await getDB();
    for (final candidate in _candidate_list) {
      await candidate.save(election_id);
    }
    if (_blockchain != null) {
      _blockchain!.save();
    }

    try {
      dbInsert(
          'election',
          {
            'election_id': election_id,
            'name': name,
            'voting_time': '${voting_time.millisecondsSinceEpoch}',
            'tallying_time': '${tallying_time.millisecondsSinceEpoch}',
            'has_voted': hasVoted
          },
          db);
    } on SqliteException {
      print('SqliteException');
    }
  }
}
