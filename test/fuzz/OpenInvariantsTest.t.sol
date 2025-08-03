// // What are our invariants
// // 1. The total supply of DSC should be less than the total value of collateral
// // 2. Getter view functions should never revert <- evergreen invariant

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// // Imports
// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {console2} from "forge-std/console2.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
// import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     // State variables
//     DeployDSC deployer;
//     DecentralizedStableCoin dscContract;
//     DSCEngine dscEngineContract;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         // deployer = new DeployDSC();
//         // (dscContract, dscEngineContract, config) = deployer.run();
//         // (,, weth, wbtc) = config.activeNetworkConfig();
//         // targetContract(address(dscEngineContract));
//         deployer = new DeployDSC();
//         (dscContract, dscEngineContract, config) = deployer.run();
//         (,, weth, wbtc) = config.activeNetworkConfig();
//         targetContract(address(dscEngineContract));
//     }

//     // INTIAL PATRICK'S CODE -> WAS FAILING WITH `FAIL: failed to set up invariant testing environment`
//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         // get value of all collateral in the protocol
//         // compare it to all the debt (dsc)
//         uint256 totalSupply = dscContract.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngineContract));
//         uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dscEngineContract));

//         uint256 wethValue = dscEngineContract.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dscEngineContract.getUsdValue(wbtc, totalBtcDeposited);
//         assert(wethValue + wbtcValue >= totalSupply);
//     }

//     // // FIXED CODE FROM `https://github.com/Cyfrin/foundry-full-course-cu/discussions/4128`
//     // function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
//     //     uint256 totalSupply = dscContract.totalSupply();
//     //     uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngineContract));
//     //     uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dscEngineContract));

//     //     console2.log("Total DSC Supply:", totalSupply);
//     //     console2.log("Total WETH Deposited:", totalWethDeposited);
//     //     console2.log("Total BTC Deposited:", totalBtcDeposited);

//     //     // Check totalWethDeposited == 0 before calling getUSDValue()
//     //     if (totalWethDeposited == 0 || totalBtcDeposited == 0) {
//     //         // If 0: Skip USD calculation and assert that totalSupply must also be 0
//     //         console2.log("No WETH or BTC deposited, skipping USD value calculation");
//     //         assert(totalSupply == 0);
//     //         // If > 0: Continue with normal flow
//     //         return;
//     //     }

//     //     uint256 wethValueInUsd = dscEngineContract.getUsdValue(weth, totalWethDeposited);
//     //     uint256 btcValueInUsd = dscEngineContract.getUsdValue(wbtc, totalWethDeposited);
//     //     console2.log("WETH Value in USD:", wethValueInUsd);
//     //     console2.log("BTC Value in USD:", btcValueInUsd);

//     //     assertGt(wethValueInUsd + btcValueInUsd, totalSupply);
//     // }
// }
