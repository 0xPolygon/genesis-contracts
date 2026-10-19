pragma solidity 0.8.26;

import "../lib/forge-std/src/Test.sol";

import "./helpers/IStateReceiver.sol";
import {TestReenterer} from "test/helpers/TestReenterer.sol";
import {TestRevertingReceiver} from "test/helpers/TestRevertingReceiver.sol";
import {TestGasOracle} from "test/helpers/TestGasOracle.sol";

contract StateReceiverTest is Test {
  address public constant SYSTEM_ADDRESS = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
  uint8 constant LIST_SHORT_START = 0xc0;

  IStateReceiver internal stateReceiver = IStateReceiver(0x0000000000000000000000000000000000001001);
  address internal rootSetter = makeAddr("rootSetter");
  address internal gasOracle = makeAddr("gasOracle");
  uint64 internal constant DEFAULT_RECEIVER_GAS = 160_000;
  // STATE_RECEIVER_OUT=out-fork runs the suite on the bytecode built for the fork (profile.fork)
  string internal outDir = vm.envOr("STATE_RECEIVER_OUT", string("out"));

  TestReenterer internal reenterer = new TestReenterer();
  TestRevertingReceiver internal revertingReceiver = new TestRevertingReceiver();

  function setUp() public {
    address tmp = deployCode(string.concat(outDir, "/StateReceiver.sol/StateReceiver.json"), abi.encode(rootSetter, gasOracle));
    vm.etch(address(stateReceiver), tmp.code);
    vm.label(address(stateReceiver), "stateReceiver");
  }

  function test_deployment() public view {
    assertEq(stateReceiver.rootSetter(), rootSetter);
    assertEq(stateReceiver.gasOracle(), gasOracle);
    assertEq(stateReceiver.DEFAULT_RECEIVER_GAS(), DEFAULT_RECEIVER_GAS);
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
      DEFAULT_RECEIVER_GAS,
      abi.encodeWithSignature("onStateReceive(uint256,bytes)", stateId, stateData)
    );
    vm.prank(SYSTEM_ADDRESS);
    vm.expectEmit();
    emit StateCommitted(stateId, false);
    assertFalse(stateReceiver.commitState(0, recordBytes));
    assertEq(stateReceiver.lastStateId(), 1);
    assertEq(stateReceiver.failedStateSyncHashes(stateId), keccak256(abi.encode(receiver, stateData)));
    assertEq(stateReceiver.failedStateSyncs(stateId).length, 0);
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
      DEFAULT_RECEIVER_GAS,
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
    assertEq(stateReceiver.failedStateSyncHashes(stateId), keccak256(abi.encode(address(revertingReceiver), callData)));

    assertTrue(revertingReceiver.shouldIRevert());

    vm.expectRevert("TestRevertingReceiver");
    stateReceiver.replayFailedStateSyncWithData(stateId, address(revertingReceiver), callData);
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
    assertEq(stateReceiver.failedStateSyncHashes(stateId), keccak256(abi.encode(address(revertingReceiver), callData)));

    revertingReceiver.toggle();
    assertFalse(revertingReceiver.shouldIRevert());

    vm.expectEmit();
    emit StateSyncReplay(stateId);
    vm.expectCall(
      address(revertingReceiver),
      0,
      abi.encodeWithSignature("onStateReceive(uint256,bytes)", stateId, callData)
    );
    stateReceiver.replayFailedStateSyncWithData(stateId, address(revertingReceiver), callData);

    vm.expectRevert("!found");
    stateReceiver.replayFailedStateSyncWithData(stateId, address(revertingReceiver), callData);
  }

  function test_ReplayFailFromReenterer(uint256 stateId, bytes memory callData) public {
    vm.assume(stateId > 0);
    vm.store(address(stateReceiver), bytes32(0), bytes32(stateId - 1));
    bytes memory recordBytes = _encodeRecord(stateId, address(reenterer), callData);

    vm.prank(SYSTEM_ADDRESS);
    vm.expectEmit();
    emit StateCommitted(stateId, false);
    assertFalse(stateReceiver.commitState(0, recordBytes));
    assertEq(stateReceiver.failedStateSyncHashes(stateId), keccak256(abi.encode(address(reenterer), callData)));

    revertingReceiver.toggle();
    assertFalse(revertingReceiver.shouldIRevert());

    vm.expectCall(address(reenterer), 0, abi.encodeWithSignature("onStateReceive(uint256,bytes)", stateId, callData));
    vm.expectRevert("!found");
    stateReceiver.replayFailedStateSyncWithData(stateId, address(reenterer), callData);
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

  function test_receiverGas_NoOracleCode(uint256 stateId, address receiver, bytes memory stateData) public view {
    assertEq(stateReceiver.receiverGas(stateId, receiver, stateData), DEFAULT_RECEIVER_GAS);
  }

  function test_receiverGas_Oracle(uint256 gasLimit) public {
    _etchOracle(TestGasOracle.Mode.Value, gasLimit);
    uint256 expected = gasLimit > 5_000_000 ? 5_000_000 : gasLimit;
    assertEq(stateReceiver.receiverGas(1, address(revertingReceiver), "State data"), expected);
  }

  function test_receiverGas_OracleCalldata(uint256 stateId, address receiver, bytes memory stateData) public {
    _etchOracle(TestGasOracle.Mode.Value, 300_000);
    vm.expectCall(gasOracle, abi.encodeCall(TestGasOracle.getGasLimit, (stateId, receiver, stateData)));
    stateReceiver.receiverGas(stateId, receiver, stateData);
  }

  function test_receiverGas_OracleFailures() public {
    TestGasOracle.Mode[3] memory modes = [TestGasOracle.Mode.Revert, TestGasOracle.Mode.Short, TestGasOracle.Mode.Burn];
    for (uint256 i = 0; i < modes.length; ++i) {
      _etchOracle(modes[i], 300_000);
      assertEq(stateReceiver.receiverGas(1, address(revertingReceiver), "State data"), DEFAULT_RECEIVER_GAS);
    }
  }

  function test_commitState_OracleGas() public {
    _etchOracle(TestGasOracle.Mode.Value, 300_000);
    revertingReceiver.toggle();
    bytes memory stateData = "State data";
    bytes memory recordBytes = _encodeRecord(1, address(revertingReceiver), stateData);

    vm.expectCallMinGas(
      address(revertingReceiver),
      0,
      300_000,
      abi.encodeWithSignature("onStateReceive(uint256,bytes)", 1, stateData)
    );
    vm.prank(SYSTEM_ADDRESS);
    assertTrue(stateReceiver.commitState(0, recordBytes));
  }

  function test_commitState_OracleZeroGas() public {
    _etchOracle(TestGasOracle.Mode.Value, 0);
    revertingReceiver.toggle();
    bytes memory stateData = "State data";
    bytes memory recordBytes = _encodeRecord(1, address(revertingReceiver), stateData);

    vm.prank(SYSTEM_ADDRESS);
    vm.expectEmit();
    emit StateCommitted(1, false);
    assertFalse(stateReceiver.commitState(0, recordBytes));

    // anyone can replay it with their own gas
    vm.expectEmit();
    emit StateSyncReplay(1);
    stateReceiver.replayFailedStateSyncWithData(1, address(revertingReceiver), stateData);
    assertEq(stateReceiver.failedStateSyncHashes(1), bytes32(0));
  }

  function test_commitState_OracleBurnsGas() public {
    _etchOracle(TestGasOracle.Mode.Burn, 0);
    revertingReceiver.toggle();
    bytes memory recordBytes = _encodeRecord(1, address(revertingReceiver), "State data");

    uint256 gasBefore = gasleft();
    vm.prank(SYSTEM_ADDRESS);
    assertTrue(stateReceiver.commitState(0, recordBytes));
    assertLt(gasBefore - gasleft(), stateReceiver.ORACLE_GAS() + 100_000);
    assertEq(stateReceiver.lastStateId(), 1);
  }

  function test_commitState_ReceiverNotContractSkipsOracle() public {
    _etchOracle(TestGasOracle.Mode.Value, 300_000);
    bytes memory recordBytes = _encodeRecord(1, makeAddr("receiver"), "State data");

    vm.expectCall(gasOracle, abi.encodeWithSelector(TestGasOracle.getGasLimit.selector), 0);
    vm.prank(SYSTEM_ADDRESS);
    assertFalse(stateReceiver.commitState(0, recordBytes));
  }

  function testRevert_replayFailedStateSyncWithData(bytes memory callData, bytes memory otherData) public {
    vm.assume(keccak256(callData) != keccak256(otherData));
    bytes memory recordBytes = _encodeRecord(1, address(revertingReceiver), callData);
    vm.prank(SYSTEM_ADDRESS);
    assertFalse(stateReceiver.commitState(0, recordBytes));
    revertingReceiver.toggle();

    vm.expectRevert("!found");
    stateReceiver.replayFailedStateSyncWithData(2, address(revertingReceiver), callData);
    vm.expectRevert("!data");
    stateReceiver.replayFailedStateSyncWithData(1, address(revertingReceiver), otherData);
    vm.expectRevert("!data");
    stateReceiver.replayFailedStateSyncWithData(1, address(reenterer), callData);

    stateReceiver.replayFailedStateSyncWithData(1, address(revertingReceiver), callData);
  }

  function test_commitState_StateSyncGasOracle() public {
    // the real oracle behind its proxy, owned by rootSetter for the test
    address implementation = deployCode("StateSyncGasOracle.sol:StateSyncGasOracle");
    address proxy = deployCode(
      "TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
      abi.encode(implementation, rootSetter, abi.encodeWithSignature("initialize(address,uint256)", rootSetter, 300_000))
    );
    address tmp = deployCode(string.concat(outDir, "/StateReceiver.sol/StateReceiver.json"), abi.encode(rootSetter, proxy));
    vm.etch(address(stateReceiver), tmp.code);

    // a record at heimdall's size limit still gets the oracle's answer within ORACLE_GAS
    bytes memory stateData = new bytes(29_900);
    uint256 gasBefore = gasleft();
    assertEq(stateReceiver.receiverGas(1, address(revertingReceiver), stateData), 300_000);
    emit log_named_uint("receiverGas gas, 29.9 KB record", gasBefore - gasleft());

    revertingReceiver.toggle();
    vm.expectCallMinGas(
      address(revertingReceiver),
      0,
      300_000,
      abi.encodeWithSignature("onStateReceive(uint256,bytes)", 1, stateData)
    );
    vm.prank(SYSTEM_ADDRESS);
    assertTrue(stateReceiver.commitState(0, _encodeRecord(1, address(revertingReceiver), stateData)));

    // governance changes the limit without a fork
    vm.prank(rootSetter);
    (bool success, ) = proxy.call(abi.encodeWithSignature("setGasLimit(uint256)", 0));
    assertTrue(success);
    assertEq(stateReceiver.receiverGas(2, address(revertingReceiver), stateData), 0);
  }

  function test_upgrade() public {
    _etchLegacy();

    // record 1 succeeds, 2 and 3 fail under the live code
    revertingReceiver.toggle();
    vm.startPrank(SYSTEM_ADDRESS);
    assertTrue(stateReceiver.commitState(0, _encodeRecord(1, address(revertingReceiver), "one")));
    revertingReceiver.toggle();
    assertFalse(stateReceiver.commitState(0, _encodeRecord(2, address(revertingReceiver), "two")));
    assertFalse(stateReceiver.commitState(0, _encodeRecord(3, address(revertingReceiver), "three")));
    vm.stopPrank();
    vm.prank(rootSetter);
    stateReceiver.setRootAndLeafCount(bytes32(uint256(0x1337)), 76);

    _etchNew();

    assertEq(stateReceiver.lastStateId(), 3);
    assertEq(stateReceiver.failedStateSyncsRoot(), bytes32(uint256(0x1337)));
    assertEq(stateReceiver.leafCount(), 76);
    assertEq(stateReceiver.failedStateSyncs(2), abi.encode(address(revertingReceiver), bytes("two")));

    // new failures store only the hash, in the slot appended after replayCount
    vm.prank(SYSTEM_ADDRESS);
    assertFalse(stateReceiver.commitState(0, _encodeRecord(4, address(revertingReceiver), "four")));
    bytes32 stateSyncHash = keccak256(abi.encode(address(revertingReceiver), bytes("four")));
    assertEq(stateReceiver.failedStateSyncHashes(4), stateSyncHash);
    assertEq(vm.load(address(stateReceiver), keccak256(abi.encode(uint256(4), uint256(6)))), stateSyncHash);
    assertEq(stateReceiver.failedStateSyncs(4).length, 0);

    // failures from before the upgrade replay through the old path only
    revertingReceiver.toggle();
    vm.expectRevert("!found");
    stateReceiver.replayFailedStateSyncWithData(2, address(revertingReceiver), "two");
    stateReceiver.replayFailedStateSync(2);
    assertEq(stateReceiver.failedStateSyncs(2).length, 0);
    stateReceiver.replayFailedStateSyncWithData(4, address(revertingReceiver), "four");

    // the root can no longer be reset
    vm.prank(rootSetter);
    vm.expectRevert("!zero");
    stateReceiver.setRootAndLeafCount(bytes32(uint256(0x1338)), 1);
  }

  function test_gas_LargeFailedRecord() public {
    // just under heimdall's 30_000 byte limit
    bytes memory stateData = new bytes(29_900);
    for (uint256 i = 0; i < stateData.length; i += 32) stateData[i] = 0xff;
    bytes memory recordBytes = _encodeRecord(1, address(revertingReceiver), stateData);

    _etchLegacy();
    uint256 legacyGas = _commitGas(recordBytes);
    vm.store(address(stateReceiver), bytes32(0), bytes32(0));
    _etchNew();
    uint256 newGas = _commitGas(recordBytes);

    // the same payload when nothing is stored: parsing and copying cost, paid by every large record
    vm.store(address(stateReceiver), bytes32(0), bytes32(0));
    uint256 eoaGas = _commitGas(_encodeRecord(1, makeAddr("receiver"), stateData));
    vm.store(address(stateReceiver), bytes32(0), bytes32(0));
    revertingReceiver.toggle();
    uint256 successGas = _commitGas(_encodeRecord(1, address(revertingReceiver), stateData));

    emit log_named_uint("legacy failed commitState gas", legacyGas);
    emit log_named_uint("new failed commitState gas", newGas);
    emit log_named_uint("new non-contract receiver commitState gas", eoaGas);
    emit log_named_uint("new successful commitState gas", successGas);
    assertGt(legacyGas, 40 * newGas);
    assertLt(newGas, successGas + 100_000);
  }

  function _commitGas(bytes memory recordBytes) internal returns (uint256) {
    uint256 gasBefore = gasleft();
    vm.prank(SYSTEM_ADDRESS);
    stateReceiver.commitState(0, recordBytes);
    return gasBefore - gasleft();
  }

  function _etchOracle(TestGasOracle.Mode mode, uint256 gasLimit) internal {
    vm.etch(gasOracle, address(new TestGasOracle()).code);
    TestGasOracle(gasOracle).set(mode, gasLimit);
  }

  function _etchLegacy() internal {
    address tmp = deployCode(string.concat(outDir, "/LegacyStateReceiver.sol/LegacyStateReceiver.json"), abi.encode(rootSetter));
    vm.etch(address(stateReceiver), tmp.code);
  }

  function _etchNew() internal {
    address tmp = deployCode(string.concat(outDir, "/StateReceiver.sol/StateReceiver.json"), abi.encode(rootSetter, gasOracle));
    vm.etch(address(stateReceiver), tmp.code);
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
    bytes memory payload = abi.encodePacked(
      _rlpEncodeUint(stateId),
      _rlpEncodeAddress(receiver),
      _rlpEncodeBytes(stateData)
    );
    if (payload.length <= 55) return abi.encodePacked(uint8(LIST_SHORT_START + payload.length), payload);
    // long list: 0xf7 + length of the length, then the length
    bytes memory lengthBytes = _lengthBytes(payload.length);
    return abi.encodePacked(uint8(0xf7 + lengthBytes.length), lengthBytes, payload);
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

  // big-endian length without leading zeros, as used by long RLP strings and lists
  function _lengthBytes(uint256 length) internal pure returns (bytes memory lengthBytes) {
    while (length != 0) {
      lengthBytes = abi.encodePacked(uint8(length), lengthBytes);
      length >>= 8;
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
      bytes memory lengthEncoded = _lengthBytes(length);
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
