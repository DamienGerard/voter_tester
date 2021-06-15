import 'dart:convert';

import 'package:pointycastle/export.dart';
import 'package:sqlite3/sqlite3.dart';
//import 'package:sqflite/sqflite.dart';

import 'paillier_encrpyt/paillier_public_key.dart';
import 'services.dart';

class Peer {
  final String peer_nid;
  final RSAPublicKey rsa_public_key;
  final PaillierPublicKey paillier_public_key;
  final String ip_address;
  final int responding_port;

  Peer(
      {required this.peer_nid,
      required this.rsa_public_key,
      required this.paillier_public_key,
      required this.ip_address,
      required this.responding_port});

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
        peer_nid: json['peer_nid'] as String,
        rsa_public_key: RSAPublicKey(
            BigInt.parse(json['public_key']['rsa']['modulus'] as String),
            BigInt.parse(json['public_key']['rsa']['exponent'] as String)),
        paillier_public_key: PaillierPublicKey(
            BigInt.parse(json['public_key']['paillier']['g'] as String),
            BigInt.parse(json['public_key']['paillier']['n'] as String),
            json['public_key']['paillier']['bits'] as int,
            BigInt.parse(json['public_key']['paillier']['nSquared'] as String)),
        ip_address: json['ip_address'] as String,
        responding_port: json['responding_port'] as int);
  }

  Map<String, dynamic> toJson() => {
        'peer_nid': peer_nid,
        'public_key': {
          'rsa': {
            'modulus': rsa_public_key.modulus.toString(),
            'exponent': rsa_public_key.exponent.toString()
          },
          'paillier': {
            'g': paillier_public_key.g.toString(),
            'n': paillier_public_key.n.toString(),
            'bits': paillier_public_key.bits,
            'nSquared': paillier_public_key.nSquared.toString()
          }
        },
        'ip_address': ip_address,
        'responding_port': responding_port
      };

  static Future<Peer?> getPeer(peer_nid) async {
    final db = getDB();
    var rawPeers = db.select(
        'SELECT * FROM peer INNER JOIN registered_voter ON peer.peer_nid=registered_voter.voter_nid WHERE peer_nid = "$peer_nid"');

    var rawPeersPodifiable = makeModifiableResults(rawPeers);
    if (rawPeersPodifiable.isEmpty) {
      return null;
    }
    var raw_peer = rawPeersPodifiable.elementAt(0);
    raw_peer['public_key'] = jsonDecode(raw_peer['public_key']);

    return Peer.fromJson(raw_peer);
  }

  Future<void> save() async {
    final db = getDB();
    dbInsert(
        'peer',
        {
          'peer_nid': peer_nid,
          'ip_address': ip_address,
          'responding_port': responding_port
        },
        db);
    /*await db
        .insert(
          'peer',
          {
            'peer_nid': peer_nid,
            'ip_address': ip_address,
            'responding_port': responding_port
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        )
        .then((value) => print('savePeer'));*/
    //await db.close();
  }

  static Future<void> delete(String peerId) async {
    final db = getDB();
    db.execute('DELETE FROM peer Where peer_nid = "' + peerId + '";');
    /*(
      'peer',
      where: "peer_nid = ?",
      whereArgs: [peerId],
    );*/
  }

  static Future<List<Peer>> peers() async {
    final db = getDB();

    var raw_peer_list = db.select(
        'SELECT * FROM peer INNER JOIN registered_voter ON peer.peer_nid=registered_voter.voter_nid');
    //await db.close();
    var raw_peer_modifiable_list = makeModifiableResults(raw_peer_list);
    var peer_list = <Peer>[];
    for (var raw_peer in raw_peer_modifiable_list) {
      raw_peer['public_key'] = jsonDecode(raw_peer['public_key']);
      peer_list.add(Peer.fromJson(raw_peer));
    }
    return peer_list;
  }
}
