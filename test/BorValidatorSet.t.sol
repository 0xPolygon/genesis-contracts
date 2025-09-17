pragma solidity 0.8.26;

import "../lib/forge-std/src/Test.sol";

import "./helpers/IBorValidatorSet.sol";

contract BorValidatorSetTest is Test {
    uint8 constant LIST_SHORT_START = 0xc0;
    address public constant SYSTEM_ADDRESS = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
    bytes32 public constant CHAIN = keccak256("heimdall-15001");
    bytes32 public constant ROUND_TYPE = keccak256("vote");
    bytes32 public constant BOR_ID = keccak256("15001");
    uint8 public constant VOTE_TYPE = 2;
    uint256 public constant FIRST_END_BLOCK = 255;
    uint256 public constant SPRINT = 64;

    uint256 private _newSpan;

    IBorValidatorSet internal borValidatorSet;

    function setUp() public {
        _newSpan = 1;
        borValidatorSet = IBorValidatorSet(deployCode("out/BorValidatorSet.sol/BorValidatorSet.json"));
    }

    function testConstants() public {
        assertEq(borValidatorSet.CHAIN(), CHAIN);
        assertEq(borValidatorSet.ROUND_TYPE(), ROUND_TYPE);
        assertEq(borValidatorSet.BOR_ID(), BOR_ID);
        assertEq(borValidatorSet.VOTE_TYPE(), VOTE_TYPE);
        assertEq(borValidatorSet.FIRST_END_BLOCK(), FIRST_END_BLOCK);
        assertEq(borValidatorSet.SPRINT(), SPRINT);
    }

    function test_currentSprint() public {
        assertEq(borValidatorSet.currentSprint(), 0);
        vm.roll(SPRINT);
        assertEq(borValidatorSet.currentSprint(), 1);
        vm.roll(SPRINT * 2 + 1);
        assertEq(borValidatorSet.currentSprint(), 2);
    }

    function test_getInitialValidators() public {
        (address[] memory addresses, uint256[] memory powers) = borValidatorSet.getInitialValidators();
        assertEq(addresses.length, 1);
        assertEq(powers.length, 1);
        assertEq(addresses[0], 0x6c468CF8c9879006E22EC4029696E005C2319C9D);
        assertEq(powers[0], 40);
    }

    function testRevert_commitSpan_OnlySystem() public {
        vm.expectRevert("Not System Addess!");
        borValidatorSet.commitSpan(0, 0, 0, "", "");
    }

    function testRevert_commitSpan_InvalidSpanId() public {
        vm.expectRevert("Invalid span id");
        vm.prank(SYSTEM_ADDRESS);
        borValidatorSet.commitSpan(0, 0, 0, "", "");
    }

    function testRevert_commitSpan_InvalidEndBlock() public {
        vm.expectRevert("End block must be greater than start block");
        vm.prank(SYSTEM_ADDRESS);
        borValidatorSet.commitSpan(1, 0, 0, "", "");
    }

    function testRevert_commitSpan_IncompleteSprint() public {
        vm.expectRevert("Difference between start and end block must be in multiples of sprint");
        vm.prank(SYSTEM_ADDRESS);
        borValidatorSet.commitSpan(1, 0, 64 * 2, "", "");
    }

    function test_commitSpan() public {
        uint256 newSpan = 1;
        uint256 startBlock = 0;
        uint256 endBlock = 64 * 2 - 1;

        uint256 numOfValidators = 5;
        uint256 numOfProducers = 3;

        uint256[] memory ids;
        uint256[] memory powers;
        address[] memory signers;
        bytes memory validatorBytes;
        bytes memory producerBytes;

        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "test/helpers/rlpEncodeValidatorsAndProducers.js";
        cmd[2] = vm.toString(numOfValidators);
        cmd[3] = vm.toString(numOfProducers);
        bytes memory result = vm.ffi(cmd);
        (ids, powers, signers, validatorBytes, producerBytes) = abi.decode(result, (uint256[], uint256[], address[], bytes, bytes));

        vm.prank(SYSTEM_ADDRESS);
        borValidatorSet.commitSpan(newSpan, startBlock, endBlock, validatorBytes, producerBytes);

        (uint256 number_, uint256 startBlock_, uint256 endBlock_) = borValidatorSet.spans(0);
        assertEq(number_, 0);
        assertEq(startBlock_, 0);
        assertEq(endBlock_, FIRST_END_BLOCK);
        assertEq(borValidatorSet.spanNumbers(0), 0);
        (uint256 id, uint256 power, address signer) = borValidatorSet.validators(0, 0);
        (address[] memory initialAddresses, uint256[] memory initialPowers) = borValidatorSet.getInitialValidators();
        assertEq(id, 0);
        assertEq(power, initialPowers[0]);
        assertEq(signer, initialAddresses[0]);
        vm.expectRevert();
        borValidatorSet.validators(0, 1);
        (id, power, signer) = borValidatorSet.producers(0, 0);
        assertEq(id, 0);
        assertEq(power, initialPowers[0]);
        assertEq(signer, initialAddresses[0]);
        vm.expectRevert();
        borValidatorSet.producers(0, 1);
        (number_, startBlock_, endBlock_) = borValidatorSet.spans(newSpan);
        assertEq(number_, newSpan);
        assertEq(startBlock_, startBlock);
        assertEq(endBlock_, endBlock);
        assertEq(borValidatorSet.spanNumbers(1), newSpan);
        for (uint256 i = 0; i < numOfValidators; i++) {
            (id, power, signer) = borValidatorSet.validators(newSpan, i);
            assertEq(id, ids[i]);
            assertEq(power, powers[i]);
            assertEq(signer, signers[i]);
            if (i >= numOfProducers) continue;
            (id, power, signer) = borValidatorSet.producers(newSpan, i);
            assertEq(id, ids[i]);
            assertEq(power, powers[i]);
            assertEq(signer, signers[i]);
        }
        vm.expectRevert();
        borValidatorSet.validators(newSpan, numOfValidators);
        vm.expectRevert();
        borValidatorSet.producers(newSpan, numOfProducers);
    }

    function testRevert_commitSpan_StartLesserThanCurrentSpanStart() public {
        _commitSpan();
        vm.expectRevert("Start block must be greater than current span");
        vm.prank(SYSTEM_ADDRESS);
        borValidatorSet.commitSpan(2, 0, 64 * 2 - 1, "", "");
    }

    // @note Redundant check.
    /*function testRevert_commitSpan_AlreadyExists() public {
    }*/

    function test_getSpan() public {
        _commitSpan();
        (uint256 number, uint256 startBlock, uint256 endBlock) = borValidatorSet.getSpan(0);
        assertEq(number, 0);
        assertEq(startBlock, 0);
        assertEq(endBlock, FIRST_END_BLOCK);
        (number, startBlock, endBlock) = borValidatorSet.getSpan(1);
        assertEq(number, 1);
        assertEq(startBlock, 1);
        assertEq(endBlock, 64 * 2);
    }

    function test_getSpanByBlock() public {
        assertEq(borValidatorSet.getSpanByBlock(1_234_567_890), 0);
        _commitSpan();
        _commitSpan(1000);
        assertEq(borValidatorSet.getSpanByBlock(0), 0);
        assertEq(borValidatorSet.getSpanByBlock(100), 1);
        assertEq(borValidatorSet.getSpanByBlock(1001), 2);
        assertEq(borValidatorSet.getSpanByBlock(1_234_567_890), 2);
    }

    function test_currentSpanNumber() public {
        vm.roll(1_234_567_890);
        assertEq(borValidatorSet.currentSpanNumber(), 0);
        _commitSpan();
        _commitSpan(1000);
        vm.roll(0);
        assertEq(borValidatorSet.currentSpanNumber(), 0);
        vm.roll(100);
        assertEq(borValidatorSet.currentSpanNumber(), 1);
        vm.roll(1001);
        assertEq(borValidatorSet.currentSpanNumber(), 2);
        vm.roll(1_234_567_890);
        assertEq(borValidatorSet.currentSpanNumber(), 2);
    }

    function test_getCurrentSpan() public {
        _commitSpan();
        (uint256 number, uint256 startBlock, uint256 endBlock) = borValidatorSet.getCurrentSpan();
        assertEq(number, 1);
        assertEq(startBlock, 1);
        assertEq(endBlock, 64 * 2);
    }

    function test_getNextSpan() public {
        _commitSpan();
        vm.roll(0);
        (uint256 number, uint256 startBlock, uint256 endBlock) = borValidatorSet.getNextSpan();
        assertEq(number, 1);
        assertEq(startBlock, 1);
        assertEq(endBlock, 64 * 2);
    }

    function test_getValidatorsTotalStakeBySpan() public {
        (uint256[] memory ids, uint256[] memory powers, address[] memory signers) = _commitSpan();
        uint256 totalStake;
        for (uint256 i = 0; i < 5; i++) {
            totalStake += powers[i];
        }
        assertEq(borValidatorSet.getValidatorsTotalStakeBySpan(1), totalStake);
    }

    function test_getProducersTotalStakeBySpan() public {
        (uint256[] memory ids, uint256[] memory powers, address[] memory signers) = _commitSpan();
        uint256 totalStake;
        for (uint256 i = 0; i < 3; i++) {
            totalStake += powers[i];
        }
        assertEq(borValidatorSet.getProducersTotalStakeBySpan(1), totalStake);
    }

    function test_getValidatorBySigner() public {
        (uint256[] memory ids, uint256[] memory powers, address[] memory signers) = _commitSpan();
        Validator memory validator = borValidatorSet.getValidatorBySigner(1, signers[4]);
        assertEq(validator.id, ids[4]);
        assertEq(validator.power, powers[4]);
        assertEq(validator.signer, signers[4]);
    }

    function test_isValidator() public {
        (uint256[] memory ids, uint256[] memory powers, address[] memory signers) = _commitSpan();
        assertTrue(borValidatorSet.isValidator(1, signers[4]));
        assertFalse(borValidatorSet.isValidator(1, makeAddr("not validator")));
    }

    function test_isProducer() public {
        (uint256[] memory ids, uint256[] memory powers, address[] memory signers) = _commitSpan();
        assertFalse(borValidatorSet.isProducer(1, signers[4]));
        assertFalse(borValidatorSet.isProducer(1, makeAddr("not producer")));
        assertTrue(borValidatorSet.isProducer(1, signers[1]));
    }

    function test_isCurrentValidator() public {
        (uint256[] memory ids, uint256[] memory powers, address[] memory signers) = _commitSpan();
        assertTrue(borValidatorSet.isCurrentValidator(signers[4]));
        vm.roll(0);
        assertFalse(borValidatorSet.isCurrentValidator(signers[4]));
    }

    function test_isCurrentProducer() public {
        (uint256[] memory ids, uint256[] memory powers, address[] memory signers) = _commitSpan();
        assertTrue(borValidatorSet.isCurrentProducer(signers[1]));
        vm.roll(0);
        assertFalse(borValidatorSet.isCurrentProducer(signers[1]));
    }

    function test_getBorValidators() public {
        (address[] memory addresses, uint256[] memory powers) = borValidatorSet.getBorValidators(0);
        assertEq(addresses.length, 1);
        assertEq(powers.length, 1);
        assertEq(addresses[0], 0x6c468CF8c9879006E22EC4029696E005C2319C9D);
        assertEq(powers[0], 40);
        (uint256[] memory ids_, uint256[] memory powers_, address[] memory signers_) = _commitSpan();
        (addresses, powers) = borValidatorSet.getBorValidators(FIRST_END_BLOCK + 1);
        for (uint256 i; i < addresses.length; ++i) {
            assertEq(addresses[i], signers_[i]);
            assertEq(powers[i], powers_[i]);
        }
    }

    function test_getValidators() public {
        vm.roll(0);
        (address[] memory addresses, uint256[] memory powers) = borValidatorSet.getValidators();
        assertEq(addresses.length, 1);
        assertEq(powers.length, 1);
        assertEq(addresses[0], 0x6c468CF8c9879006E22EC4029696E005C2319C9D);
        assertEq(powers[0], 40);
        (uint256[] memory ids_, uint256[] memory powers_, address[] memory signers_) = _commitSpan();
        vm.roll(FIRST_END_BLOCK + 1);
        (addresses, powers) = borValidatorSet.getValidators();
        for (uint256 i; i < addresses.length; ++i) {
            assertEq(addresses[i], signers_[i]);
            assertEq(powers[i], powers_[i]);
        }
    }

    function test_getStakePowerBySigs() public {
        Account[] memory signerAccounts = new Account[](5);
        address[] memory specificSigners = new address[](5);

        bytes32 digest = bytes32("something");
        bytes memory sigs;

        for (uint256 i; i < signerAccounts.length; ++i) {
            signerAccounts[i] = makeAccount(string.concat("signer", vm.toString(i)));
            specificSigners[i] = signerAccounts[i].addr;
        }

        specificSigners = _sortAddresses(specificSigners);

        for (uint256 i; i < signerAccounts.length; ++i) {
            uint256 key;
            for (uint256 j; j < signerAccounts.length; ++j) {
                if (signerAccounts[j].addr == specificSigners[i]) {
                    key = signerAccounts[j].key;
                    break;
                }
            }
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
            bytes memory sig = bytes.concat(r, s, bytes1(v));
            sigs = abi.encodePacked(sigs, sig);
        }

        (uint256[] memory ids_, uint256[] memory powers_, address[] memory signers_) = _commitSpan(specificSigners);

        uint256 sum;
        for (uint256 i; i < powers_.length; ++i) {
            sum += powers_[i];
        }

        assertEq(borValidatorSet.getStakePowerBySigs(1, digest, sigs), sum);
    }

    function test_checkMembership_SingleLeaf() public {
        bytes32 leaf = keccak256("leaf");
        assertTrue(borValidatorSet.checkMembership(leaf, leaf, ""));
        assertFalse(borValidatorSet.checkMembership(keccak256("not root"), leaf, ""));
    }

    function test_checkMembership() public {
        bytes32 leaf = keccak256("leaf");
        bytes32 proof1 = keccak256("proof1");
        bytes32 proof2 = keccak256("proof2");
        bytes32 computedHash = sha256(abi.encodePacked(hex"00", leaf));
        bytes memory proof = abi.encodePacked(hex"01", proof1, hex"00", proof2, "garbage");
        bytes32 root = sha256(abi.encodePacked(hex"01", computedHash, proof1));
        root = sha256(abi.encodePacked(hex"01", proof2, root));
        assertTrue(borValidatorSet.checkMembership(root, leaf, proof));
        bytes memory wrongProof = abi.encodePacked(hex"01", proof1, hex"01", proof2, "garbage");
        assertFalse(borValidatorSet.checkMembership(root, leaf, wrongProof));
    }

    function test_leafNode(bytes32 d) public returns (bytes32) {
        assertEq(borValidatorSet.leafNode(d), sha256(abi.encodePacked(bytes1(uint8(0)), d)));
    }

    function test_innerNode(bytes32 left, bytes32 right) public returns (bytes32) {
        assertEq(borValidatorSet.innerNode(left, right), sha256(abi.encodePacked(bytes1(uint8(1)), left, right)));
    }

    function _commitSpan() internal returns (uint256[] memory ids, uint256[] memory powers, address[] memory signers) {
        return _commitSpan(0, new address[](0));
    }

    function _commitSpan(uint256 startBlockOffset) internal returns (uint256[] memory ids, uint256[] memory powers, address[] memory signers) {
        return _commitSpan(startBlockOffset, new address[](0));
    }

    function _commitSpan(address[] memory specificSigners) internal returns (uint256[] memory ids, uint256[] memory powers, address[] memory signers) {
        return _commitSpan(0, specificSigners);
    }

    function _commitSpan(uint256 startBlockOffset, address[] memory specificSigners)
        internal
        returns (uint256[] memory ids, uint256[] memory powers, address[] memory signers)
    {
        uint256 startBlock = 1 + startBlockOffset;
        uint256 endBlock = startBlockOffset + 64 * 2;

        uint256 numOfValidators = 5;
        uint256 numOfProducers = 3;

        uint256[] memory ids;
        uint256[] memory powers;
        address[] memory signers;
        bytes memory validatorBytes;
        bytes memory producerBytes;

        string[] memory cmd = new string[](specificSigners.length == 0 ? 4 : 5);
        cmd[0] = "node";
        cmd[1] = "test/helpers/rlpEncodeValidatorsAndProducers.js";
        cmd[2] = vm.toString(numOfValidators);
        cmd[3] = vm.toString(numOfProducers);
        if (specificSigners.length != 0) cmd[4] = vm.toString(abi.encode(specificSigners));
        bytes memory result = vm.ffi(cmd);
        (ids, powers, signers, validatorBytes, producerBytes) = abi.decode(result, (uint256[], uint256[], address[], bytes, bytes));

        vm.prank(SYSTEM_ADDRESS);
        borValidatorSet.commitSpan(_newSpan, startBlock, endBlock, validatorBytes, producerBytes);

        ++_newSpan;

        return (ids, powers, signers);
    }

    function _sortAddresses(address[] memory addresses) internal pure returns (address[] memory) {
        uint256 length = addresses.length;
        bool swapped;

        for (uint256 i = 0; i < length - 1; i++) {
            swapped = false;
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (addresses[j] > addresses[j + 1]) {
                    address temp = addresses[j];
                    addresses[j] = addresses[j + 1];
                    addresses[j + 1] = temp;
                    swapped = true;
                }
            }

            if (!swapped) break;
        }

        return addresses;
    }
}
