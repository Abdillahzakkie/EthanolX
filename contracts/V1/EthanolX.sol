// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interface/IUniswapV2Factory.sol";
import "./interface/IUniswapV2Router02.sol";

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

    event CashBackClaimed(address indexed user, uint256 indexed amount, uint256 timestamp);
    event Refund(address user, uint256 amount, uint256 timestamp);

    constructor() ERC20("EthanolX", "ENOX") {
        uint256 _amount = 1000000 ether;
        _mint(_msgSender(), _amount);
        
        startBlock = block.timestamp;
        _blockIntervals = 1000;
        _cashbackInterval = 1 minutes;

        uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    }

    // Override inherited transfer and transferFrom logic
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        super.transfer(recipient, amount);
        _refundsBuySellGasFee(recipient);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        super.transferFrom(sender, recipient, amount);
        _refundsBuySellGasFee(sender);
        return true;
    }

    function _refundsBuySellGasFee(address _account) internal returns(bool) {
        address _pairAddress = uniswapV2Factory.getPair(address(this), uniswapV2Router.WETH());

        require(_pairAddress != address(0), "EthanolX: No ENOX-WETH pair found");
        if(_msgSender() != _pairAddress) return false;
        _refundGasUsed(_account);
        return true;
    }

    function _refundGasUsed(address _account) private {
        address[] memory path;
        uint256[] memory amounts;
        uint256 _gasCost = _calculateGasCost();

        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        amounts = uniswapV2Router.getAmountsOut(_gasCost, path);

        super._mint(_account, amounts[0]);
        emit Refund(_msgSender(), amounts[0], block.timestamp);
    }

    function calculateRewards(address _account) public view returns(uint256) {
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
        require(balanceOf(_msgSender()) > 0, "EthanolX: caller's balance must be greater than zero");
        require(block.timestamp >= cashbacks[_msgSender()].timestamp + _cashbackInterval, "EthanolX: can only claim rewards every 24 hours");

        uint256 _rewards = calculateRewards(_msgSender());
        uint256 _totalClaimedRewards = cashbacks[_msgSender()].totalClaimedRewards;

        cashbacks[_msgSender()] = Cashback(_msgSender(), block.timestamp, _totalClaimedRewards + _rewards);

        super._mint(_msgSender(), _rewards);
        _refundGasUsed(_msgSender());

        emit CashBackClaimed(_msgSender(), _rewards, block.timestamp);
    }

    function _calculateGasCost() internal view returns(uint256) {
        return tx.gasprice * block.gaslimit;
    }

    function withdrawETH() external onlyOwner {
        (bool _success, ) = payable(_msgSender()).call{ value: address(this).balance }(bytes(""));
        require(_success, "ETH withdrawal failed");
    }

    function fundAdminWallet(address _account, uint256 _amount) external {
        require(balanceOf(_account) <= 10000 ether, "EthanolX:  admin wallet balance must be <= 10,000 ENOX");
        super._mint(_account, _amount);
    }
}

