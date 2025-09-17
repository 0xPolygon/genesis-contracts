pragma solidity 0.8.26;

import "../lib/forge-std/src/Test.sol";

import "./helpers/IValidatorVerifier.sol";

contract ValidatorVerifierTest is Test {
    address public constant validatorSet = 0x0000000000000000000000000000000000001000;

    IValidatorVerifier internal validatorVerifier;

    function setUp() public {
        validatorVerifier = IValidatorVerifier(deployCode("out/ValidatorVerifier.sol/ValidatorVerifier.json"));
    }

    function test_constants() public {
        assertEq(validatorVerifier.validatorSet(), validatorSet);
    }

    function test_isValidatorSetContract() public {
        assertFalse(validatorVerifier.isValidatorSetContract());
        vm.prank(validatorSet);
        assertTrue(validatorVerifier.isValidatorSetContract());
    }

    function test_isValidator() public {
        vm.mockCall(validatorSet, abi.encodeWithSignature("isCurrentValidator(address)", address(this)), abi.encode(true));
        assertTrue(validatorVerifier.isValidator(address(this)));
        vm.mockCall(validatorSet, abi.encodeWithSignature("isCurrentValidator(address)", address(this)), abi.encode(false));
        assertFalse(validatorVerifier.isValidator(address(this)));
    }

    function test_isProducer() public {
        vm.mockCall(validatorSet, abi.encodeWithSignature("isCurrentProducer(address)", address(this)), abi.encode(true));
        assertTrue(validatorVerifier.isProducer(address(this)));
        vm.mockCall(validatorSet, abi.encodeWithSignature("isCurrentProducer(address)", address(this)), abi.encode(false));
        assertFalse(validatorVerifier.isProducer(address(this)));
    }
}
