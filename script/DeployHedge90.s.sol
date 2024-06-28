// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { TokenSale } from "../src/Hedge90_v2.sol";
import { MyUSDT } from "../src/DummyUSDT.sol";
import { DedaCoin } from "../src/DummyDeDa.sol";
import { TokenPriceManager } from "../src/TokenPriceManager.sol";

contract DeployHedge90 is Script {
    function run() external returns(TokenSale, TokenPriceManager, MyUSDT, DedaCoin) {
        address DummyACC0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address DummyACC1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address DummyACC2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        address [] memory holders = new address[](1);
        holders[0] = DummyACC0;
        uint256 [] memory shares = new uint256[](1);
        shares[0] = 100;
        vm.startBroadcast();
        TokenPriceManager tokenpricemanager = new TokenPriceManager(
            85_000_000_000_000_000_000
        );
        MyUSDT usdt = new MyUSDT();
        DedaCoin dedacoin = new DedaCoin("DedaCoin", "DEDA", holders, shares);

        TokenSale tokensale = new TokenSale(
            address(dedacoin),
            address(usdt),
            DummyACC1, // team wallet
            DummyACC2, // withdraw wallet
            address(tokenpricemanager)
        );
        vm.stopBroadcast();
        return (tokensale, tokenpricemanager, usdt, dedacoin);
    }
}
