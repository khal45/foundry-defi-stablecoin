// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";

contract DeployDSC is Script {
    function run() external returns (DecentralizedStableCoin, DSCEngine) {
        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(msg.sender);
        // DSCEngine engine = new DSCEngine()
        vm.stopBroadcast();
    }
}
