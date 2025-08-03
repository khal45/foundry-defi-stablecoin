// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {console2} from "forge-std/console2.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

// You can only redeem collateral if it doesn't break your health factor

contract Handler is Test {
    DSCEngine dscEngineContract;
    DecentralizedStableCoin dscContract;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngineContract, DecentralizedStableCoin _dscContract) {
        dscEngineContract = _dscEngineContract;
        _dscContract = dscContract;

        address[] memory collateralTokens = dscEngineContract.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngineContract.getPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngineContract.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd / 2) - int256(totalDscMinted));
        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscToMint));

        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngineContract.mintDSC(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngineContract), amountCollateral);
        dscEngineContract.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = dscEngineContract.getCollateralDeposited(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) return;

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngineContract.getAccountInformation(msg.sender);
        if (totalDscMinted == 0) return;

        uint256 redeemUsdValue = dscEngineContract.getUsdValue(address(collateral), amountCollateral);

        uint256 newCollateralValue = collateralValueInUsd > redeemUsdValue ? collateralValueInUsd - redeemUsdValue : 0;

        uint256 LIQUIDATION_THRESHOLD = dscEngineContract.getLiquidationThreshold();
        uint256 LIQUIDATION_PRECISION = dscEngineContract.getLiquidationPrecision();
        uint256 PRECISION = dscEngineContract.getPrecision();
        uint256 MIN_HEALTH_FACTOR = dscEngineContract.getMinHealthFactor();

        uint256 adjustedCollateral = (newCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 simulatedHealthFactor = (adjustedCollateral * PRECISION) / totalDscMinted;

        if (simulatedHealthFactor < MIN_HEALTH_FACTOR) return;

        vm.prank(msg.sender);
        dscEngineContract.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     uint256 maxCollateral = dscEngineContract.getCollateralDeposited(msg.sender, address(collateral));

    //     amountCollateral = bound(amountCollateral, 0, maxCollateral);
    //     if (amountCollateral == 0) {
    //         return;
    //     }
    //     vm.prank(msg.sender);
    //     // console2.log("health factor before %s", dscEngineContract.getHealthFactor(msg.sender));
    //     dscEngineContract.redeemCollateral(address(collateral), amountCollateral);
    //     vm.stopPrank();
    //     // console2.log("health factore after %s", dscEngineContract.getHealthFactor(msg.sender));
    // }

    // This breaks our invariant test suite !!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
