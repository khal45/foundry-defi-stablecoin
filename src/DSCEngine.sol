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

////////////////
// Imports  //
////////////////
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DscEngine
 * @author khal45
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg
 * This stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar Pegged
 * - Algorithmically stable
 *
 * It is similar to DAI if DAI had no governance, no fees and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point should the value of all collateral <= the $ backed value of all DSC.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming DSC, as well as
 * depositing & withdrawing collateral
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////
    // Errors  //
    ////////////////
    error DSCEngine__NeedsMoreThanZero(uint256 amountCollateral);
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength(
        uint256 tokenAddressesLength, uint256 priceFeedAddressesLength
    );
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsNotBelowMinimum();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__TotalDscMintedIsZero();

    ////////////////
    // Types  //
    ////////////////
    using OracleLib for AggregatorV3Interface;

    //////////////////////
    // State Variables  //
    //////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALT_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means a 10% bonus
    address[] public s_tokenAddresses;
    address[] public s_priceFeedAddresses;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //////////////////////
    // Events  //
    //////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ////////////////
    // Modifiers  //
    ////////////////
    /**
     * @dev Modifier to ensure the user does not deposit <= 0. Will revert if collateral is not > 0
     * @param amount The amount of collateral to deposit
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero(amount);
        }
        _;
    }

    /**
     * @dev Modifier to ensure only allowed tokens can be deposited. Will revert if the price feed of the token address does not exist
     * @param token Address of the token to be deposited
     */
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    ////////////////
    // Functions  //
    ////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        s_tokenAddresses = tokenAddresses;
        s_priceFeedAddresses = priceFeedAddresses;
        if (s_tokenAddresses.length != s_priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength(
                s_tokenAddresses.length, s_priceFeedAddresses.length
            );
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = s_priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////
    // External Functions  //
    /////////////////////////
    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDSCToMint The amount of DSC to be minted
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }
    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @notice Follows CEI patterns
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        /**
         * @notice The checks are happening in the modifiers
         */
        // Effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // Interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param tokenCollateralAddress The address of the token to be redeemed
     * @param amountCollateral The amount of collateral to to be redeemed
     * @param amountDSCToBurn The amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transaction
     * @notice Follows CEI patterns
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
    {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health factor
    }

    // In order to reddem collateral
    // 1. Health factor must be above 1 after collateral pulled
    /**
     * @param tokenCollateralAddress The address of the token to be redeemed
     * @param amountCollateral The amount of collateral to be redeemed
     * @notice Follows CEI patterns
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealtFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI
     * @param amountDSCToMint The amount of DSC to be minted.
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertIfHealtFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealtFactorIsBroken(msg.sender); // I don't think this would ever hit ...
    }

    /**
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The address of the user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve user's health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the user's funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work
     * @notice A known bug would be if a protocol were 100% or less collateralized, then we wouldn't be able to incentivize liquidators
     * For example if the price of the collateral plummeted before anyone could be liquidated
     * Follows CEI
     */
    // If someone is undercollateralized, we will pay you to liquidate them
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // Is user's health factor broken?
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALT_FACTOR) {
            revert DSCEngine__HealthFactorIsNotBelowMinimum();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // Give liquidator a 10% bonus
        // We should add a feature to implement in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealtFactorIsBroken(msg.sender);
    }

    ////////////////////////////////////////
    // Private & Internal View Functions  //
    ////////////////////////////////////////
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collaterlValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collaterlValueInUSD = getAccountCollateralValue(user);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
    }

    /**
     * @dev Low level internal function, do not call unless the function calling it is checking for health factors being broken
     */
    // Users shouldn't be able to burn more dsc than they've minted
    function _burnDSC(uint256 amountDSCToBurn, address onbehalfOf, address dscFrom) private {
        s_DSCMinted[onbehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDSCToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDSCToBurn);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC Minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    // 1. Check health factor (do they have enough collaterall)
    // 2. Revert if they don't
    function _revertIfHealtFactorIsBroken(address user) internal view {
        // My own tweak (if statement)
        if (s_DSCMinted[user] == 0) {
            return; // no DSC minted, no debt, always safe
        }
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALT_FACTOR) {
            revert DSCEngine__BreaksHealthFactor();
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /////////////////////////
    // Public And External View Functions  //
    /////////////////////////
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (
            /* uint80 roundId */
            ,
            int256 price,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = priceFeed.stalePriceCheckLatestRoundData();
        // (10e18 * 1e18) / (2000e8 * 1e10)
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // we are looping through the collateral tokens
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (
            /* uint80 roundId */
            ,
            int256 price,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = priceFeed.stalePriceCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDSCMinted, uint256 collaterlValueInUSD)
    {
        (totalDSCMinted, collaterlValueInUSD) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    // Getters
    function getPriceFeed(address token) external view returns (address priceFeed) {
        return s_priceFeeds[token];
    }

    function getPriceFeedAddress(uint256 index) external view returns (address priceFeedAddress) {
        return s_priceFeedAddresses[index];
    }

    function getPriceFeedAddressLength() external view returns (uint256) {
        return s_priceFeedAddresses.length;
    }

    function getCollateralToken(uint256 index) external view returns (address) {
        return s_collateralTokens[index];
    }

    function getCollateralTokensLength() external view returns (uint256) {
        return s_collateralTokens.length;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralDeposited(address user, address collateral) external view returns (uint256) {
        return s_collateralDeposited[user][collateral];
    }

    function getDscMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() public pure returns (uint256) {
        return MIN_HEALT_FACTOR;
    }
}
