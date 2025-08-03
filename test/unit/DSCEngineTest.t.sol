// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test {
    // State variables
    DeployDSC deployer;
    DecentralizedStableCoin dscContract;
    DSCEngine dscEngineContract;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant ZERO_AMOUNT = 0;
    uint256 public constant VALID_AMOUNT = 20;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant LIQUIDATOR_COLLATERAL = 30 ether;
    uint256 public constant STARTING_USER_ERC20_BALANCE = 10 ether;
    uint256 public constant STARTING_LIQUIDATOR_ERC20_BALANCE = 30 ether;
    uint256 public constant DSC_AMOUNT_TO_MINT = 5000e18;
    uint256 public constant DSC_AMOUNT_TO_BURN = 2000e18;
    uint256 public constant DSC_AMOUNT_TO_MINT_THAT_BREAKS_HEALTH_FACTOR = 15000e18;
    uint256 public constant AMOUNT_COLLATERAL_TO_REDEEM = 5 ether;
    uint256 public constant DEBT_TO_COVER = 1000e18;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    // Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (dscContract, dscEngineContract, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_USER_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_LIQUIDATOR_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector,
                tokenAddresses.length,
                priceFeedAddresses.length
            )
        );

        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dscContract));
    }

    function testPriceFeedsMappingAndCollateralTokensAreUpdatedCorrectly() public {
        // Arrange
        uint256 tokenAddressesLength = dscEngineContract.getPriceFeedAddressLength();
        // Act / Assert
        for (uint256 i = 0; i < tokenAddressesLength; i++) {
            address tokenAddress = dscEngineContract.s_tokenAddresses(i);
            address collateralToken = dscEngineContract.getCollateralToken(i);
            address priceFeed = dscEngineContract.getPriceFeed(tokenAddress);
            address savedPriceFeed = dscEngineContract.getPriceFeedAddress(i);
            assertEq(priceFeed, savedPriceFeed);
            assertEq(collateralToken, tokenAddress);
        }
    }
    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public {
        /**
         * Call getusd with weth and amount
         * Log to the console
         */
        uint256 ethAmount = 15 ether;
        // 15e18 * 2000/Eth = 30,000e18
        uint256 expectedUsdValue = 30000e18;
        uint256 actualUsdValue = dscEngineContract.getUsdValue(weth, ethAmount);
        assertEq(expectedUsdValue, actualUsdValue);
    }

    function testGetTokenAmountFromUsd() public {
        // Arrange
        uint256 usdAmountInWei = 10e18;
        uint256 expectedTokenAmount = 5e15;
        uint256 actualTokenAmount = dscEngineContract.getTokenAmountFromUsd(weth, usdAmountInWei);
        assertEq(expectedTokenAmount, actualTokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testDepositCollateralRevertsIfAmountIsZero() public {
        // Arrange
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector, ZERO_AMOUNT));
        dscEngineContract.depositCollateral(weth, ZERO_AMOUNT);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        // Arrange
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        // Act / Assert
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(ranToken)));
        dscEngineContract.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        dscEngineContract.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        // Arrange
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngineContract.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngineContract.getTokenAmountFromUsd(weth, collateralValueInUsd);
        // Act / Assert
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCollateralDepositedIsUpdatedCorrectly() public depositedCollateral {
        // Arrange
        uint256 collateralDeposited = dscEngineContract.getCollateralDeposited(USER, weth);
        // Act / Assert
        assertEq(collateralDeposited, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralEmitsAnEvent() public {
        // Arrange
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscEngineContract.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/
    modifier dscMinted() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        dscEngineContract.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testMintDscRevertsIfAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector, ZERO_AMOUNT));
        dscEngineContract.mintDSC(ZERO_AMOUNT);
    }

    function testDscMintedIsUpdatedCorrectly() public dscMinted {
        uint256 amountDscMinted = dscEngineContract.getDscMinted(USER);
        assertEq(amountDscMinted, DSC_AMOUNT_TO_MINT);
    }

    function testMintDscRevertsIfHealthFactorIsBroken() public {
        // Arrange
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        dscEngineContract.depositCollateral(weth, AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dscEngineContract.mintDSC(DSC_AMOUNT_TO_MINT_THAT_BREAKS_HEALTH_FACTOR);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                 DEPOSIT COLLATERAL AND MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositCollateralAndMintDSC() public {
        /**
         * Deposit collateral and mint dsc
         * Assert collateral deposited is correct
         * Assert dsc minted is correct
         */
        // Arrange
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        // Act
        dscEngineContract.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_AMOUNT_TO_MINT);
        uint256 collateralDeposited = dscEngineContract.getCollateralDeposited(USER, weth);
        uint256 amountDscMinted = dscEngineContract.getDscMinted(USER);
        // Assert
        assertEq(collateralDeposited, AMOUNT_COLLATERAL);
        assertEq(amountDscMinted, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/
    function testDscMintedReducesByAmountToBeBurned() public dscMinted {
        // Arrange
        vm.startPrank(USER);
        uint256 dscMintedBeforeBurn = dscEngineContract.getDscMinted(USER);
        dscContract.approve(address(dscEngineContract), DSC_AMOUNT_TO_MINT);
        // Act
        dscEngineContract.burnDSC(DSC_AMOUNT_TO_BURN);
        uint256 dscMintedAfterBurn = dscEngineContract.getDscMinted(USER);
        // Assert
        assertEq(dscMintedAfterBurn, dscMintedBeforeBurn - DSC_AMOUNT_TO_BURN);
        vm.stopPrank();
    }

    function testBurnDscBurnsTheDsc() public dscMinted {
        // Arrange
        vm.startPrank(USER);
        dscContract.approve(address(dscEngineContract), DSC_AMOUNT_TO_MINT);
        // Act
        dscEngineContract.burnDSC(DSC_AMOUNT_TO_BURN);
        // Assert
        assertEq(address(dscEngineContract).balance, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRedeemCollateralRevertsIfCollateralEqualsZero() public depositedCollateral {
        // Arrange
        vm.startPrank(USER);
        // Act / Assert
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector, ZERO_AMOUNT));
        dscEngineContract.redeemCollateral(weth, ZERO_AMOUNT);
        vm.stopPrank();
    }

    function testRedeemCollateralReducesTheCollateralDeposited() public depositedCollateral {
        // Arrange
        vm.startPrank(USER);
        // Act
        uint256 collateralDepositedBeforeRedeemingCollateral = dscEngineContract.getCollateralDeposited(USER, weth);
        dscEngineContract.redeemCollateral(weth, AMOUNT_COLLATERAL_TO_REDEEM);
        uint256 collateralDepositedAfterRedeemingCollateral = dscEngineContract.getCollateralDeposited(USER, weth);
        assertEq(
            collateralDepositedAfterRedeemingCollateral,
            collateralDepositedBeforeRedeemingCollateral - AMOUNT_COLLATERAL_TO_REDEEM
        );
        vm.stopPrank();
    }

    function testRedeemCollateralEmitsAnEvent() public depositedCollateral {
        // Arrange
        vm.startPrank(USER);
        // Act / Assert
        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL_TO_REDEEM);
        dscEngineContract.redeemCollateral(weth, AMOUNT_COLLATERAL_TO_REDEEM);
        vm.stopPrank();
    }

    function testRedeemCollateralTransfersCollateralToUser() public depositedCollateral {
        // Arrange
        vm.startPrank(USER);
        uint256 userStartingBalance = ERC20Mock(weth).balanceOf(USER);
        // Act
        dscEngineContract.redeemCollateral(weth, AMOUNT_COLLATERAL_TO_REDEEM);
        uint256 userEndingBalance = ERC20Mock(weth).balanceOf(USER);
        // Assert
        assertEq(userEndingBalance, userStartingBalance + AMOUNT_COLLATERAL_TO_REDEEM);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    REDEEM COLLATERAL FOR DSC TESTS
    //////////////////////////////////////////////////////////////*/
    // Come back to this test, you aint testing shit
    function testRedeemCollateralForDSC() public dscMinted {
        /**
         * Call the function
         * Assert dsc was burned
         * Assert collateral was redeemed
         */
        // Arrange
        vm.startPrank(USER);
        // should redeem 5 ether and burn the DSC equivalent of 5 ether
        dscContract.approve(address(dscEngineContract), 5 ether);
        dscEngineContract.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL_TO_REDEEM, 5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT INFORMATION TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetAccountInformation() public {
        // Arrange
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        dscEngineContract.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngineContract.mintDSC(DSC_AMOUNT_TO_MINT);
        // Act
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngineContract.getAccountInformation(USER);
        uint256 amountCollateralInUsd = dscEngineContract.getUsdValue(weth, AMOUNT_COLLATERAL);
        // Assert
        assertEq(totalDSCMinted, DSC_AMOUNT_TO_MINT);
        assertEq(collateralValueInUSD, amountCollateralInUsd);
    }

    /*//////////////////////////////////////////////////////////////
                            LIQUIDATE TESTS
    //////////////////////////////////////////////////////////////*/
    modifier liquidatorDscMinted() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        dscEngineContract.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngineContract), LIQUIDATOR_COLLATERAL);
        dscEngineContract.depositCollateralAndMintDSC(weth, LIQUIDATOR_COLLATERAL, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();
        int256 newPrice = 900e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);
        _;
    }

    function testLiquidateRevertsIfHealthFactorIsAboveMin() public dscMinted {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsNotBelowMinimum.selector);
        dscEngineContract.liquidate(weth, USER, DEBT_TO_COVER);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfDebtToCoverIsZero() public dscMinted {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector, ZERO_AMOUNT));
        dscEngineContract.liquidate(weth, USER, ZERO_AMOUNT);
        vm.stopPrank();
    }

    function testCanLiquidateAfterHealthFactorBreaks() public liquidatorDscMinted {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngineContract), DSC_AMOUNT_TO_MINT);
        dscContract.approve(address(dscEngineContract), DSC_AMOUNT_TO_MINT);
        dscEngineContract.liquidate(address(weth), USER, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testLiquidatorHealthFactorMustNotBeBrokenAfterLiquidation() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        dscEngineContract.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngineContract), AMOUNT_COLLATERAL);
        dscEngineContract.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();

        int256 newPrice = 900e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngineContract), DSC_AMOUNT_TO_MINT);
        dscContract.approve(address(dscEngineContract), DSC_AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dscEngineContract.liquidate(address(weth), USER, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    GETACCOUNTCOLLATERALVALUE TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetAccountCollateralValue() public depositedCollateral {
        vm.startPrank(USER);
        uint256 collateralTokenength = dscEngineContract.getCollateralTokensLength();
        uint256 expectedCollateralValue;
        for (uint256 i = 0; i < collateralTokenength; i++) {
            address token = dscEngineContract.getCollateralToken(i);
            uint256 amount = dscEngineContract.getCollateralDeposited(USER, token);

            assertEq(token, dscEngineContract.getCollateralToken(i));
            assertEq(amount, dscEngineContract.getCollateralDeposited(USER, token));

            expectedCollateralValue += dscEngineContract.getUsdValue(token, amount);
        }

        uint256 actual = dscEngineContract.getAccountCollateralValue(USER);
        assertEq(expectedCollateralValue, actual, "total collateral value mismatch");
        vm.stopPrank();
    }
}
