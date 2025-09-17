pragma solidity 0.8.26;

import "../lib/forge-std/src/Test.sol";

import "./helpers/IECVerifyWrapper.sol";

contract ECVerifyTest is Test {
    Account internal signer;
    IECVerifyWrapper internal ecVerifyWrapper;

    function setUp() public {
        ecVerifyWrapper = IECVerifyWrapper(deployCode("out/ECVerifyWrapper.sol/ECVerifyWrapper.json"));
        signer = makeAccount("signer");
    }

    function test_ecrecovery_sig_LengthNot65() public {
        assertEq(ecVerifyWrapper.ecrecovery(bytes32(0), new bytes(64)), address(0));
        assertEq(ecVerifyWrapper.ecrecovery(bytes32(0), new bytes(66)), address(0));
    }

    function test_ecrecovery_sig_VNot27Or28() public {
        bytes memory sig = new bytes(65);
        sig[64] = bytes1(uint8(26));
        assertEq(ecVerifyWrapper.ecrecovery(bytes32(0), sig), address(0));
        sig[64] = bytes1(uint8(29));
        assertEq(ecVerifyWrapper.ecrecovery(bytes32(0), sig), address(0));
    }

    function testRevert_ecrecovery_sig_NotRecovered() public {
        vm.expectRevert();
        ecVerifyWrapper.ecrecovery(bytes32(0), new bytes(65));
    }

    function test_ecrecovery_sig() public {
        bytes32 digest = bytes32(vm.unixTime());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, digest);
        bytes memory sig = bytes.concat(r, s, bytes1(v));
        assertEq(ecVerifyWrapper.ecrecovery(digest, sig), signer.addr);
    }

    function test_ecrecovery_sig_AdjustsV() public {
        bytes32 digest = bytes32(uint256(134_234_234));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, digest);
        bytes memory sig = bytes.concat(r, s, bytes1(v - 27));
        assertEq(ecVerifyWrapper.ecrecovery(digest, sig), signer.addr);
    }

    function testRevert_ecrecovery_vrs_NotRecovered() public {
        vm.expectRevert();
        ecVerifyWrapper.ecrecovery(bytes32(0), 0, 0, 0);
    }

    function test_ecrecovery_vrs() public {
        bytes32 digest = bytes32(vm.unixTime());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, digest);
        assertEq(ecVerifyWrapper.ecrecovery(digest, v, r, s), signer.addr);
    }

    function test_ecverify_True() public {
        bytes32 digest = bytes32(vm.unixTime());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, digest);
        bytes memory sig = bytes.concat(r, s, bytes1(v));
        assertTrue(ecVerifyWrapper.ecverify(digest, sig, signer.addr));
    }

    function test_ecverify_False() public {
        bytes32 digest = bytes32(vm.unixTime());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, digest);
        bytes memory sig = bytes.concat(r, s, bytes1(v));
        assertFalse(ecVerifyWrapper.ecverify(keccak256("fiuewgfniuw34n"), sig, signer.addr));
    }
}
