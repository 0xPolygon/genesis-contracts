pragma solidity 0.6.12;

import {RLPReader} from "./utils/RLPReader.sol";
import {System} from "./System.sol";
import {IStateReceiver} from "./IStateReceiver.sol";
import {IStateSyncGasOracle} from "./IStateSyncGasOracle.sol";

contract StateReceiver is System {
  using RLPReader for bytes;
  using RLPReader for RLPReader.RLPItem;

  uint256 public lastStateId;

  bytes32 public failedStateSyncsRoot;
  mapping(bytes32 => bool) public nullifier;

  // failed state syncs committed before failedStateSyncHashes existed
  mapping(uint256 => bytes) public failedStateSyncs;

  address public immutable rootSetter;
  uint256 public leafCount;
  uint256 public replayCount;
  uint256 public constant TREE_DEPTH = 16;

  // keccak256(abi.encode(receiver, stateData)) of each failed state sync
  mapping(uint256 => bytes32) public failedStateSyncHashes;

  address public immutable gasOracle;
  // receiver gas when the oracle has no code, reverts or returns malformed data
  uint256 public constant DEFAULT_RECEIVER_GAS = 160000;
  uint256 public constant MAX_RECEIVER_GAS = 5000000;
  uint256 public constant ORACLE_GAS = 50000;

  event StateCommitted(uint256 indexed stateId, bool success);
  event StateSyncReplay(uint256 indexed stateId);

  constructor(address _rootSetter, address _gasOracle) public {
    rootSetter = _rootSetter;
    gasOracle = _gasOracle;
  }

  function commitState(uint256 syncTime, bytes calldata recordBytes) external onlySystem returns (bool success) {
    // parse state data
    RLPReader.RLPItem[] memory dataList = recordBytes.toRlpItem().toList();
    uint256 stateId = dataList[0].toUint();
    require(lastStateId + 1 == stateId, "StateIds are not sequential");
    lastStateId++;
    address receiver = dataList[1].toAddress();
    bytes memory stateData = dataList[2].toBytes();
    // notify state receiver contract, in a non-revert manner
    if (isContract(receiver)) {
      uint256 txGas = receiverGas(stateId, receiver, stateData);

      bytes memory data = abi.encodeWithSignature("onStateReceive(uint256,bytes)", stateId, stateData);
      // solium-disable-next-line security/no-inline-assembly
      assembly {
        success := call(txGas, receiver, 0, add(data, 0x20), mload(data), 0, 0)
      }
      emit StateCommitted(stateId, success);
      // only the hash is stored, replayers supply the data (L1 StateSynced event / heimdall record)
      if (!success) failedStateSyncHashes[stateId] = keccak256(abi.encode(receiver, stateData));
    }
  }

  // gas forwarded to the receiver, as reported by the oracle and capped at MAX_RECEIVER_GAS
  // an oracle failure must never revert commitState, else state syncs halt
  function receiverGas(uint256 stateId, address receiver, bytes memory stateData) public view returns (uint256 gasLimit) {
    address oracle = gasOracle;
    if (!isContract(oracle)) return DEFAULT_RECEIVER_GAS;

    bytes memory data = abi.encodeWithSelector(IStateSyncGasOracle.getGasLimit.selector, stateId, receiver, stateData);
    uint256 oracleGas = ORACLE_GAS;
    bool success;
    uint256 size;
    // solium-disable-next-line security/no-inline-assembly
    assembly {
      success := staticcall(oracleGas, oracle, add(data, 0x20), mload(data), 0, 0x20)
      size := returndatasize()
      gasLimit := mload(0)
    }
    if (!success || size < 32) return DEFAULT_RECEIVER_GAS;
    if (gasLimit > MAX_RECEIVER_GAS) return MAX_RECEIVER_GAS;
  }

  function replayFailedStateSync(uint256 stateId) external {
    bytes memory stateSyncData = failedStateSyncs[stateId];
    require(stateSyncData.length != 0, "!found");
    delete failedStateSyncs[stateId];

    (address receiver, bytes memory stateData) = abi.decode(stateSyncData, (address, bytes));
    emit StateSyncReplay(stateId);
    IStateReceiver(receiver).onStateReceive(stateId, stateData); // revertable
  }

  function replayFailedStateSyncWithData(uint256 stateId, address receiver, bytes calldata stateData) external {
    bytes32 stateSyncHash = failedStateSyncHashes[stateId];
    require(stateSyncHash != bytes32(0), "!found");
    require(keccak256(abi.encode(receiver, stateData)) == stateSyncHash, "!data");
    delete failedStateSyncHashes[stateId];

    emit StateSyncReplay(stateId);
    IStateReceiver(receiver).onStateReceive(stateId, stateData); // revertable
  }

  function setRootAndLeafCount(bytes32 _root, uint256 _leafCount) external {
    require(msg.sender == rootSetter, "!rootSetter");
    require(failedStateSyncsRoot == bytes32(0), "!zero");
    failedStateSyncsRoot = _root;
    leafCount = _leafCount;
  }

  function replayHistoricFailedStateSync(
    bytes32[TREE_DEPTH] calldata proof,
    uint256 leafIndex,
    uint256 stateId,
    address receiver,
    bytes calldata data
  ) external {
    require(leafIndex < 2 ** TREE_DEPTH, "invalid leafIndex");
    require(++replayCount <= leafCount, "end");
    bytes32 root = failedStateSyncsRoot;
    require(root != bytes32(0), "!root");

    bytes32 leafHash = keccak256(abi.encode(stateId, receiver, data));
    bytes32 zeroHash = 0x28cf91ac064e179f8a42e4b7a20ba080187781da55fd4f3f18870b7a25bacb55; // keccak256(abi.encode(uint256(0), address(0), new bytes(0)));
    require(leafHash != zeroHash && !nullifier[leafHash], "used");
    nullifier[leafHash] = true;

    require(root == _getRoot(proof, leafIndex, leafHash), "!proof");

    emit StateSyncReplay(stateId);
    IStateReceiver(receiver).onStateReceive(stateId, data);
  }

  function _getRoot(bytes32[TREE_DEPTH] memory proof, uint256 index, bytes32 leafHash) private pure returns (bytes32) {
    bytes32 node = leafHash;

    for (uint256 height = 0; height < TREE_DEPTH; height++) {
      if (((index >> height) & 1) == 1) node = keccak256(abi.encodePacked(proof[height], node));
      else node = keccak256(abi.encodePacked(node, proof[height]));
    }

    return node;
  }

  // check if address is contract
  function isContract(address _addr) private view returns (bool) {
    uint32 size;
    // solium-disable-next-line security/no-inline-assembly
    assembly {
      size := extcodesize(_addr)
    }
    return (size > 0);
  }
}
