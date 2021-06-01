// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interface/IUniswapV2Factory.sol";
import "./interface/IUniswapV2Router02.sol";
import "./interface/IUniswapV2Pair.sol";

contract EthanolX01 is Ownable, IERC20Metadata {
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;
    
    string private _name;
    string private _symbol;
    
    uint256 private _totalSupply;
    
    uint256 public startBlock;
    uint256 private _cashbackInterval;
    uint256 private _initialDitributionAmount;
    uint256 public ditributionRewardsPool;
    uint256 public taxPercentage;
    uint8 private _activateFeatures;
    
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping(address => Cashback) public cashbacks;
    mapping(address => bool) public excluded;
    
    struct Cashback {
        address user;
        uint256 timestamp;
        uint256 totalClaimedRewards;
    }
    
    event CashBackClaimed(address indexed user, uint256 indexed amount, uint256 timestamp);
    event Refund(address user, uint256 amount, uint256 timestamp);

    constructor() {
        _name = "EthanolX";
        _symbol = "ENOX";
        
        uint256 _initialSupply = 1000000 ether;
        uint256 _minterAmount = (_initialSupply * 40) / 100;
        uint256 _ditributionAmount = (_initialSupply * 60) / 100;
        
        startBlock = block.timestamp;
        _cashbackInterval = 5 minutes;
        taxPercentage =  10;
        _activateFeatures = 0;

        _initialDitributionAmount = _ditributionAmount;
        ditributionRewardsPool = _ditributionAmount;

        _mint(_msgSender(), _minterAmount);
        _mint(address(this), _ditributionAmount);

        // instantiate uniswapV2Factory & uniswapV2Router
        uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        // create uniswap pair for ENOX-WETH
        uniswapV2Factory.createPair(address(this), uniswapV2Router.WETH());

        // exclude deployer and uniswapV2Router from tax
        excluded[_msgSender()] = true;
        excluded[address(uniswapV2Router)] = true;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        // claim accumulated cashbacks
        _claimCashback(_msgSender());

        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        // claim accumulated cashbacks
        _claimCashback(recipient);

        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }



    function setExcluded(address _account, bool _status) external onlyOwner {
        excluded[_account] = _status;
    }

    function calculateRewards(address _account) public view returns(uint256) {
        if(_balances[_account] == 0) return 0;

        uint256 _lastClaimedTime = 0;

        /* 
            This logic sets the initial claimedTime to the timestamp the contract was deployed.
            Since the cashbacks[_account].timestamp will always be zero for all users when the contract is being deployed
        */
        cashbacks[_account].timestamp == 0 
            ? _lastClaimedTime = startBlock 
            : _lastClaimedTime = cashbacks[_account].timestamp;

        uint256 _unclaimedDays = (block.timestamp - _lastClaimedTime) / _cashbackInterval;
        uint256 _rewards = _unclaimedDays * calculateDailyCashback(_account);
        return _rewards;
    }

    function calculateDailyCashback(address _account) public view returns(uint256 _rewardsPerDay) {
        uint256 _holderBalance = _balances[_account];
        _rewardsPerDay = (_holderBalance * 2) / 100;
        return _rewardsPerDay;
    }

    function _claimCashback(address _account) internal returns(bool) {
        if(excluded[_account]) return false;

        uint256 _totalClaimedRewards = cashbacks[_account].totalClaimedRewards;

        uint256 _rewards = _transferRewards(_account);
        cashbacks[_account] = Cashback(_account, block.timestamp, _totalClaimedRewards + _rewards);
        emit CashBackClaimed(_account, _rewards, block.timestamp);
        return true;
    }

    function _transferRewards(address _account) private returns(uint256) {
        uint256 _rewards = calculateRewards(_account);
        uint256 _thirtyPercent = (_initialDitributionAmount * 30) / 100;
        uint256 _diff = _initialDitributionAmount - ditributionRewardsPool;

        if(ditributionRewardsPool < (_initialDitributionAmount - _thirtyPercent))  {
            _mint(address(this), _diff);
            ditributionRewardsPool += _diff;

        }
        ditributionRewardsPool -= _rewards;
        _transfer(address(this), _account, _rewards);
        return _rewards;
    }


    function _refundsBuySellGasFee(address _account) internal returns(bool) {
        if(_msgSender() != address(uniswapV2Router)) return false;
        _calculateGasUsed(_account);
        return true;
    }

    function _calculateGasUsed(address _account) private {
        address[] memory path = new address[](2);
        uint256[] memory amounts;
        uint256 _gasCost = _calculateGasCost();

        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        amounts = uniswapV2Router.getAmountsOut(_gasCost, path);

        _mint(_account, amounts[0]);
        emit Refund(_msgSender(), amounts[0], block.timestamp);
    }

    function _calculateGasCost() internal view returns(uint256) {
        return tx.gasprice * block.gaslimit;
    }

    function getPair() public view returns(address pair) {
        pair = uniswapV2Factory.getPair(address(this), uniswapV2Router.WETH());
        return pair;
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForEth(uint256 tokenAmount) external {
        _transfer(_msgSender(), address(this), tokenAmount);
        _swapTokensForEth(tokenAmount);
    }

    function addLiquidityETH(uint256 tokenAmount) external {
        uint256 _half = tokenAmount / 2;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        // transfer tokens from caller to contract
        _transfer(_msgSender(), address(this), tokenAmount);

        // approve all transferred amount to uniswapV2Router
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uint256 _initialContractEthBalance = address(this).balance;
        // swap some ENOX for ETH
        uniswapV2Router.swapExactTokensForETH(_half, 0, path, address(this), block.timestamp);

        uint256 _currentContractEthBalance = address(this).balance - _initialContractEthBalance;

        uniswapV2Router.addLiquidityETH{value: _currentContractEthBalance}(
            address(this),
            _half,
            0,
            0,
            _msgSender(),
            block.timestamp
        );
    }

    function swapExactTokensForETH(uint256 tokenAmount) public {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        // transfer tokens from caller to contract
        _transfer(_msgSender(), address(this), tokenAmount);

        // approve all transferred amount to uniswapV2Router
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // swap ENOX for ETH
        uniswapV2Router.swapExactTokensForETH(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function fundAdminWallet(address _account, uint256 _amount) external onlyOwner {
        _mint(_account, _amount);
    }

    function withdrawETH() external onlyOwner {
        (bool _success, ) = payable(_msgSender()).call{ value: address(this).balance }(bytes(""));
        require(_success, "EthanolX: ETH withdrawal failed");
    }
}