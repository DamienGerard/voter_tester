import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'election.dart';
import 'peer.dart';
import 'message.dart';
import 'services.dart';
import 'verifier.dart';

class Node {
  Map<String, Election> mapElections = <String, Election>{};
  late ServerSocket responder;

  Node._create();

  static Future<Node> getNode(String address, int port) async {
    final node = Node._create();
    await node.initResponder(address, port);
    await node.sayHello(address, port);
    await node.initElections();

    return node;
  }

  Future<void> initElections() async {
    var electionList = await Election.elections();
    for (var election in electionList) {
      if (DateTime.now().compareTo(election!.tallying_time) >= 0) {
        if (!election.isTallySet()) {
          await election.postConstructionTallying();
        }
      }

      mapElections[election.election_id] = election;
    }
  }

  Future<void> initResponder(String address, int port) async {
    responder = await ServerSocket.bind(address, port);

    responder.listen((socket) {
      var msgSrt = '';
      socket.cast<List<int>>().transform(utf8.decoder).listen((data) {
        msgSrt = msgSrt + data;
        try {
          Map<String, dynamic> msgJsno = jsonDecode(msgSrt);
          handleConnection(msgJsno);
        } on Exception {
          print('Incomplete message received');
        }
      });
    });
  }

  void handleConnection(data) async {
    //print('messageReceived');
    Map<String, dynamic> requestJson = data;
    final msg = Message.fromJson(requestJson);
    //print(msg.message_title);
    if (!await msg.isValid()) {
      //print('msg invalid');
      print(
          'Message Received: ${msg.message_title} from ${msg.sender_nid} is NOT VALID');
      return;
    }
    //print('valid msg');
    print(
        'Message Received: ${msg.message_title} from ${msg.sender_nid} is VALID');
    //await msg.save();
    if (msg.message_title == 'Hello') {
      print('waaasssuupp!!!');
      await handleHello(msg);
    } else if (msg.message_title == 'Blockchain_Last_Hash_Request') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        await mapElections[msg.content['election_id']]!
            .handleBlockchainLastHashRequest(msg);
      }
    } else if (msg.message_title == 'Blockchain_Last_Hash_Response') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        mapElections[msg.content['election_id']]!
            .handleBlockchainLastHashResponse(msg);
      }
    } else if (msg.message_title == 'Preapproved_Blocks') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        mapElections[msg.content['election_id']]!.handlePreapprovedBlocks(msg);
      }
    } else if (msg.message_title == 'Blockchain_Update_Request') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        await mapElections[msg.content['election_id']]!
            .handleBlockchainUpdateRequest(msg);
      }
    } else if (msg.message_title == 'Blockchain_Update_Response') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        await mapElections[msg.content['election_id']]!
            .handleBlockchainUpdateResponse(msg);
      }
    } else if (msg.message_title == 'SubTally_Request') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        await mapElections[msg.content['election_id']]!
            .handleSubTallyRequest(msg);
      }
    } else if (msg.message_title == 'SubTally_Response') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        mapElections[msg.content['election_id']]!.handleSubTallyResponse(msg);
      }
    } else if (msg.message_title == 'Ballot_Validation_Request') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        await mapElections[msg.content['election_id']]!
            .handleBallotValidationRequest(msg);
      }
    } else if (msg.message_title == 'Block_Approval_Request') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        await mapElections[msg.content['election_id']]!
            .handleBlockApprovalRequest(msg);
      }
    } else if (msg.message_title == 'Ballot_Share_Complaint') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        await mapElections[msg.content['election_id']]!
            .handleBallotShareComplaint(msg);
      }
    } else if (msg.message_title == 'Ballot_Validation_Response') {
      if (mapElections.containsKey(msg.content['election_id'])) {
        await mapElections[msg.content['election_id']]!
            .handleBallotValidationResponse(msg);
      }
    } else if (msg.message_title == 'Bye') {
      await handleBye(msg);
    }
    //},
    //onDone: () => print('Socket is done!!!'),
    //);
  }

  Future<void> sayHello(String address, int port) async {
    final myLocalID = await getLocalID();
    final myRSAPublicKey = await getMyRSAPublicKey();
    final myPaillierPublicKey = await getMyPaillierPublicKey();
    final shareNum = await getMyShareNum();
    var me = Peer(
        peer_nid: myLocalID,
        rsa_public_key: myRSAPublicKey,
        paillier_public_key: myPaillierPublicKey,
        ip_address: address,
        responding_port: port);
    var meVerif = Verifier(
        paillierPublicKey: myPaillierPublicKey,
        rsaPublicKey: myRSAPublicKey,
        shareNum: shareNum,
        verifierNid: myLocalID);
    //print('sayHello');
    await meVerif.save();
    //print('sayHello1');
    await me.save();
    //print('sayHello2');
    await Message.broadcast('Hello', {'me': me.toJson()});
    //print('sayHello3');
  }

  Future<void> handleHello(Message msg) async {
    print(msg.sender_nid);
    var newPeer = Peer.fromJson(msg.content['me']);
    //print(newPeer.toJson());
    var assocVerifier = await Verifier.getVerifier(msg.sender_nid);
    if (msg.sender_nid != newPeer.peer_nid) {
      return;
    }
    if (newPeer.paillier_public_key.g != assocVerifier!.paillierPublicKey.g) {
      return;
    }
    if (newPeer.paillier_public_key.n != assocVerifier.paillierPublicKey.n) {
      return;
    }
    if (newPeer.paillier_public_key.nSquared !=
        assocVerifier.paillierPublicKey.nSquared) {
      return;
    }
    if (newPeer.rsa_public_key.n != assocVerifier.rsaPublicKey.n) {
      return;
    }
    if (newPeer.rsa_public_key.exponent !=
        assocVerifier.rsaPublicKey.exponent) {
      return;
    }
    await newPeer.save();
    print('hello msg successfully handled!!!');
  }

  Future<void> sayBye() async {
    mapElections.forEach((election_id, election) async {
      await election.save();
    });
    await Message.broadcast('Bye', {'peer_id': await getLocalID()});
  }

  Future<void> handleBye(Message msg) async {
    if (msg.sender_nid != msg.content['peer_id']) {
      return;
    }
    await Peer.delete(msg.content['peerId']);
  }
}
