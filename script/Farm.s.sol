// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Farm.sol";

contract DeployFarm is Script {
    function run() external {
        // Load deployer private key (set in .env or CLI)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Developer wallet to receive fees
        address developerWallet = vm.envAddress("DEVELOPER_WALLET");

        // Start broadcasting using the deployer's private key
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        FarmEscrow escrow = new FarmEscrow(developerWallet);

        console.log("FarmEscrow deployed at:", address(escrow));

        vm.stopBroadcast();
    }
}



