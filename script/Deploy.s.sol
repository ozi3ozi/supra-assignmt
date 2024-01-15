// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { MultiSigWallet } from "../src/MultiSigWallet.sol";
import { VotingSystem } from "../src/VotingSystem.sol";
import { FixedSwapper } from "../src/FixedSwapper.sol";
import { SupraToken } from "../src/SupraToken.sol";
import { TokenSeller, CrowdSale } from "../src/TokenSeller.sol";

import { console } from "forge-std/src/console.sol";
import { Script } from "forge-std/src/Script.sol";


/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is Script {
    CrowdSale preSale = CrowdSale({
        maxCap: 100_000 * 10**18,
        minCap: 50_000 * 10**18,
        maxPerBuyer: 1000 * 10**18,
        minPerBuyer: 100 * 10**18,
        startTime: block.timestamp + 5 days,
        endTime: block.timestamp + 10 days,
        rate: 100,
        raisedWei: 0,
        tokensSold: 0,
        buyers: new address[](0)
    });
    CrowdSale publicSale = CrowdSale({
        maxCap: 100_000 * 10**18,
        minCap: 50_000 * 10**18,
        maxPerBuyer: 1000 * 10**18,
        minPerBuyer: 100 * 10**18,
        startTime: preSale.endTime,
        endTime: preSale.endTime + 10 days,
        rate: 150,
        raisedWei: 0,
        tokensSold: 0,
        buyers: new address[](0)
    });
    address[] internal owners = generateRandomAddresses(10);
    VotingSystem public votingSystem;
    MultiSigWallet public multiSigWallet;
    FixedSwapper public fixedSwapper;
    SupraToken public tokenA;
    SupraToken public tokenB;
    TokenSeller public tokenSeller;

    function run() public {
        vm.startBroadcast();

        console.log(msg.sender);
        multiSigWallet = new MultiSigWallet(owners, 80);
        votingSystem = new VotingSystem(owners);
        tokenA = new SupraToken("TokenA", "ATOK", 1000000* 10**18, msg.sender);
        tokenB = new SupraToken("TokenB", "BOTK", 1_000_000* 10**14, msg.sender);
        fixedSwapper = new FixedSwapper(address(tokenA), tokenA.decimals(), address(tokenB), tokenB.decimals(), 4);
        tokenSeller = new TokenSeller(address(tokenA), 1000000* 10**18, preSale, publicSale);

        vm.stopBroadcast();
    }
}

function generateRandomAddresses(uint256 numAddresses) view returns (address[] memory) {
    address[] memory walletAddresses = new address[](numAddresses);

    for (uint256 i = 0; i < numAddresses; i++) {
        address wallet = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp + i)))));
        walletAddresses[i] = wallet;

        // Optional: Print the generated wallet address
        // You can comment out this line if you don't need the address printed
        console.log("Generated wallet address:", wallet);
    }

    return walletAddresses;
}
