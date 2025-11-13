pragma solidity 0.8.26;

import "../lib/forge-std/src/Test.sol";

import "./helpers/IStateReceiver.sol";
import {TestReenterer} from "test/helpers/TestReenterer.sol";
import {TestRevertingReceiver} from "test/helpers/TestRevertingReceiver.sol";

contract StateReceiverTest is Test {
  address public constant SYSTEM_ADDRESS = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
  uint8 constant LIST_SHORT_START = 0xc0;

  IStateReceiver internal stateReceiver = IStateReceiver(0x0000000000000000000000000000000000001001);
  address internal rootSetter = makeAddr("rootSetter");

  TestReenterer internal reenterer = new TestReenterer();
  TestRevertingReceiver internal revertingReceiver = new TestRevertingReceiver();

  function setUp() public {
    address tmp = deployCode("out/StateReceiver.sol/StateReceiver.json", abi.encode(rootSetter));
    vm.etch(address(stateReceiver), tmp.code);
    vm.label(address(stateReceiver), "stateReceiver");
  }

  function test_deployment() public view {
    assertEq(stateReceiver.rootSetter(), rootSetter);
  }

  function testRevert_commitState_OnlySystem() public {
    vm.expectRevert("Not System Addess!");
    stateReceiver.commitState(0, "");
  }

  function testRevert_commitState_StateIdsAreNotSequential() public {
    bytes memory recordBytes = _encodeRecord(2, address(0), "");
    vm.expectRevert("StateIds are not sequential");
    vm.prank(SYSTEM_ADDRESS);
    stateReceiver.commitState(0, recordBytes);
  }

  function test_commitState_ReceiverNotContract() public {
    uint256 stateId = 1;
    address receiver = makeAddr("receiver");
    bytes memory recordBytes = _encodeRecord(stateId, receiver, "");

    vm.prank(SYSTEM_ADDRESS);
    assertFalse(stateReceiver.commitState(0, recordBytes));
    assertEq(stateReceiver.lastStateId(), 1);
  }

  function test_commitState_ReceiverReverts() public {
    uint256 stateId = 1;
    address receiver = makeAddr("receiver");
    vm.etch(receiver, "00");
    vm.mockCallRevert(receiver, "", "");
    bytes memory stateData = "State data";
    bytes memory recordBytes = _encodeRecord(stateId, receiver, stateData);

    vm.expectCallMinGas(
      receiver,
      0,
      5_000_000,
      abi.encodeWithSignature("onStateReceive(uint256,bytes)", stateId, stateData)
    );
    vm.prank(SYSTEM_ADDRESS);
    vm.expectEmit();
    emit StateCommitted(stateId, false);
    assertFalse(stateReceiver.commitState(0, recordBytes));
    assertEq(stateReceiver.lastStateId(), 1);
    assertEq(stateReceiver.failedStateSyncs(stateId), abi.encode(receiver, stateData));
  }

  function test_commitState_Success() public {
    uint256 stateId = 1;
    address receiver = makeAddr("receiver");
    vm.etch(receiver, "00");
    bytes memory stateData = "State data";
    bytes memory recordBytes = _encodeRecord(stateId, receiver, stateData);

    vm.expectCallMinGas(
      receiver,
      0,
      5_000_000,
      abi.encodeWithSignature("onStateReceive(uint256,bytes)", stateId, stateData)
    );
    vm.prank(SYSTEM_ADDRESS);
    vm.expectEmit();
    emit StateCommitted(stateId, true);
    assertTrue(stateReceiver.commitState(0, recordBytes));
    assertEq(stateReceiver.lastStateId(), 1);
  }

  function testRevert_ReplayFailedStateSync(uint256 stateId, bytes memory callData) public {
    vm.assume(stateId > 0);
    vm.store(address(stateReceiver), bytes32(0), bytes32(stateId - 1));
    assertTrue(revertingReceiver.shouldIRevert());
    bytes memory recordBytes = _encodeRecord(stateId, address(revertingReceiver), callData);

    vm.prank(SYSTEM_ADDRESS);
    vm.expectEmit();
    emit StateCommitted(stateId, false);
    assertFalse(stateReceiver.commitState(0, recordBytes));
    assertEq(stateReceiver.failedStateSyncs(stateId), abi.encode(address(revertingReceiver), callData));

    assertTrue(revertingReceiver.shouldIRevert());

    vm.expectRevert("TestRevertingReceiver");
    stateReceiver.replayFailedStateSync(stateId);
  }

  function test_ReplayFailedStateSync(uint256 stateId, bytes memory callData) public {
    vm.assume(stateId > 0);
    vm.store(address(stateReceiver), bytes32(0), bytes32(stateId - 1));
    assertTrue(revertingReceiver.shouldIRevert());
    bytes memory recordBytes = _encodeRecord(stateId, address(revertingReceiver), callData);

    vm.prank(SYSTEM_ADDRESS);
    vm.expectEmit();
    emit StateCommitted(stateId, false);
    assertFalse(stateReceiver.commitState(0, recordBytes));
    assertEq(stateReceiver.failedStateSyncs(stateId), abi.encode(address(revertingReceiver), callData));

    revertingReceiver.toggle();
    assertFalse(revertingReceiver.shouldIRevert());

    vm.expectEmit();
    emit StateSyncReplay(stateId);
    vm.expectCall(
      address(revertingReceiver),
      0,
      abi.encodeWithSignature("onStateReceive(uint256,bytes)", stateId, callData)
    );
    stateReceiver.replayFailedStateSync(stateId);

    vm.expectRevert("!found");
    stateReceiver.replayFailedStateSync(stateId);
  }

  function test_ReplayFailFromReenterer(uint256 stateId, bytes memory callData) public {
    vm.assume(stateId > 0);
    vm.store(address(stateReceiver), bytes32(0), bytes32(stateId - 1));
    bytes memory recordBytes = _encodeRecord(stateId, address(reenterer), callData);

    vm.prank(SYSTEM_ADDRESS);
    vm.expectEmit();
    emit StateCommitted(stateId, false);
    assertFalse(stateReceiver.commitState(0, recordBytes));
    assertEq(stateReceiver.failedStateSyncs(stateId), abi.encode(address(reenterer), callData));

    revertingReceiver.toggle();
    assertFalse(revertingReceiver.shouldIRevert());

    vm.expectCall(address(reenterer), 0, abi.encodeWithSignature("onStateReceive(uint256,bytes)", stateId, callData));
    vm.expectRevert("!found");
    stateReceiver.replayFailedStateSync(stateId);
  }

  function test_rootSetter(address random) public {
    vm.prank(random);
    if (random != rootSetter) vm.expectRevert("!rootSetter");
    stateReceiver.setRootAndLeafCount(bytes32(uint(0x1337)), 0);

    vm.prank(rootSetter);
    if (random == rootSetter) vm.expectRevert("!zero");
    stateReceiver.setRootAndLeafCount(bytes32(uint(0x1337)), 0);
  }

  function test_shouldNotReplayZeroLeaf(bytes32 root, bytes32[16] memory proof) public {
    vm.assume(root != bytes32(0));
    vm.prank(rootSetter);
    stateReceiver.setRootAndLeafCount(root, 1);

    vm.expectRevert(bytes("used"));
    stateReceiver.replayHistoricFailedStateSync(proof, 0, 0, address(0), new bytes(0));
  }

  function test_shouldNotReplayInvalidProof(bytes32 root, bytes32[16] memory proof, bytes memory stateData) public {
    vm.assume(root != bytes32(0));
    vm.prank(rootSetter);
    stateReceiver.setRootAndLeafCount(root, 1);

    vm.expectRevert("!proof");
    stateReceiver.replayHistoricFailedStateSync(
      proof,
      vm.randomUint(0, 2 ** 16 - 1),
      vm.randomUint(),
      vm.randomAddress(),
      stateData
    );
  }

  function test_FailedStateSyncs(bytes[] memory stateDatas) external {
    vm.assume(stateDatas.length > 1 && stateDatas.length < 10);

    address receiver = address(revertingReceiver);

    for (uint256 i = 0; i < stateDatas.length; ++i) {
      bytes memory recordBytes = _encodeRecord(i + 1, receiver, stateDatas[i]);

      vm.prank(SYSTEM_ADDRESS);
      vm.expectEmit();
      emit StateCommitted(i + 1, false);
      assertFalse(stateReceiver.commitState(0, recordBytes));
    }

    uint256 leafCount = stateDatas.length;
    bytes32 root;
    bytes[] memory proofs = new bytes[](leafCount);
    (root, proofs) = _getRootAndProofs(receiver, abi.encode(stateDatas));

    vm.prank(rootSetter);
    stateReceiver.setRootAndLeafCount(root, leafCount);

    revertingReceiver.toggle();

    for (uint256 i = 0; i < leafCount; ++i) {
      vm.expectCall(receiver, 0, abi.encodeWithSignature("onStateReceive(uint256,bytes)", i + 1, stateDatas[i]));
      vm.expectEmit();
      emit StateSyncReplay(i + 1);
      stateReceiver.replayHistoricFailedStateSync(
        abi.decode(proofs[i], (bytes32[16])),
        i,
        i + 1,
        receiver,
        stateDatas[i]
      );
    }
  }

  function _getRootAndProofs(
    address receiver,
    bytes memory stateDatasEncoded
  ) internal returns (bytes32 root, bytes[] memory proofs) {
    string[] memory inputs = new string[](4);
    inputs[0] = "node";
    inputs[1] = "test/helpers/merkle.js";
    inputs[2] = vm.toString(receiver);
    inputs[3] = vm.toString(stateDatasEncoded);

    (root, proofs) = abi.decode(vm.ffi(inputs), (bytes32, bytes[]));
  }

  function _encodeRecord(
    uint256 stateId,
    address receiver,
    bytes memory stateData
  ) public pure returns (bytes memory recordBytes) {
    return
      abi.encodePacked(
        LIST_SHORT_START,
        _rlpEncodeUint(stateId),
        _rlpEncodeAddress(receiver),
        _rlpEncodeBytes(stateData)
      );
  }

  function _rlpEncodeUint(uint256 value) internal pure returns (bytes memory) {
    if (value == 0) {
      return hex"80";
    } else if (value < 0x80) {
      return abi.encodePacked(uint8(value));
    } else {
      bytes memory result = new bytes(33);
      uint256 length = 0;
      while (value != 0) {
        length++;
        result[33 - length] = bytes1(uint8(value));
        value >>= 8;
      }
      bytes memory encoded = new bytes(length + 1);
      encoded[0] = bytes1(uint8(0x80 + length));
      for (uint256 i = 0; i < length; i++) {
        encoded[i + 1] = result[33 - length + i];
      }
      return encoded;
    }
  }

  function _rlpEncodeAddress(address value) internal pure returns (bytes memory) {
    bytes memory encoded = new bytes(21);
    encoded[0] = bytes1(uint8(0x94));
    for (uint256 i = 0; i < 20; i++) {
      encoded[i + 1] = bytes1(uint8(uint256(uint160(value)) >> (8 * (19 - i))));
    }
    return encoded;
  }

  function _rlpEncodeBytes(bytes memory value) internal pure returns (bytes memory) {
    uint256 length = value.length;
    if (length == 1 && uint8(value[0]) < 0x80) {
      return value;
    } else if (length <= 55) {
      bytes memory encoded = new bytes(length + 1);
      encoded[0] = bytes1(uint8(0x80 + length));
      for (uint256 i = 0; i < length; i++) {
        encoded[i + 1] = value[i];
      }
      return encoded;
    } else {
      bytes memory lengthEncoded = _rlpEncodeUint(length);
      bytes memory encoded = new bytes(1 + lengthEncoded.length + length);
      encoded[0] = bytes1(uint8(0xb7 + lengthEncoded.length));
      for (uint256 i = 0; i < lengthEncoded.length; i++) {
        encoded[i + 1] = lengthEncoded[i];
      }
      for (uint256 i = 0; i < length; i++) {
        encoded[i + 1 + lengthEncoded.length] = value[i];
      }
      return encoded;
    }
  }
}
