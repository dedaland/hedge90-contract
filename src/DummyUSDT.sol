// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyUSDT is ERC20 {
    constructor() ERC20("Tether USDT", "USDT") {

        _mint(msg.sender, 1000000000 * (10 ** uint256(decimals())));
    }
    function decimals() override public pure returns (uint8) {
        return 18;
    }
}