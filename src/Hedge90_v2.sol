// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.24;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { TokenPriceManager } from "./TokenPriceManager.sol";

contract TokenSale is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public owner;
    IERC20 public token;
    IERC20 public USDT;
    TokenPriceManager public tokenPriceManager;

    uint256 public tokenPriceDecimal = 8;
    address public teamWallet;
    address public withdrawalAddress;

    struct Purchase {
        uint256 amount;
        uint256 pricePerToken;
        uint256 USDTAmount;
    }

    mapping(address => Purchase[]) public purchases;

    constructor(
        address _token,
        address _USDT,
        address _teamWallet,
        address _withdrawalAddress,
        address _tokenPriceManager
    ) {
        owner = msg.sender;
        token = IERC20(_token);
        USDT = IERC20(_USDT);
        teamWallet = _teamWallet;
        withdrawalAddress = _withdrawalAddress;
        tokenPriceManager = TokenPriceManager(_tokenPriceManager);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    function getPurchases(address user) public view returns (Purchase[] memory) {
        return purchases[user];
    }

    function buyTokens(uint256 USDTAmount) external nonReentrant {
        require(USDTAmount >= 5000000000, "Minimum purchase is 50 USDT");

        uint256 tokenPrice = tokenPriceManager.getTokenPrice();
        uint256 amount = (USDTAmount * (10 ** tokenPriceDecimal)) / tokenPrice;
        uint256 baseCost = (tokenPrice * amount) / (10 ** tokenPriceDecimal);
        uint256 extraFee = (baseCost * 4) / 100;
        uint256 teamWalletShare = (baseCost * 10) / 100;
        uint256 user90HedgeShare = baseCost - teamWalletShare;

        uint256 totalCostWithFee = user90HedgeShare + teamWalletShare + extraFee;

        require(USDT.balanceOf(msg.sender) >= totalCostWithFee, "Insufficient USDT balance");
        require(USDT.allowance(msg.sender, address(this)) >= totalCostWithFee, "USDT allowance too low");
        require(token.balanceOf(address(this)) >= amount, "Insufficient contract token balance");

        USDT.safeTransferFrom(msg.sender, address(this), totalCostWithFee);

        purchases[msg.sender].push(Purchase(amount, tokenPrice, user90HedgeShare));

        USDT.safeTransfer(teamWallet, teamWalletShare + extraFee);

        token.safeTransfer(msg.sender, amount);

    }

    function returnTokens(uint256 amount, uint256 _index) external nonReentrant {
        require(token.balanceOf(msg.sender) >= amount, "Insufficient TOKEN balance");
        require(token.allowance(msg.sender, address(this)) >= amount, "TOKEN allowance too low");
        Purchase memory purchase = purchases[msg.sender][_index];
        require(purchase.amount >= amount, "Not enough tokens purchased for the amount being returned");
        uint256 percentageOfHedge = (amount * 100) / purchase.amount;
        uint256 refundAmount = (purchase.USDTAmount * percentageOfHedge) / 100;

        require(USDT.balanceOf(address(this)) >= refundAmount, "Insufficient USDT for refund");
        require(refundAmount <= purchase.USDTAmount, "Refund exceeds purchase amount");

        token.safeTransferFrom(msg.sender, address(this), amount);
        USDT.safeTransfer(msg.sender, refundAmount);

        purchases[msg.sender][_index].amount -= amount;
        purchases[msg.sender][_index].USDTAmount -= refundAmount;

    }

    function cancelHedge90(uint256 _index) external nonReentrant {
        require(_index < purchases[msg.sender].length, "Invalid index");
        // Ensure the contract has enough balance to make the transfers

        Purchase memory purchase = purchases[msg.sender][_index];
        uint256 userLockedAmount = purchase.USDTAmount;
        require(USDT.balanceOf(address(this)) >= userLockedAmount, "Insufficient USDT balance in contract");


        // Calculate 85% of the locked amount(90% is user's) to transfer to the team wallet
        uint256 teamWalletAmount = (userLockedAmount * 85 * 100) / 90 / 100;

        // Calculate 5% of the locked amount(90% is user's) to refund to the user
        uint256 userRefundAmount = userLockedAmount - teamWalletAmount;

        // Update the user's locked amount
        purchases[msg.sender][_index].USDTAmount = 0;

        // Transfer 85% to the team wallet
        USDT.safeTransfer(teamWallet, teamWalletAmount);

        // Transfer 5% back to the user
        USDT.safeTransfer(msg.sender, userRefundAmount);

    }

    function withdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(token.balanceOf(address(this)) >= amount, "Insufficient token balance in contract");
        token.safeTransfer(withdrawalAddress, amount);
    }
}