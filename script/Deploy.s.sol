// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { MultiSigWallet } from "../src/MultiSigWallet.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    address[] internal owners;

    function run() public broadcast returns (MultiSigWallet multiSigWallet) {
        multiSigWallet = new MultiSigWallet(owners, 80);
    }
}
