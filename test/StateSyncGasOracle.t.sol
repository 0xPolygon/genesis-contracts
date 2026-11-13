pragma solidity 0.8.28;

import "../lib/forge-std/src/Test.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
  ITransparentUpgradeableProxy,
  TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {StateSyncGasOracle} from "contracts/oracle/StateSyncGasOracle.sol";
import {TestGasOracleV2} from "test/helpers/TestGasOracleV2.sol";

contract StateSyncGasOracleTest is Test {
  event GasLimitSet(uint256 gasLimit);

  address internal governance = makeAddr("governance");
  uint256 internal constant GAS_LIMIT = 160_000;

  StateSyncGasOracle internal implementation;
  StateSyncGasOracle internal oracle;
  ProxyAdmin internal proxyAdmin;

  function setUp() public {
    implementation = new StateSyncGasOracle();
    oracle = StateSyncGasOracle(
      address(
        new TransparentUpgradeableProxy(
          address(implementation),
          governance,
          abi.encodeCall(StateSyncGasOracle.initialize, (governance, GAS_LIMIT))
        )
      )
    );
    proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(oracle), ERC1967Utils.ADMIN_SLOT)))));
  }

  function test_deployment() public view {
    assertEq(oracle.owner(), governance);
    assertEq(oracle.gasLimit(), GAS_LIMIT);
    assertEq(proxyAdmin.owner(), governance);
    assertEq(address(uint160(uint256(vm.load(address(oracle), ERC1967Utils.IMPLEMENTATION_SLOT)))), address(implementation));
  }

  function test_storageLocation() public view {
    bytes32 location = keccak256(abi.encode(uint256(keccak256("polygon.storage.StateSyncGasOracle")) - 1)) &
      ~bytes32(uint256(0xff));
    assertEq(uint256(vm.load(address(oracle), location)), GAS_LIMIT);
  }

  function testRevert_initialize_Implementation() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    implementation.initialize(governance, GAS_LIMIT);
  }

  function testRevert_initialize_Twice() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    oracle.initialize(address(this), GAS_LIMIT);
  }

  function test_getGasLimit(uint256 stateId, address receiver, bytes calldata data) public view {
    assertEq(oracle.getGasLimit(stateId, receiver, data), GAS_LIMIT);
  }

  function test_setGasLimit(uint256 gasLimit) public {
    gasLimit = bound(gasLimit, 0, oracle.MAX_GAS_LIMIT());
    vm.expectEmit(address(oracle));
    emit GasLimitSet(gasLimit);
    vm.prank(governance);
    oracle.setGasLimit(gasLimit);
    assertEq(oracle.getGasLimit(1, address(this), ""), gasLimit);
  }

  function testRevert_setGasLimit_TooHigh(uint256 gasLimit) public {
    gasLimit = bound(gasLimit, oracle.MAX_GAS_LIMIT() + 1, type(uint256).max);
    vm.expectRevert(abi.encodeWithSelector(StateSyncGasOracle.GasLimitTooHigh.selector, gasLimit));
    vm.prank(governance);
    oracle.setGasLimit(gasLimit);
  }

  function testRevert_setGasLimit_OnlyOwner(address caller) public {
    vm.assume(caller != governance && caller != address(proxyAdmin));
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
    vm.prank(caller);
    oracle.setGasLimit(1);
  }

  function test_transferOwnership_TwoStep() public {
    address newGovernance = makeAddr("newGovernance");
    vm.prank(governance);
    oracle.transferOwnership(newGovernance);
    assertEq(oracle.owner(), governance);
    assertEq(oracle.pendingOwner(), newGovernance);

    vm.prank(newGovernance);
    oracle.acceptOwnership();
    assertEq(oracle.owner(), newGovernance);
  }

  function test_upgrade() public {
    TestGasOracleV2 v2 = new TestGasOracleV2();
    vm.prank(governance);
    proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(oracle)), address(v2), "");

    address receiver = address(0x1234);
    assertEq(oracle.getGasLimit(1, receiver, ""), uint256(uint160(receiver)) % 1_000_000);
  }

  function testRevert_upgrade_OnlyProxyAdminOwner(address caller) public {
    vm.assume(caller != governance);
    TestGasOracleV2 v2 = new TestGasOracleV2();
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
    vm.prank(caller);
    proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(oracle)), address(v2), "");
  }
}
