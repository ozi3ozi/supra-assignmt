// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SupraToken } from "./SupraToken.sol";

/**
 * Design choices:
 * - Because the presale and public sale share the same properties. I used a struct called Crowdsale for both.
 * - The Crowdsale.buyers array is used for the refunding process.
 * - the mappings weiReceivedPerBuyerPresale and weiReceivedPerBuyerPublicSale are used for:
 *      # eligibility to purchase when buyer is doing multiple buys
 *      # checking if an address is a buyer
 *      # refunding
 * - When the SupraToken is deployed it gives MINTER_ROLE to the TokenSeller contract.
 * - The MINT_ROLE allows the TokenSeller contract to mint tokens and send them directly to the buyer.
 * - No Need for contract owner to give allowances.
 * - I used Checks-Effects-Interactions pattern to avoid reentrancy attack on all refunding functions
 * - I used _to.call() to refund the Ether as it is the preferred function in combination with reentrancy prevention
 * - For the refunding process, I chose not to get back the supra tokens sent. Because:
 *      # If there is another sale, it's easier to redeploy the contract than to check who still has the tokens
 *      # Trying to get back all the supra tokens sent would be too complicated: 
            + Each participant would need to give the allownace to the contract.
            + The owner wont have the possibility to refund all pariticpants at once.
 * - For security, readability and role of each function, I tried to keep them limited to ~4 lines
 */

contract TokenSeller is Ownable {
// events
    event EthReceived(address indexed sender, uint amount);
    event PreSaleTokenPurchased(address indexed sender, address indexed buyer, uint weiAmount, uint tokensSent);
    event PublicSaleTokenPurchased(address indexed sender, address indexed buyer, uint weiAmount, uint tokensSent);
    event Refunded(address indexed sender, address indexed buyerToRefund, uint weiAmount);

// constants, structs, and variables
    // Token to be sold
    SupraToken public immutable supraToken;

    struct CrowdSale {
        // Max cap of the crowdsale in wei
        uint maxCap;
        uint minCap;
        // Max contribution per buyer in wei
        uint maxPerBuyer;
        uint minPerBuyer;
        uint startTime;
        uint endTime;
        // Amount of tokens per wei
        uint rate;
        uint raisedWei;
        uint tokensSold;
        address[] buyers;
    }

    CrowdSale public preSale;
    CrowdSale public publicSale;

    // received amount per buyer during sale
    mapping(address => uint) public weiReceivedPerBuyerPresale;
    mapping(address => uint) public weiReceivedPerBuyerPublicSale;

// modifiers
    modifier notZeroAddress(address _sender) {
        require(_sender != address(0), "zero address");
        _;
    }

    modifier preSaleHasEnded() {
        require(saleHasEnded(preSale), "presale hasn't ended yet.");
        _;
    }

    modifier publicSaleHasEnded() {
        require(saleHasEnded(publicSale), "public sale hasn't ended yet.");
        _;
    }

    modifier preSaleMinCapNotReached() {
        require(!saleMinCapReached(preSale), "total min cap reached");
        _;
    }

    modifier publicSaleMinCapNotReached() {
        require(!saleMinCapReached(publicSale), "total min cap reached");
        _;
    }

    modifier isPreSaleBuyer() {
        require(isCrowdSaleBuyer(weiReceivedPerBuyerPresale[_msgSender()]), "not a presale buyer");
        _;
    }

    modifier isPublicSaleBuyer() {
        require(isCrowdSaleBuyer(weiReceivedPerBuyerPublicSale[_msgSender()]), "not a public sale buyer");
        _;
    }

// functions

    /**
     * @dev Constructor
     * @param _tokenToSell Token to be sold
     * @param _preSale Presale information
     * @param _publicSale Public sale information
     */
    constructor(address _tokenToSell, CrowdSale memory _preSale, CrowdSale memory _publicSale) 
            Ownable(_msgSender()) 
            notZeroAddress(_tokenToSell) {
        checkPreSaleInfo(_preSale);
        checkPublicSaleInfo(_publicSale, _preSale.endTime);

        supraToken = SupraToken(_tokenToSell);
        preSale = _preSale;
        publicSale = _publicSale;
    }

    receive() external payable {
        emit EthReceived(_msgSender(), msg.value);
    }

    fallback() external payable {
        require(msg.value > 0, "value must be greater than 0");
        emit EthReceived(_msgSender(), msg.value);
    }

    /**
     * @dev Buy token with ETH. Function will be called with ether.js when EthReceived() event is emitted
     */
    function buyTokenWithEth(address _buyer, uint _weiAmount) public payable notZeroAddress(_buyer) {
        require(_weiAmount > 0, "value must be greater than 0");
        require(isPresalePeriod() || isPublicSalePeriod(), "sale not started");

        if (isPresalePeriod()) {
            require(isValidPresalePurchase(_buyer, _weiAmount), "invalid amount. Check limits");
            proceedWithPreSalePurchase(_buyer, _weiAmount, getTokenAmountFrom(preSale.rate, _weiAmount));
        } else { // Public sale
            require(isValidPublicSalePurchase(_buyer, _weiAmount), "invalid amount. Check limits");
            proceedWithPublicSalePurchase(_buyer, _weiAmount, getTokenAmountFrom(publicSale.rate, _weiAmount));
        }
    }

    /**
     * @dev Refunds preSale buyer
     */
    function refundPreSaleBuyer() public payable
            notZeroAddress(_msgSender()) 
            isPreSaleBuyer 
            preSaleHasEnded 
            preSaleMinCapNotReached {
        // Checks-Effects-Interactions pattern to avoid reentrancy attack
        uint256 refundAmount = weiReceivedPerBuyerPresale[_msgSender()];
        weiReceivedPerBuyerPresale[_msgSender()] = 0;
        refundBuyer(_msgSender(), refundAmount);
    }

    /**
     * @dev Refunds publicSale buyer
     */
    function refundPublicSaleBuyer() public payable
            notZeroAddress(_msgSender()) 
            isPublicSaleBuyer 
            publicSaleHasEnded 
            publicSaleMinCapNotReached {
        // Checks-Effects-Interactions pattern to avoid reentrancy attack
        uint256 refundAmount = weiReceivedPerBuyerPublicSale[_msgSender()];                
        weiReceivedPerBuyerPublicSale[_msgSender()] = 0;
        refundBuyer(_msgSender(), refundAmount);
    }

    /**
     * @dev Refunds all preSale buyers at once. Can only be called by owner
     */
    function refundAllPreSaleBuyers() public payable onlyOwner preSaleHasEnded preSaleMinCapNotReached {
        for (uint256 i = 0; i < preSale.buyers.length; i++) {
            uint256 refundAmount = weiReceivedPerBuyerPresale[preSale.buyers[i]];
            if (refundAmount > 0) {
                weiReceivedPerBuyerPresale[preSale.buyers[i]] = 0;
                refundBuyer(preSale.buyers[i], refundAmount);
            }
        }
    }

    /**
     * @dev Refunds all publicSale buyers at once. Can only be called by owner
     */
    function refundAllPublicSaleBuyers() public payable onlyOwner publicSaleHasEnded publicSaleMinCapNotReached {
        for (uint256 i = 0; i < publicSale.buyers.length; i++) {
            uint256 refundAmount = weiReceivedPerBuyerPublicSale[publicSale.buyers[i]];
            if (refundAmount > 0) {
                weiReceivedPerBuyerPublicSale[publicSale.buyers[i]] = 0;
                refundBuyer(publicSale.buyers[i], refundAmount);
            }
        }
    }

    /**
     * @dev Sends remaining supra tokens after end of public sale. Can only be called by owner
     * @param _to Address to send remaining tokens to
     */
    function sendRemainingTo(address _to) public payable onlyOwner publicSaleHasEnded {
        supraToken.mint(_to, supraToken.totalSupply() - (preSale.tokensSold + publicSale.tokensSold));
    }

// helper functions
    function checkPreSaleInfo(CrowdSale memory _preSale) public pure {
        require(_preSale.startTime < _preSale.endTime, "presale start >= end");
        require(_preSale.minCap < _preSale.maxCap, "presale mincap >= maxcap");
        require(_preSale.minPerBuyer < _preSale.maxPerBuyer, "pre minPerBuyer >= maxPerBuyer");
    }

    function checkPublicSaleInfo(CrowdSale memory _publicSale, uint _preSaleEnd) public pure {
        require(_preSaleEnd == _publicSale.startTime, "preSale.end != publicSale.start");
        require(_publicSale.startTime < _publicSale.endTime, "publicSale start >= end");
        require(_publicSale.minCap < _publicSale.maxCap, "publicSale mincap >= maxcap");
        require(_publicSale.minPerBuyer < _publicSale.maxPerBuyer, "pub minPerBuyer >= maxPerBuyer");
    }

    function isPresalePeriod() public view returns (bool) {
        return isCrowdSalePeriod(preSale);
    }

    function isPublicSalePeriod() public view returns (bool) {
        return isCrowdSalePeriod(publicSale);
    }

    function isCrowdSalePeriod(CrowdSale memory _sale) internal view returns (bool) {
        return saleHasStarted(_sale) && !saleHasEnded(_sale);
    }

    function saleHasStarted(CrowdSale memory _sale) internal view returns (bool) {
        return block.timestamp >= _sale.startTime;
    }

    function saleHasEnded(CrowdSale memory _sale) internal view returns (bool) {
        return block.timestamp > _sale.endTime;
    }

    function saleMinCapReached(CrowdSale memory _sale) internal pure returns (bool) {
        return _sale.raisedWei >= _sale.minCap;
    }
    
    function isCrowdSaleBuyer(uint256 _buyAmount) internal pure returns (bool) {
        return _buyAmount > 0;
    }

    function isValidPresalePurchase(address _buyer, uint _weiAmount) internal view returns (bool) {
        return isValidPurchase(preSale, _weiAmount, weiReceivedPerBuyerPresale[_buyer]);
    }

    function isValidPublicSalePurchase(address _buyer, uint _weiAmount) internal view returns (bool) {
        return isValidPurchase(publicSale, _weiAmount, weiReceivedPerBuyerPublicSale[_buyer]);
    }

    function isValidPurchase(CrowdSale memory _sale, uint _weiAmount, uint _pastWeiContribution) internal view returns (bool) {
        bool maxCapNotReached = _weiAmount + preSale.raisedWei <= _sale.maxCap;
        bool minPerBuyerReached = _pastWeiContribution != 0 || _weiAmount >= _sale.minPerBuyer;
        bool maxPerBuyerNotReached = _weiAmount + _pastWeiContribution <= _sale.maxPerBuyer;

        return maxCapNotReached && minPerBuyerReached && maxPerBuyerNotReached;
    }

    function proceedWithPreSalePurchase(address _buyer, uint _weiAmount, uint tokensToSend) internal {
        supraToken.mint(_buyer, tokensToSend);
        weiReceivedPerBuyerPresale[_buyer] += _weiAmount;
        preSale.raisedWei += _weiAmount;
        preSale.tokensSold += tokensToSend;
        preSale.buyers.push(_buyer);

        emit PreSaleTokenPurchased(address(this), _buyer, _weiAmount, tokensToSend);
    }

    function proceedWithPublicSalePurchase(address _buyer, uint _weiAmount, uint tokensToSend) internal {
        supraToken.mint(_buyer, tokensToSend);
        weiReceivedPerBuyerPublicSale[_buyer] += _weiAmount;
        publicSale.raisedWei += _weiAmount;
        publicSale.tokensSold += tokensToSend;
        publicSale.buyers.push(_buyer);

        emit PublicSaleTokenPurchased(address(this), _buyer, _weiAmount, tokensToSend);
    }

    function getPresaleTokenAmntFor(uint _wei) internal view returns (uint) {
        return getTokenAmountFrom(preSale.rate, _wei);
    }

    function getPubSaleTokenAmntFor(uint _wei) internal view returns (uint) {
        return getTokenAmountFrom(publicSale.rate, _wei);
    }

    function getTokenAmountFrom(uint rate, uint _wei) internal pure returns (uint) {
        return _wei * rate;
    }

    /**
     * @dev Gets back amount of supraToken sold and Refunds the buyer with ether
     * @param _buyer address of the buyer
     * @param _weiAmount amount to be refunded
     */
    function refundBuyer(address _buyer, uint _weiAmount) internal {
        (bool sent, ) = _buyer.call{value: _weiAmount}("");
        require(sent, "Failed to refund Ether");
        emit Refunded(address(this), _buyer, _weiAmount);
    }

}