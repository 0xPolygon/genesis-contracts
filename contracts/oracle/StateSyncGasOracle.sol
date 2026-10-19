// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IStateSyncGasOracle} from "../IStateSyncGasOracle.sol";

/// @title StateSyncGasOracle
/// @notice Gas limit that StateReceiver (0x0000000000000000000000000000000000001001) forwards to each
///         state sync receiver.
/// @dev Deployed behind a TransparentUpgradeableProxy. v1 returns one owner-set limit for every record;
///      per-receiver rules are an upgrade behind the same proxy, since every call already carries the full
///      record. StateReceiver caps the answer at its MAX_RECEIVER_GAS and falls back to its own default
///      when this contract reverts, runs out of its gas allowance or returns malformed data.
contract StateSyncGasOracle is IStateSyncGasOracle, Ownable2StepUpgradeable {
  /// @notice Same ceiling StateReceiver applies, so a limit above it is rejected instead of silently capped.
  uint256 public constant MAX_GAS_LIMIT = 5_000_000;

  /// @custom:storage-location erc7201:polygon.storage.StateSyncGasOracle
  struct StateSyncGasOracleStorage {
    uint256 gasLimit;
  }

  // keccak256(abi.encode(uint256(keccak256("polygon.storage.StateSyncGasOracle")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant STORAGE_LOCATION = 0x52a463d9fafd23036c8acb4ad55ffe5fd0cab584ff8822c6f748e07fb5783d00;

  /// @notice Emitted when the gas limit forwarded to every receiver changes.
  event GasLimitSet(uint256 gasLimit);

  /// @notice The requested limit is above MAX_GAS_LIMIT.
  error GasLimitTooHigh(uint256 gasLimit);

  constructor() {
    _disableInitializers();
  }

  /// @param owner_ Governance account allowed to change the gas limit.
  /// @param gasLimit_ Initial gas limit forwarded to every receiver.
  function initialize(address owner_, uint256 gasLimit_) external initializer {
    __Ownable_init(owner_);
    _setGasLimit(gasLimit_);
  }

  /// @inheritdoc IStateSyncGasOracle
  function getGasLimit(uint256, address, bytes calldata) external view returns (uint256) {
    return _getStorage().gasLimit;
  }

  /// @notice Gas limit currently forwarded to every receiver.
  function gasLimit() external view returns (uint256) {
    return _getStorage().gasLimit;
  }

  /// @notice Sets the gas limit forwarded to every receiver, from the next state sync on.
  function setGasLimit(uint256 gasLimit_) external onlyOwner {
    _setGasLimit(gasLimit_);
  }

  function _setGasLimit(uint256 gasLimit_) private {
    if (gasLimit_ > MAX_GAS_LIMIT) revert GasLimitTooHigh(gasLimit_);
    _getStorage().gasLimit = gasLimit_;
    emit GasLimitSet(gasLimit_);
  }

  function _getStorage() private pure returns (StateSyncGasOracleStorage storage $) {
    assembly {
      $.slot := STORAGE_LOCATION
    }
  }
}
