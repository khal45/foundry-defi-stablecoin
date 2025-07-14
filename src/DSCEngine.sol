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
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
    error DSCENGINE__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    //////////////////////
    // State Variables  //
    //////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant MIN_HEALT_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //////////////////////
    // Events  //
    //////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength(
                tokenAddresses.length, priceFeedAddresses.length
            );
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////
    // External Functions  //
    /////////////////////////
    function depositCollateralAndMintDSC() external {}
    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @notice Follows CEI patterns
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        /**
         * @notice The checks are happening in the modifiers
         */
        // Effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // Interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCENGINE__TransferFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /**
     * @notice Follows CEI
     * @param amountDSCToMint The amount of DSC to be minted.
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDSCToMint) external moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertIfHealtFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

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

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC Minted
        // total collateral value
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        // $1000 ETH / 100 DSC
        // 1000 * 50 / 100 -> 500
        // 500 / 600 -> 5 > 1
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    // 1. Check health factor (do they have enough collaterall)
    // 2. Revert if they don't
    function _revertIfHealtFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALT_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////
    // Public And External View Functions  //
    /////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
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
        ) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
