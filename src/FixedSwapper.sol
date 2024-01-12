// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import "@openzeppelin/contracts/utils/Context.sol";

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.0.0/contracts/token/ERC20/IERC20.sol
interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

contract FixedSwapper is Context {
/**
 * Fixed exchange rate of A to B in % in the form of
 * 1 B = A * fxdXchgRateAtoB/100 and 1 A = B * 100 / fxdXchgRateAtoB
 * i.e. 50 would exchange 1 A for 0.5 B
 */
uint16 public immutable FXD_XCHG_RATE_A_TO_B;
IERC20 public immutable tokenA;
IERC20 public immutable tokenB;

// constructor
    /**
     * @param _fxdXchgRateAtoB Fixed exchange rate of A to B in % in the form of 1 A = B * fxdXchgRateAtoB/100
     */
    constructor(address _tokenA, address _tokenB, uint16 _fxdXchgRateAtoB) {
        require(_tokenA != address(0) && _tokenB != address(0), "zero address");
        require(_fxdXchgRateAtoB > 0, "zero exchange rate");

        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        FXD_XCHG_RATE_A_TO_B = _fxdXchgRateAtoB;
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
        _amountB = _amountA * FXD_XCHG_RATE_A_TO_B / 100;
    }

    function getTokenAAmountFromB(uint256 _amountB) public view returns (uint256 _amountA) {
        _amountA = _amountB * 100 / FXD_XCHG_RATE_A_TO_B;
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