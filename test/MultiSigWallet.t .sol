// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import "@openzeppelin/contracts/utils/Context.sol";

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { console } from "forge-std/src/console.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";
import { stdError } from "forge-std/src/Test.sol";

import { MultiSigWallet } from "../src/MultiSigWallet.sol";

contract MultiSigWalletTest is PRBTest, StdCheats, Context {
    MultiSigWallet internal multiSigWallet;
    address[] internal ownersToAdd;

    /// @dev A function invoked before each test case is run.
    function setUp() public {
        ownersToAdd.push(vm.addr(1));
        ownersToAdd.push(vm.addr(2));
        ownersToAdd.push(vm.addr(3));
        vm.label(ownersToAdd[0], "Alice");
        vm.label(ownersToAdd[1], "Bob");
        vm.label(ownersToAdd[2], "Tantzor");

        multiSigWallet = new MultiSigWallet(ownersToAdd, 80);
        console.log(msg.sender);
    }

    /// @dev List of ownersToAdd should be at least 2
    function testFuzz_RevertDeployingIf_OwnersLengthUnder2(uint16 _length) external {
        vm.assume(_length == 0 || _length == 1);
        vm.expectRevert("owners count is under 2");
        address[] memory ownersList = new address[](_length);
        if (_length == 1) 
            ownersList[0] = vm.addr(1);

        new MultiSigWallet(ownersList, 80);
    }

    /// @dev Threshold % must be > 0
    function test_RevertDeployingIf_ThresholdPrctIs0() external {
        vm.expectRevert("threshold % must be > 0");
        new MultiSigWallet(ownersToAdd, 0);
    }

    /// @dev Contract deployment should have list of ownersToAdd to add
    function test_WhenDeploying_ListOfOwnersIsAdded() external {
        assertTrue(multiSigWallet.getOwners().length == ownersToAdd.length);
        for (uint8 i = 0; i < ownersToAdd.length; i++) {
            assertTrue(multiSigWallet.isOwner(ownersToAdd[i]));    
        }
    }

    /// @dev When deploying, list of ownersToAdd cannot include address(0)
    function test_RevertDeployingIf_ZeroAddressInOwnersLst() external {
        vm.expectRevert("zero address in owners list");
        ownersToAdd.push(address(0));
        new MultiSigWallet(ownersToAdd, 80);
    }

    /// @dev When deploying, cannot add same address twice
    function test_RevertDeployingIf_AddressesNotUniqueInOwnersToAdd() external {
        vm.expectRevert("owner already exists");
        ownersToAdd.push(ownersToAdd[0]);
        new MultiSigWallet(ownersToAdd, 80);
    }

    /// @dev GetThresholdNbr should always return a number >= 2
    function test_TresholdNbrAlwaysGte2(uint8 _tresholdPrct) external {
        vm.assume(0 < _tresholdPrct && _tresholdPrct <= 100);
        multiSigWallet = new MultiSigWallet(ownersToAdd, _tresholdPrct);
        assertGte(multiSigWallet.getThresholdNbr(), 2);
    }

    /// @dev GetThresholdNbr should always return a number <= ownersToAdd.length
    function test_TresholdNbrMaxIsOwnersCount(uint8 _tresholdPrct) external {
        vm.assume(0 < _tresholdPrct && _tresholdPrct <= 100);
        multiSigWallet = new MultiSigWallet(ownersToAdd, _tresholdPrct);
        assertLte(multiSigWallet.getThresholdNbr(), ownersToAdd.length);
    }

    /// @dev When not < 2, GetThresholdNbr should always return a number based on tresholdPrct
    function test_GetThresholdNbrBasedOnTreshold(uint8 _thresholdPrct, uint8 _ownersCount) external {
        vm.assume(50 < _thresholdPrct && _thresholdPrct <= 100);
        vm.assume(2 < _ownersCount && _ownersCount <= 500);

        for (uint256 i = 1; i <= _ownersCount; i++) {
            ownersToAdd.push(vm.addr(i*4)); //*4 to avoid "owner already exists"
        }
        
        multiSigWallet = new MultiSigWallet(ownersToAdd, _thresholdPrct);
        uint16 threshold = uint16(ownersToAdd.length * _thresholdPrct / 100);
        threshold = _thresholdPrct == 100 ? threshold : threshold + 1;
        assertTrue(multiSigWallet.getThresholdNbr() == threshold);
    }
}
