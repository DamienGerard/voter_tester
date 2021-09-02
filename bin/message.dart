import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'peer.dart';
import 'services.dart';
import 'verifier.dart';

class Message {
  final String sender_nid;
  final String receiver_nid;
  final DateTime timestamp;
  final String message_title;
  final Map<String, dynamic> content;
  String digital_signature;

  Message(
      {required this.sender_nid,
      required this.receiver_nid,
      required this.timestamp,
      required this.message_title,
      required this.content,
      this.digital_signature = ''});

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
        sender_nid: json['sender_nid'] as String,
        receiver_nid: json['receiver_nid'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(json['timestamp'] as String) ?? 0),
        message_title: json['message_title'] as String,
        content: jsonDecode(json['content']),
        digital_signature: json['digital_signature'] as String);
  }

  Map<String, dynamic> toJson() => {
        'sender_nid': sender_nid,
        'receiver_nid': receiver_nid,
        'timestamp': '${timestamp.millisecondsSinceEpoch}',
        'message_title': message_title,
        'content': json.encode(content),
        'digital_signature': digital_signature
      };

  static Future<Message> write(String msg_receiver_nid,
      String msg_message_title, Map<String, dynamic> msg_content) async {
    final local_nid = await getLocalID();
    final msg_timestamp = DateTime.now();
    var dataToSign =
        '$local_nid,$msg_receiver_nid,${msg_timestamp.millisecondsSinceEpoch},$msg_message_title,${jsonEncode(msg_content)}';
    //String dataToSign = 'qwerty';
    final msg_signature = jsonEncode(rsaSign(
        await getMyRSAPrivateKey(), Uint8List.fromList(dataToSign.codeUnits)));
    //print('rsaSign: ${rsaSign(await getMyRSAPrivateKey(), Uint8List.fromList(dataToSign.codeUnits))}');
    //print('msg_signature: $msg_signature');
    return Message(
        sender_nid: local_nid,
        receiver_nid: msg_receiver_nid,
        timestamp: msg_timestamp,
        message_title: msg_message_title,
        content: msg_content,
        digital_signature: msg_signature);
  }

  Future<bool> isAuthenticated() async {
    var verifier = await Verifier.getVerifier(sender_nid);
    //print('in authentication, peer.toJson: ${peer.toJson()}');
    //print('peer.peer_nid: ${peer.peer_nid}');
    var dataToVerify =
        '$sender_nid,$receiver_nid,${timestamp.millisecondsSinceEpoch},$message_title,${jsonEncode(content)}';

    //print('digital_signature: $digital_signature');
    //print('List<int>.from(jsonDecode(digital_signature)): ${List<int>.from(jsonDecode(digital_signature))}');
    //String dataToVerify = 'qwerty';
    return rsaVerify(
        verifier!.rsaPublicKey,
        Uint8List.fromList(dataToVerify.codeUnits),
        Uint8List.fromList(List<int>.from(jsonDecode(digital_signature))));
  }

  Future<bool> isValid() async {
    final db = getDB();
    final sinceCreation = DateTime.now().difference(timestamp).inSeconds;
    if (sinceCreation > 300 /*|| sinceCreation < 0*/) {
      return false;
    }
    var duplicate_msg = db.select(
        'SELECT * FROM message_log WHERE signature = "$digital_signature"');
    //await db.close();
    //print('duplicate_msg.length: ${duplicate_msg.length}');
    if (duplicate_msg.rows.isNotEmpty) {
      return false;
    }

    if (!await isAuthenticated()) {
      return false;
    }

    //await save();

    return true;
  }

  static Future<void> broadcast(
      String msg_message_title, Map<String, dynamic> msg_content) async {
    final peers = await Peer.peers();
    for (final peer in peers) {
      var msg =
          await Message.write(peer.peer_nid, msg_message_title, msg_content);
      try {
        var socket =
            await Socket.connect(peer.ip_address, peer.responding_port);

        //print(jsonEncode(msg.toJson()));
        socket.write(jsonEncode(msg.toJson()));
        //sleep(Duration(seconds: 1));
        //print('messageSent');
        //socket.close();
      } on SocketException {
        continue;
      }
    }
  }

  Future<void> save() async {
    final db = getDB();
    var rand = Random();
    /*await db.insert(
      'message_log',
      {
        'msg_log_id': rand.nextInt(500000),
        'timestamp': '${timestamp.millisecondsSinceEpoch}',
        'signature': digital_signature
      },
    );*/
    dbInsert(
        'message_log',
        {
          'msg_log_id': rand.nextInt(500000),
          'timestamp': '${timestamp.millisecondsSinceEpoch}',
          'signature': digital_signature
        },
        db);
    print('message saved');
  }
}
