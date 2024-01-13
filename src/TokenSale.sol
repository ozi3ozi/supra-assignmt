// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract TokenSale is Ownable {
    ERC20 public immutable tokenToSell;


    struct CrowdSale {
        // Max cap of the crowdsale
        uint maxCap;
        // Min contribution per buyer
        uint minPerBuyer;
        // Max contribution per buyer
        uint maxPerBuyer;
        uint startTime;
        uint endTime;
    }

    CrowdSale public preSale;
    CrowdSale public publicSale;

    constructor(address _tokenToSell, CrowdSale memory _preSale, CrowdSale memory _publicSale)
            Ownable(_msgSender()) {
        tokenToSell = ERC20(_tokenToSell);
        preSale = _preSale;
        publicSale = _publicSale;
    }


}