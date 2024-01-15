// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Capped } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";


/**
 * Design choices:
 * - I used the openzeppelin contracts for their reliability.
 * - The SupraToken contract used is capped, mintable, and has access control based on roles.
 *  The MINT_ROLE allows the TokenSeller contract to mint tokens and send them directly to the buyer.
 *  No Need for contract owner to give allowances.
 */
contract SupraToken is ERC20Capped, Ownable, AccessControl {
    // Used for TokenSale during preSale and publicSale
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor (string memory _name, string memory _symbol, uint256 _maxSupply, address _owner) 
            ERC20Capped(_maxSupply) ERC20(_name, _symbol) Ownable(_owner) {
    }

    function mint(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }
}