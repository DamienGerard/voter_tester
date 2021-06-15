import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;

import 'Node.dart';
import 'candidate.dart';
import 'election.dart';
import 'paillier_encrpyt/paillier_key_pair.dart';
import 'peer.dart';
import 'services.dart';
import 'verifier.dart';

/*void main() {
  runApp(MyApp());
}*/
const List<String> defArgs = ['jim', 'jim'];
Future<void> main(
    /*{List<String> arguments = defArgs}*/ List<String> arguments) async {
  if (arguments.isEmpty) {
    arguments = defArgs;
  }
  exitCode = 0; // presume success
  final parser = ArgParser();
  final argResults = parser.parse(arguments);
  identifier = argResults.rest[0];
  var username = /*'jim'*/ argResults.rest[0];
  var password = /*'jim'*/ argResults.rest[1];
  var basicAuth = 'Basic ' + base64Encode(utf8.encode('$username:$password'));

  //log(face_pic_uri);
  var headers = {'Authorization': basicAuth};
  var request =
      http.MultipartRequest('POST', Uri.parse('$urlEA/voter_test_login'));

  request.headers.addAll(headers);

  var ipAddress = '127.0.0.1';
  var respondingPort = await getUnusedPort(ipAddress);

  request.fields.addAll(
      {'ip_address': ipAddress, 'responding_port': respondingPort.toString()});

  print('Local Id: ${await getLocalID()}');
  print('username: ${username}');
  if (username != await getLocalID()) {
    print('saving');
    await saveLocalID(username);
    var rsaKeyPair = generateRSAkeyPair(bitLength: 2048);
    await saveMyRSAPrivateKey(rsaKeyPair.privateKey);
    await saveMyRSAPublicKey(rsaKeyPair.publicKey); /**/
    var paillierKeyPair = PaillierKeyPair.generate(2048);
    await saveMyPaillierPrivateKey(paillierKeyPair.privateKey);
    await saveMyPaillierPublicKey(paillierKeyPair.publicKey);
    var public_key_str = jsonEncode({
      'rsa': {
        'modulus': rsaKeyPair.publicKey.modulus.toString(),
        'exponent': rsaKeyPair.publicKey.exponent.toString()
      },
      'paillier': {
        'g': paillierKeyPair.publicKey.g.toString(),
        'n': paillierKeyPair.publicKey.n.toString(),
        'bits': paillierKeyPair.publicKey.bits,
        'nSquared': paillierKeyPair.publicKey.nSquared.toString()
      }
    });
    request.fields.addAll({
      'public_key': public_key_str,
    });
  }
  //print(request.fields);
  var response = await request.send();

  if (response.statusCode == 200) {
    var resStr = await response.stream.bytesToString();
    //print(resStr);
    Map<String, dynamic> resJson = jsonDecode(resStr);
    await saveMyShareNum(BigInt.from(resJson['yourShareNum']));
    var candidatesJson =
        List<Map<String, dynamic>>.from(resJson['candidatesJson']);
    Candidate candidateTemp;
    for (final candidateJson in candidatesJson) {
      candidateTemp = Candidate.fromJson(candidateJson);
      await candidateTemp.save(candidateJson['election_id']);
    }
    var electionsJson =
        List<Map<String, dynamic>>.from(resJson['electionsJson']);
    Election electionTemp;
    for (final electionJson in electionsJson) {
      electionTemp =
          (await Election.fromJson(electionJson, toConstruct: false))!;
      await electionTemp.save();
    }
    var peersJson = List<Map<String, dynamic>>.from(resJson['peersJson']);
    Peer peerTemp;
    for (var peerJson in peersJson) {
      peerJson['public_key'] = jsonDecode(peerJson['public_key']);
      peerTemp = Peer.fromJson(peerJson);
      await peerTemp.save();
    }
    var verifiersJson =
        List<Map<String, dynamic>>.from(resJson['verifiersJson']);
    Verifier verifierTemp;
    for (var verifierJson in verifiersJson) {
      verifierJson['public_key'] = jsonDecode(verifierJson['public_key']);
      verifierTemp = Verifier.fromJson(verifierJson);
      await verifierTemp.save();
    }

    var node = await Node.getNode(ipAddress, respondingPort);

    /*var futureElections = <String, Election>{};
    var ongoingElections = <String, Election>{};
    var pastElections = <String, Election>{};



    node.mapElections.forEach((electionId, electionObj) {
      if (DateTime.now().compareTo(electionObj.voting_time) < 0) {
        futureElections[electionId] = electionObj;
      } else if (DateTime.now().compareTo(electionObj.voting_time) >= 0 &&
          DateTime.now().compareTo(electionObj.tallying_time) < 0) {
        ongoingElections[electionId] = electionObj;
      } else if (DateTime.now().compareTo(electionObj.tallying_time) >= 0) {
        pastElections[electionId] = electionObj;
      }
    }); */

    var mainToIsolateStream = await initMenuIsolate(node, node.mapElections);
    //print('2. ${mainToIsolateStream}');
    //print('Before send mainToIsolateStream');
    mainToIsolateStream.send({'elections': node.mapElections});
    //print('After send mainToIsolateStream');
  } else {
    print(response.reasonPhrase ?? 'FAIL');
  }

  print("ending");
}

Future<SendPort> initMenuIsolate(
    Node node, Map<String, Election> elections) async {
  // ignore: omit_local_variable_types
  Completer<SendPort> completer = Completer<SendPort>();
  var isolateToMainStream = ReceivePort();

  // ignore: unused_local_variable
  var myIsolateInstance =
      await Isolate.spawn(myIsolate, isolateToMainStream.sendPort);
  var mainToIsolateStream = ReceivePort().sendPort;
  isolateToMainStream.listen((data) {
    if (data is SendPort) {
      mainToIsolateStream = data;
      completer.complete(mainToIsolateStream);
      //print('Cooooooooooooommmmmmmmmmppppllllleeeeeeetttttttteeeeeeeeeeddddd');
    } else if (data is String && data == 'reload') {
      mainToIsolateStream.send({'elections': node.mapElections});
    } else {
      //print('[isolateToMainStream] $data');
      node.mapElections[data['election_id']]!.castVote(data['candidate_id']);
    }
  });

  return completer.future as Future<SendPort>;
}

Future<void> myIsolate(SendPort isolateToMainStream) async {
  var elections = <String, Election>{};
  var futureElections = <String, Election>{};
  var ongoingElections = <String, Election>{};
  var pastElections = <String, Election>{};

  var mainToIsolateStream = ReceivePort();
  //print('1. ${mainToIsolateStream}');
  isolateToMainStream.send(mainToIsolateStream.sendPort);

  mainToIsolateStream.listen((electionsJson) {
    //print('Listen to mainToIsolateStream');
    //print(elections);
    elections = electionsJson['elections'];
    //futureElections = elections['futureElections'];
    //ongoingElections = elections['ongoingElections'];
    //pastElections = elections['pastElections'];
    //exit(0);
  });

  await Future.delayed(const Duration(seconds: 1));

  isolateToMainStream.send({'election_id': '260958086', 'candidate_id': '14'});

  //isolateToMainStream.send('This is from myIsolate()');
  Election? electionToDisplay;
  var input;
  while (input != '-1') {
    isolateToMainStream.send('reload');
    futureElections.clear();
    ongoingElections.clear();
    pastElections.clear();
    elections.forEach((electionId, electionObj) {
      if (DateTime.now().compareTo(electionObj.voting_time) < 0) {
        futureElections[electionId] = electionObj;
      } else if (DateTime.now().compareTo(electionObj.voting_time) >= 0 &&
          DateTime.now().compareTo(electionObj.tallying_time) < 0) {
        ongoingElections[electionId] = electionObj;
      } else if (DateTime.now().compareTo(electionObj.tallying_time) >= 0) {
        pastElections[electionId] = electionObj;
      }
    });
    //
    print('\n\nFUTURE ELECTIONS');
    futureElections.forEach((election_id, election) {
      print(
          '${election.election_id}\t${election.name}\t${election.voting_time} - ${election.tallying_time}');
    });
    print('ONGOING ELECTIONS');
    ongoingElections.forEach((election_id, election) {
      print(
          '${election.election_id}\t${election.name}\t${election.voting_time} - ${election.tallying_time}');
    });

    print('PAST ELECTIONS');
    pastElections.forEach((election_id, election) {
      print(
          '${election.election_id}\t${election.name}\t${election.voting_time} - ${election.tallying_time}');
    });
    print(
        '\n\nEnter the election id you want to proceed with(or -1 to stop): ');

    input = stdin.readLineSync();

    if (ongoingElections.containsKey(input)) {
      electionToDisplay = ongoingElections[input];
      print(
          '${electionToDisplay!.election_id}\t${electionToDisplay.name}\t${electionToDisplay.voting_time} - ${electionToDisplay.tallying_time}');
      print('CANDIDATES\n');
      var candidatesHeaders = 'Candidate id\tCandidate name\tCandidate party';

      print(candidatesHeaders);
      var candidates = electionToDisplay.getCandidates();
      var candidateStr;
      for (final candidate in candidates) {
        candidateStr =
            '${candidate.candidate_id}\t${candidate.name}\t${candidate.party}';

        print(candidateStr);
      }
      print('Enter the id of a candidate to vote for them(or -1 to go back): ');
      input = stdin.readLineSync();
      if (input != '-1') {
        isolateToMainStream.send({
          'election_id': electionToDisplay.election_id,
          'candidate_id': input
        });
      }
    } else if (futureElections.containsKey(input) ||
        pastElections.containsKey(input)) {
      if (futureElections.containsKey(input)) {
        electionToDisplay = futureElections[input];
      } else {
        electionToDisplay = pastElections[input];
      }

      print(
          '${electionToDisplay!.election_id}\t${electionToDisplay.name}\t${electionToDisplay.voting_time} - ${electionToDisplay.tallying_time}');
      print('CANDIDATES\n');
      var candidatesHeaders = 'Candidate id\tCandidate name\tCandidate party';
      if (pastElections.containsKey(electionToDisplay.election_id)) {
        candidatesHeaders += '\tVotes';
      }
      print(candidatesHeaders);
      var candidates = electionToDisplay.getCandidates();
      var candidateStr;
      for (final candidate in candidates) {
        candidateStr =
            '${candidate.candidate_id}\t${candidate.name}\t${candidate.party}';
        if (pastElections.containsKey(electionToDisplay.election_id)) {
          candidateStr += '\t${candidate.tally}';
        }
        print(candidateStr);
      }
      print('Enter anything to go back: ');
      input = stdin.readLineSync();
    }
  }
}
