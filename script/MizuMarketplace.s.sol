// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/MizuMarketplace.sol";
import "../src/DLT.sol";
import "../src/MockUSDC.sol";

contract MizuMarketplaceScript is Script {
    MockUSDC public usdc;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy DLT contract
        DLT dlt = new DLT();
        console.log("DLT deployed at:", address(dlt));

        // Deploy USDC contract
        usdc = new MockUSDC();
        console.log("USDC deployed at:", address(usdc));

        // Deploy MizuMarketplace with DLT address and USDC address
        MizuMarketplace marketplace = new MizuMarketplace(
            address(dlt),
            address(usdc)
        );
        console.log("MizuMarketplace deployed to:", address(marketplace));

        // Grant minting rights to marketplace
        dlt.setApprovalForAll(address(marketplace), true);
        console.log("Granted minting rights to marketplace");

        // Log addresses in env format for easy copying
        console.log("--------------------");
        console.log("DLT_ADDRESS =", address(dlt));
        console.log("MARKETPLACE_ADDRESS =", address(marketplace));
        console.log("--------------------");

        vm.stopBroadcast();
    }
}
