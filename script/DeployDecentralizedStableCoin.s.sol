// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {console2} from "forge-std/console2.sol";

contract DeployDecentralizedStableCoin is Script {
    // State variables
    DecentralizedStableCoin decentralizedStableCoinContract;

    function run() external returns (DecentralizedStableCoin) {
        vm.startBroadcast();
        decentralizedStableCoinContract = new DecentralizedStableCoin();
        vm.stopBroadcast();
        return decentralizedStableCoinContract;
    }
}
