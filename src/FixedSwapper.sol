// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FixedSwapper is Context {
/**
 * Fixed exchange rate From A to B.
 * We use the smallest bits based on the tokens' respective decimals.
 * i.e. If the rate from A to B is 2, then 1 * 10**A_decimals = 2 * 10**B_decimals
 * Which gives the following:
 * decimalAdjustedRate = rate * 10**B_decimals / 10**A_decimals
 * amountOfB = amountOfA * decimalAdjustedRate
 * amountOfA = amountOfB / decimalAdjustedRate 
 */
uint public immutable FXD_XCHG_RATE_A_TO_B;
ERC20 public immutable tokenA;
ERC20 public immutable tokenB;

// constructor
    /**
     * @dev 
     * @param _tokenA Token A
     * @param _tokenB Token B
     * @param _fxdXchgRateAtoB Fixed exchange rate of A to B. Must be greater than 0. i.e. rate of 2 means 1 * 10**A_decimals = 2 * 10**B_decimals
     * the _fxdXchgRateAtoB is used to get adjusted rate based on tokens' decimals
     */
    constructor(address _tokenA, address _tokenB, uint _fxdXchgRateAtoB) {
        require(_tokenA != address(0) && _tokenB != address(0), "zero address");
        require(_fxdXchgRateAtoB > 0, "zero exchange rate");

        tokenA = ERC20(_tokenA);
        tokenB = ERC20(_tokenB);
        FXD_XCHG_RATE_A_TO_B = _fxdXchgRateAtoB * 10**tokenB.decimals() / 10**tokenA.decimals();
    }
// events
    event SwappedAToB(address indexed sender, uint amountIn, uint amountOut);
    event SwappedBToA(address indexed sender, uint amountIn, uint amountOut);

// modifiers
    modifier notZeroAddress() {
        require(_msgSender() != address(0), "zero address");
        _;
    }

// functions

    function swapExactAToB(uint256 _amountIn) external notZeroAddress {
        require(senderHasEnoughBalanceOf(tokenA, _amountIn), "insufficient balance");
        require(senderGaveEnoughAllowanceOf(tokenA, _amountIn), "insufficient allowance");
        
        uint256 _amountOut = getTokenBAmountFromA(_amountIn);
        require(contractHasEnoughReservesOf(tokenB, _amountOut), "insufficient reserves");

        safeTransferFrom(_msgSender(), address(this), tokenA, _amountIn);
        safeTransferFrom(address(this), _msgSender(), tokenB, _amountOut);

        emit SwappedAToB(_msgSender(), _amountIn, _amountOut);
    }

    function swapAToExactB(uint256 _amountOut) external notZeroAddress {
        require(contractHasEnoughReservesOf(tokenB, _amountOut), "insufficient reserves");

        uint256 _amountIn = getTokenAAmountFromB(_amountOut);
        require(senderHasEnoughBalanceOf(tokenA, _amountIn), "insufficient balance");
        require(senderGaveEnoughAllowanceOf(tokenA, _amountIn), "insufficient allowance");
        
        safeTransferFrom(_msgSender(), address(this), tokenA, _amountIn);
        safeTransferFrom(address(this), _msgSender(), tokenB, _amountOut);

        emit SwappedAToB(_msgSender(), _amountIn, _amountOut);
    }

    function swapExactBtoA(uint256 _amountIn) external notZeroAddress {
        require(senderHasEnoughBalanceOf(tokenB, _amountIn), "insufficient balance");
        require(senderGaveEnoughAllowanceOf(tokenB, _amountIn), "insufficient allowance");

        uint256 _amountOut = getTokenAAmountFromB(_amountIn);
        require(contractHasEnoughReservesOf(tokenA, _amountOut), "insufficient reserves");

        safeTransferFrom(_msgSender(), address(this), tokenB, _amountIn);
        safeTransferFrom(address(this), _msgSender(), tokenA, _amountOut);

        emit SwappedBToA(_msgSender(), _amountIn, _amountOut);
    }

    function swapBtoExactA(uint256 _amountOut) external notZeroAddress {
        require(contractHasEnoughReservesOf(tokenA, _amountOut), "insufficient reserves");

        uint256 _amountIn = getTokenBAmountFromA(_amountOut);
        require(senderHasEnoughBalanceOf(tokenB, _amountIn), "insufficient balance");
        require(senderGaveEnoughAllowanceOf(tokenB, _amountIn), "insufficient allowance");

        safeTransferFrom(_msgSender(), address(this), tokenB, _amountIn);
        safeTransferFrom(address(this), _msgSender(), tokenA, _amountOut);

        emit SwappedBToA(_msgSender(), _amountIn, _amountOut);
    }

// helper functions
    function senderGaveEnoughAllowanceOf(IERC20 _token, uint256 _amount) internal view returns (bool) {
        return _token.allowance(_msgSender(), address(this)) >= _amount;
    }

    function contractHasEnoughReservesOf(IERC20 _token, uint256 _amount) internal view returns (bool) {
        return hasEnoughBalance(address(this), _token, _amount);
    }

    function senderHasEnoughBalanceOf(IERC20 _token, uint256 _amount) internal view returns (bool) {
        return hasEnoughBalance(_msgSender(), _token, _amount);
    }

    function hasEnoughBalance(address _wallet, IERC20 _token, uint256 _amount) internal view returns (bool) {
        return _token.balanceOf(_wallet) >= _amount;
        
    }

    function getTokenBAmountFromA(uint256 _amountA) public view returns (uint256 _amountB) {
        _amountB = _amountA * FXD_XCHG_RATE_A_TO_B;
    }

    function getTokenAAmountFromB(uint256 _amountB) public view returns (uint256 _amountA) {
        _amountA = _amountB / FXD_XCHG_RATE_A_TO_B;
    }

    function safeTransferFrom(
        address _from,
        address _to,
        IERC20 _token,
        uint256 _amount
    ) internal {
        bool successIn = _token.transferFrom(_from, _to, _amount);
        require(successIn, "transferFrom failed");
    }
}