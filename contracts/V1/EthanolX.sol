// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IUniswapV2Factory.sol";
import "./interface/IUniswapV2Pair.sol";
import "./interface/IUniswapV2Router02.sol";
import "./interface/IWETH.sol";

contract EthanolX is ERC20, Ownable {
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;
    uint256 public startBlock;
    uint256 private _blockIntervals;
    uint256 private _cashbackInterval;

    // mapping(address => Rewards) public rewards;
    mapping(address => Cashback) public cashbacks;

    // struct Rewards {
    //     address user;
    //     uint256 lastRewards;
    //     uint256 totalClaimedRewards;
    //     uint256 timestamp;
    // }

    struct Cashback {
        address user;
        uint256 timestamp;
        uint256 totalClaimedRewards;
    }

    constructor() ERC20("EthanolX", "ENOL-X") {
        uint256 _amount = 1000000 ether;
        _mint(_msgSender(), _amount);
        
        startBlock = block.timestamp;
        _blockIntervals = 1000;
        _cashbackInterval = 24 hours;

        uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    }

    // Override inherited transfer and transferFrom logic
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        super.transfer(recipient, amount);
        _refundGasUsed(recipient);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        super.transferFrom(sender, recipient, amount);
        _refundGasUsed(sender);
        return true;
    }

    function _refundGasUsed(address _account) private returns(bool) {
        address _pairAddress = uniswapV2Factory.getPair(address(this), uniswapV2Router.WETH());

        require(_pairAddress != address(0), "EthanolX: No ENOX-WETH pair found");
        if(_msgSender() != _pairAddress) return false;
        
        address[] memory path;
        uint256[] memory amounts;
        uint256 _gasCost = _calculateGasCost();

        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        amounts = uniswapV2Router.getAmountsOut(_gasCost, path);

        _mint(_account, amounts[0]);
        return true;
    }

    function _calculateRewards(address _account) internal view returns(uint256) {
        uint256 _lastClaimedTime = 0;

        cashbacks[_account].timestamp == 0 
            ? _lastClaimedTime = startBlock 
            : _lastClaimedTime = cashbacks[_account].timestamp;

        uint256 _unclaimedDays = (block.timestamp - _lastClaimedTime) / _cashbackInterval;

        uint256 _holderBalance = balanceOf(_account);
        uint256 _rewardsPerDay = (_holderBalance * 2) / 100;
        uint256 _rewards = _rewardsPerDay * _unclaimedDays;
        return _rewards;
    }

    function claimCashback() external {
        require(balanceOf(_msgSender()) > 0, "");
        require(block.timestamp >= cashbacks[_msgSender()].timestamp + _cashbackInterval, "");

        uint256 _rewards = _calculateRewards(_msgSender());
        uint256 _totalClaimedRewards = cashbacks[_msgSender()].totalClaimedRewards;

        cashbacks[_msgSender()] = Cashback(_msgSender(), block.timestamp, _totalClaimedRewards + _rewards);

        super._mint(_msgSender(), _rewards);
        _refundGasUsed(_msgSender());
    }

    function _calculateGasCost() internal view returns(uint256) {
        return tx.gasprice * block.gaslimit;
    }

    function withdrawETH() external onlyOwner {
        (bool _success, ) = payable(_msgSender()).call{ value: address(this).balance }(bytes(""));
        require(_success, "ETH withdrawal failed");
    }
}
