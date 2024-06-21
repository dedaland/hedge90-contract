// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Hedge90.sol";
import "../src/ReentrancyAttack.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10**decimals());
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockTokenPriceManager {
    uint256 public tokenPrice = 100000000; // Price with 8 decimals

    function setTokenPrice(uint256 _tokenPrice) external {
        tokenPrice = _tokenPrice;
    }

    function getTokenPrice() external view returns (uint256) {
        return tokenPrice;
    }
}

contract TokenSaleTest is Test {
    using SafeERC20 for IERC20;

    TokenSale public tokenSale;
    MockERC20 public token;
    MockERC20 public usdt;
    MockTokenPriceManager public tokenPriceManager;
    address public owner;
    address public teamWallet;
    address public withdrawalAddress;
    address public buyer;

    function setUp() public {
        token = new MockERC20();
        usdt = new MockERC20();
        tokenPriceManager = new MockTokenPriceManager();

        owner = address(this);
        teamWallet = address(0x123);
        withdrawalAddress = address(0x456);
        buyer = address(0x789);

        tokenSale = new TokenSale(
            address(token),
            address(usdt),
            teamWallet,
            withdrawalAddress,
            address(tokenPriceManager)
        );

        token.mint(address(tokenSale), 1000000 * 10**token.decimals());
        usdt.mint(buyer, 100000 * 10**usdt.decimals());
        vm.startPrank(buyer);
        usdt.approve(address(tokenSale), type(uint256).max);
        token.approve(address(tokenSale), type(uint256).max);
        vm.stopPrank();
    }

    function testBuyTokens() public {
        uint256 amountToBuy = 5000000000; // 50 tokens
        uint256 tokenPrice = tokenPriceManager.getTokenPrice();
        uint256 baseCost = (tokenPrice * amountToBuy) / (10**tokenSale.tokenPriceDecimal());
        uint256 extraFee = (baseCost * 4) / 100;
        uint256 teamWalletShare = (baseCost * 10) / 100;
        uint256 user90HedgeShare = baseCost - teamWalletShare;
        uint256 totalCostWithFee = user90HedgeShare + teamWalletShare + extraFee;

        uint256 initialBuyerUsdtBalance = usdt.balanceOf(buyer);
        uint256 initialBuyerTokenBalance = token.balanceOf(buyer);
        uint256 initialTeamWalletUsdtBalance = usdt.balanceOf(teamWallet);

        vm.startPrank(buyer);
        tokenSale.buyTokens(amountToBuy);
        vm.stopPrank();

        assertEq(usdt.balanceOf(buyer), initialBuyerUsdtBalance - totalCostWithFee);
        assertEq(token.balanceOf(buyer), initialBuyerTokenBalance + amountToBuy);
        assertEq(usdt.balanceOf(teamWallet), initialTeamWalletUsdtBalance + teamWalletShare + extraFee);

        TokenSale.Purchase[] memory purchases = tokenSale.getPurchases(buyer);
        assertEq(purchases.length, 1);
        assertEq(purchases[0].amount, amountToBuy);
        assertEq(purchases[0].pricePerToken, tokenPrice);
        assertEq(purchases[0].USDTAmount, user90HedgeShare);
    }

    function testReturnTokens() public {
        uint256 amountToBuy = 5000000000; // 50 tokens
        uint256 tokenPrice = tokenPriceManager.getTokenPrice();
        uint256 baseCost = (tokenPrice * amountToBuy) / (10**tokenSale.tokenPriceDecimal());
        uint256 extraFee = (baseCost * 4) / 100;
        uint256 teamWalletShare = (baseCost * 10) / 100;
        uint256 user90HedgeShare = baseCost - teamWalletShare;
        uint256 totalCostWithFee = user90HedgeShare + teamWalletShare + extraFee;

        vm.startPrank(buyer);
        tokenSale.buyTokens(amountToBuy);
        vm.stopPrank();

        uint256 amountToReturn = 2500000000; // 25 tokens
        uint256 percentageOfHedge = (amountToReturn * 100) / amountToBuy;
        uint256 refundAmount = (user90HedgeShare * percentageOfHedge) / 100;

        uint256 initialBuyerUsdtBalance = usdt.balanceOf(buyer);
        uint256 initialBuyerTokenBalance = token.balanceOf(buyer);

        vm.startPrank(buyer);
        tokenSale.returnTokens(amountToReturn, 0);
        vm.stopPrank();

        assertEq(usdt.balanceOf(buyer), initialBuyerUsdtBalance + refundAmount);
        assertEq(token.balanceOf(buyer), initialBuyerTokenBalance - amountToReturn);

        TokenSale.Purchase[] memory purchases = tokenSale.getPurchases(buyer);
        assertEq(purchases[0].amount, amountToBuy - amountToReturn);
        assertEq(purchases[0].USDTAmount, user90HedgeShare - refundAmount);
    }

    function testWithdrawTokens() public {
        uint256 amountToWithdraw = 1000000000; // 10 tokens
        uint256 initialWithdrawalAddressTokenBalance = token.balanceOf(withdrawalAddress);

        tokenSale.withdrawTokens(amountToWithdraw);

        assertEq(token.balanceOf(withdrawalAddress), initialWithdrawalAddressTokenBalance + amountToWithdraw);
    }

    function testOnlyOwnerCanWithdraw() public {
        uint256 amountToWithdraw = 1000000000; // 10 tokens
        vm.prank(buyer);
        vm.expectRevert("Only owner can perform this action");
        tokenSale.withdrawTokens(amountToWithdraw);
    }

    function testReentrancyAttack() public {
        uint256 amountToBuy = 5000000000; // 50 tokens
        uint256 tokenPrice = tokenPriceManager.getTokenPrice();
        uint256 baseCost = (tokenPrice * amountToBuy) / (10**tokenSale.tokenPriceDecimal());
        uint256 extraFee = (baseCost * 4) / 100;
        uint256 teamWalletShare = (baseCost * 10) / 100;
        uint256 user90HedgeShare = baseCost - teamWalletShare;
        uint256 totalCostWithFee = user90HedgeShare + teamWalletShare + extraFee;

        // Buyer purchases tokens
        vm.startPrank(buyer);
        tokenSale.buyTokens(amountToBuy);
        vm.stopPrank();

        // Deploy reentrancy attack contract
        ReentrancyAttack attackContract = new ReentrancyAttack(
            address(tokenSale),
            address(token),
            address(usdt)
        );

        // Transfer tokens to attack contract
        vm.prank(buyer);
        token.transfer(address(attackContract), amountToBuy);

        uint256 amountToReturn = 2500000000; // 25 tokens

        // Attempt reentrancy attack
        vm.startPrank(buyer);
//        vm.expectRevert("ReentrancyGuard: reentrant call");
        vm.expectRevert();
        attackContract.attack(amountToReturn, 0);
        vm.stopPrank();
}
}
