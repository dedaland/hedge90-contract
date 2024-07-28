// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TokenPriceManager} from "./TokenPriceManager.sol";

contract TokenSale is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public owner;
    IERC20 public token;
    IERC20 public USDT;
    TokenPriceManager public tokenPriceManager;

    uint256 public tokenPriceDecimal = 8;
    address public teamWallet;
    address public withdrawalAddress;

    uint256 public buyerDiscountPercent = 1; // 5% discount for the buyer
    uint256 public referralPercent = 2; // 3% referral reward

    struct Purchase {
        uint256 amount;
        uint256 pricePerToken;
        uint256 USDTAmount;
    }

    mapping(address => Purchase[]) public purchases;

    struct Influencer {
        string name;
        bool isActive;
    }

    // Mapping to store influencers
    mapping(address => Influencer) public influencers;

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

    function setDiscounts(uint256 _buyerDiscountPercent, uint256 _referralPercent) external onlyOwner {
        buyerDiscountPercent = _buyerDiscountPercent;
        referralPercent = _referralPercent;
    }

    function normalBuy(uint256 USDTAmount, address inviter) external nonReentrant {
        require(USDTAmount >= 5_000_000_000_000_000_000, "Minimum purchase is 50 USDT");

        uint256 tokenPrice = tokenPriceManager.getTokenPrice();
        uint256 tokenAmount = (USDTAmount * (10 ** tokenPriceDecimal)) / tokenPrice;

        uint256 buyerDiscount = (tokenAmount * buyerDiscountPercent) / 100;
        uint256 finalAmount = tokenAmount + buyerDiscount;
        uint256 referralAmount = 0;
        if (inviter != address(0)) {
            referralAmount = (USDTAmount * referralPercent) / 100;
        }

        require(USDT.balanceOf(msg.sender) >= USDTAmount, "Insufficient USDT balance");
        require(USDT.allowance(msg.sender, address(this)) >= USDTAmount, "USDT allowance too low");
        require(token.balanceOf(address(this)) >= finalAmount, "Insufficient contract token balance");

        USDT.safeTransferFrom(msg.sender, address(this), USDTAmount);
        USDT.safeTransfer(teamWallet, USDTAmount - referralAmount);

        if (inviter != address(0)) {
            USDT.safeTransfer(inviter, referralAmount);
        } else {
            USDT.safeTransfer(teamWallet, referralAmount); // If no inviter, send referral amount to team wallet
        }

        token.safeTransfer(msg.sender, finalAmount);
    }

    function buyTokens(uint256 USDTAmount, address inviter) external nonReentrant {
        require(USDTAmount >= 5_000_000_000_000_000_000, "Minimum purchase is 50 USDT");

        uint256 tokenPrice = tokenPriceManager.getTokenPrice();
        uint256 tokenAmount = (USDTAmount * (10 ** tokenPriceDecimal)) / tokenPrice;
        uint256 extraFee = (tokenAmount * 4) / 100;
        if (inviter != address(0)) {
            extraFee = (tokenAmount * (4 - buyerDiscountPercent)) / 100; // 4% fee in tokens
        }
        uint256 finalAmount = tokenAmount - extraFee; // amount after deducting 4% fee

        uint256 teamWalletShare = (USDTAmount * 14) / 100; // 14% of USDTAmount (10% + 4%)
        uint256 userNetUSDT = USDTAmount - teamWalletShare; // remaining 86% for user's token purchase

        require(USDT.balanceOf(msg.sender) >= USDTAmount, "Insufficient USDT balance");
        require(USDT.allowance(msg.sender, address(this)) >= USDTAmount, "USDT allowance too low");
        require(token.balanceOf(address(this)) >= finalAmount, "Insufficient contract token balance");

        USDT.safeTransferFrom(msg.sender, address(this), USDTAmount);
        uint256 referralAmount = 0;
        if(inviter != address(0)) {
            referralAmount = (USDTAmount * referralPercent) / 100;
        }
        USDT.safeTransfer(teamWallet, teamWalletShare - referralAmount);
        if(inviter != address(0)) {
            USDT.safeTransfer(inviter, referralAmount);
        }
        purchases[msg.sender].push(Purchase(finalAmount, tokenPrice, userNetUSDT));

        token.safeTransfer(msg.sender, finalAmount);
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

        Purchase memory purchase = purchases[msg.sender][_index];
        uint256 userLockedAmount = purchase.USDTAmount;
        require(USDT.balanceOf(address(this)) >= userLockedAmount, "Insufficient USDT balance in contract");

        uint256 teamWalletAmount = (userLockedAmount * 85 * 100) / 90 / 100;
        uint256 userRefundAmount = userLockedAmount - teamWalletAmount;

        purchases[msg.sender][_index].USDTAmount = 0;

        USDT.safeTransfer(teamWallet, teamWalletAmount);
        USDT.safeTransfer(msg.sender, userRefundAmount);
    }

    function addInfluencer(address _addr, string memory _name) public onlyOwner{
        require(_addr != address(0), "Influencer address cannot be the zero address");
        require(bytes(_name).length > 0, "Influencer name cannot be empty");
        influencers[_addr] = Influencer(_name, true);
    }

    // Function to remove (disable) an influencer
    function removeInfluencer(address _addr) public onlyOwner{
        require(_addr != address(0), "Influencer address cannot be the zero address");
        require(bytes(influencers[_addr].name).length > 0, "Influencer does not exist");

        influencers[_addr].isActive = false;
    }

    // Function to check if an address is an active influencer
    function isInfluencer(address _addr) public view returns (bool) {
        return influencers[_addr].isActive;
    }

    function withdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(token.balanceOf(address(this)) >= amount, "Insufficient token balance in contract");
        token.safeTransfer(withdrawalAddress, amount);
    }
}