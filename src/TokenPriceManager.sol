// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TokenPriceManager {
    address public owner;
    uint256 public tokenPrice;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    constructor(uint256 initialPrice) {
        owner = msg.sender;
        tokenPrice = initialPrice;
    }

    function setTokenPrice(uint256 newPrice) external onlyOwner {
        tokenPrice = newPrice;
    }

    function getTokenPrice() external view returns (uint256) {
        return tokenPrice;
    }
}
