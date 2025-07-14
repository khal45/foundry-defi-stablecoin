// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {console2} from "forge-std/console2.sol";

contract DecentralizedStableCoinTest is Test {
    // State variables
    DecentralizedStableCoin decentralizedStableCoinContract;
    DeployDecentralizedStableCoin deployer;
    uint256 public constant INVALID_AMOUNT = 0;
    uint256 public constant MINT_AMOUNT = 10;
    uint256 public constant BURN_AMOUNT = 20;
    address alice = makeAddr("alice");

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
        decentralizedStableCoinContract = deployer.run();
    }

    function testMintRevertsIfAddressIsZeroAdrress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DecentralizedStableCoin.DecentralizedStableCoin__CantMintToZeroAddress.selector, address(0)
            )
        );
        decentralizedStableCoinContract.mint(address(0), MINT_AMOUNT);
    }

    function testMintRevertsIfValueLessThanZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector, INVALID_AMOUNT
            )
        );
        decentralizedStableCoinContract.mint(address(this), INVALID_AMOUNT);
    }

    function testBurnRevertsIfValueIsLessThanZero() public {
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector, INVALID_AMOUNT
            )
        );
        decentralizedStableCoinContract.burn(INVALID_AMOUNT);
    }

    function testBurnRevertsIfBalanceIsLessThanValue() public {
        decentralizedStableCoinContract.mint(address(this), MINT_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector, MINT_AMOUNT
            )
        );
        decentralizedStableCoinContract.burn(BURN_AMOUNT);
    }
}
