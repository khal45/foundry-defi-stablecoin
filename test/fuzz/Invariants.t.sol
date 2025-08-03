// What are our invariants
// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    // State variables
    DeployDSC deployer;
    DecentralizedStableCoin dscContract;
    DSCEngine dscEngineContract;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dscContract, dscEngineContract, config) = deployer.run();
        (,, weth, wbtc) = config.activeNetworkConfig();
        // targetContract(address(dscEngineContract));
        handler = new Handler(dscEngineContract, dscContract);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get value of all collateral in the protocol
        // compare it to all the debt (dsc)
        uint256 totalSupply = dscContract.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngineContract));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dscEngineContract));

        uint256 wethValue = dscEngineContract.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngineContract.getUsdValue(wbtc, totalBtcDeposited);
        assert(wethValue + wbtcValue >= totalSupply);
        console2.log("weth value %s, wbtc value %s, total supply %s", wethValue, wbtcValue, totalSupply);
        console2.log("times mint called", handler.timesMintIsCalled());
    }

    // function invariant_gettersShouldNotRevert() public view {
    //     dscEngineContract.getPriceFeedAddressLength();
    //     dscEngineContract.getCollateralTokens();
    //     dscEngineContract.getLiquidationBonus();
    //     dscEngineContract.getPrecision();
    //     dscEngineContract.getAdditionalFeedPrecision();
    //     dscEngineContract.getLiquidationThreshold();
    //     dscEngineContract.getLiquidationPrecision();
    //     dscEngineContract.getMinHealthFactor();
    // }
}
