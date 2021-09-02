import 'block.dart';
import 'candidate.dart';
import 'election.dart';

class Blockchain {
  List<Block> _blocks;
  final String election_id;
  var _candidates = <Candidate>[];
  var _mapVoterBlock = <String, String>{};

  Blockchain._preCreate(this.election_id, this._blocks);

  static Future<Blockchain> fromElection(Election election) async {
    var blocks = <Block>[];
    blocks.add(Block.getGenesis(election));
    var blockchain = Blockchain._preCreate(election.election_id, blocks);
    blockchain._candidates = election.getCandidates();
    var blocksToAdd = await Block.getBlocksByElection(election.election_id);
    blocksToAdd.sort();
    await blockchain.addList(blocksToAdd, true);
    return blockchain;
  }

  Future<bool> isUnapprovedBlockValid(Block block) async {
    if (_mapVoterBlock.containsKey(block.voter_nid)) {
      return false;
    }
    if (!(await block.isUnapprovedValid(_candidates))) {
      return false;
    }
    return true;
  }

  Future<bool> isBlockValid(Block block, Block prev_block) async {
    if (!(await isUnapprovedBlockValid(block))) {
      return false;
    }
    if (block.prev_hash != prev_block.hash) {
      return false;
    }
    if (block.compareTo(prev_block) < 0) {
      return false;
    }
    if (!(await block.isValid(_candidates))) {
      return false;
    }
    return true;
  }

  Future<bool> isBlockListValid(List<Block> blocks, Block prev_block) async {
    for (final block in blocks) {
      if (!(await isBlockValid(block, prev_block))) {
        return false;
      }
      prev_block = block;
    }
    return true;
  }

  Future<void> add(Block block, bool isElectionConstruction) async {
    if (await isBlockValid(block, _blocks.last) &&
        !_mapVoterBlock.containsKey(block.voter_nid)) {
      _blocks.add(block);
      _mapVoterBlock[block.voter_nid] = block.block_id;
      if (block.ballot == null) {
        print('Ballot is NULL when saving');
      } else {
        print('Ballot is not NULL when saving');
        print('Ballot id: ${block.ballot!.ballot_id}');
      }
      print(
          'block ${block.block_id} from ${block.voter_nid} is added to the blockchain');
      if (!isElectionConstruction) {
        await save();
      }

      print(
          'block ${block.block_id} from ${block.voter_nid} is saved to the blockchain');
      //display();
    } else {
      //throw Exception('Invalid block');
      print(
          'block ${block.block_id} from ${block.voter_nid} is ALREADY added to the blockchain');
    }
  }

  Future<void> addList(
      List<Block> blockList, bool isElectionConstruction) async {
    for (final block in blockList) {
      try {
        await add(block, isElectionConstruction);
      } catch (e) {
        //continue;
        print('could not add the following block: ');
        block.display();
        return;
      }
    }
  }

  List<Map<String, dynamic>> toJsonAsFrom(String hash) {
    var jsonBlockList = <Map<String, dynamic>>[];
    var hashFound = false;
    for (final block in _blocks) {
      if (hashFound) {
        jsonBlockList.add(block.toJson());
      }
      if (hash == block.hash) {
        hashFound = true;
      }
    }
    return jsonBlockList;
  }

  Block getLastBlock() => _blocks.last;

  List<Block> getBlocks() => _blocks;

  bool contains(Block block) {
    for (final approvedBlock in _blocks) {
      if (approvedBlock.block_id == block.block_id &&
              approvedBlock.voter_nid == block.voter_nid
          /*&&
          approvedBlock.prev_hash == block.prev_hash &&
          approvedBlock.hash == block.hash &&
          approvedBlock.digital_signature == block.digital_signature*/
          ) {
        return true;
      }
    }
    return false;
  }

  Future<void> save() async {
    for (final block in _blocks) {
      if (block.ballot != null) {
        await block.save();
      }
    }
  }

  void display() {
    print('\n');
    for (final block in _blocks) {
      block.display();
      print('\n');
    }
  }
}
