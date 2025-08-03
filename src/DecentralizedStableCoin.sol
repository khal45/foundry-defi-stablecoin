// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author khal45
 * Collateral: Exogenous (ETH or BTC)
 * Minting: ALgorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the contract meant to be governed by DSCEngine. This is just the ERC20 implementation of our stable coin system.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    // Errors
    error DecentralizedStableCoin__AmountMustBeMoreThanZero(uint256 value);
    error DecentralizedStableCoin__BurnAmountExceedsBalance(uint256 balance);
    error DecentralizedStableCoin__CantMintToZeroAddress(address account);

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable() {}

    function burn(uint256 value) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        // Checks
        if (value <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero(value);
        }

        if (balance < value) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance(balance);
        }

        // Effects
        super.burn(value);
    }

    function mint(address account, uint256 value) public onlyOwner returns (bool) {
        // Checks
        if (account == address(0)) {
            revert DecentralizedStableCoin__CantMintToZeroAddress(address(0));
        }

        if (value <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero(value);
        }

        // Effects
        _mint(account, value);
        return true;
    }
}
