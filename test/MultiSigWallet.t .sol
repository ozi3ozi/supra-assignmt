// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { console } from "forge-std/src/console.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";
import { stdError } from "forge-std/src/Test.sol";

import { MultiSigWallet } from "../src/MultiSigWallet.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/// @dev If this is your first time with Forge, read this tutorial in the Foundry Book:
/// https://book.getfoundry.sh/forge/writing-tests
contract FooTest is PRBTest, StdCheats {
    MultiSigWallet internal multiSigWallet;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        multiSigWallet = new MultiSigWallet();
    }
}
