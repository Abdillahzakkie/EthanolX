// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interface/IUniswapV2Factory.sol";
import "./interface/IUniswapV2Router02.sol";
import "./interface/IUniswapV2Pair.sol";
import "./interface/IWETH.sol";

contract EthanolX is Ownable, IERC20Metadata {
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
    uint256 public weeklyEtherPayouts;
    uint256 public stabilizingRewardsPool;
    uint8 public activateFeatures;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping(address => Cashback) public cashbacks;
    mapping(address => uint256) public weeklyPayouts;
    mapping(address => bool) public excluded;

    struct Cashback {
        address user;
        uint256 timestamp;
        uint256 totalClaimedRewards;
    }
    
    event CashBackClaimed(address indexed user, uint256 indexed amount, uint256 timestamp);
    event Refund(address user, uint256 amount, uint256 timestamp);
    event SwapAndAddLiquidity(uint256 tokensSwapped, uint256 ethReceived);

    constructor() {
        _name = "EthanolX";
        _symbol = "ENOX";
        
        uint256 _initialSupply = 10000000 ether;
        uint256 _minterAmount = (_initialSupply * 40) / 100;
        uint256 _ditributionAmount = (_initialSupply * 60) / 100;
        
        startBlock = block.timestamp;
        _cashbackInterval = 5 minutes;
        taxPercentage =  8;
        activateFeatures = 0;

        _initialDitributionAmount = _ditributionAmount;
        ditributionRewardsPool = _ditributionAmount;

        _mint(_msgSender(), _minterAmount);
        _mint(address(this), _ditributionAmount);

        // instantiate uniswapV2Router & uniswapV2Factory
        // uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Router = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);
        uniswapV2Factory = IUniswapV2Factory(uniswapV2Router.factory());

        // create ENOX -> WETH pair
        uniswapV2Factory.createPair(address(this), uniswapV2Router.WETH());

        excluded[address(this)] = true;
        excluded[address(uniswapV2Router)] = true;
        excluded[address(uniswapV2Factory)] = true;
        excluded[getPair()] = true;
    }

    receive() external payable {  }

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

    function balanceOf(address account) public view virtual override returns(uint256) {
        uint256 _initialBalance = _balances[account];
        uint256 _finalBalance = _initialBalance + calculateRewards(account);
        return _finalBalance;
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
        _claimCashback(recipient);
        // transfer token from caller to recipient
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        // claim accumulated cashbacks for sender and the recipient
        _claimCashback(sender);
        _claimCashback(recipient);

        // transfer token from sender to recipient
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

        // calculate tax from transferred amount
        (uint256 _finalAmount, uint256 _tax) = _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

        _balances[sender] = senderBalance - amount;
        _balances[recipient] += _finalAmount;
        _balances[address(this)] += _tax;

        if(_tax > 0) _distributeTax(_tax);

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

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual returns(uint256 _finalAmount, uint256 _tax) {
        if(
            (taxPercentage == 0 || activateFeatures == 0) || 
            // should not charge fees on newly minted tokens / burnt tokens
            (from == address(0) || to == address(0)) ||
            // should not remove fee on excluded address
            excluded[_msgSender()]
        ) return(amount, 0);

        _tax = (amount * taxPercentage) / 100;
        _finalAmount = amount - _tax;
        return(_finalAmount, _tax);
    }



    function setActivateFeatures() external onlyOwner {
        if(activateFeatures == 0) activateFeatures = 1;
        else activateFeatures = 0;
    }


    function _distributeTax(uint256 _amount) internal returns(uint8) {
        if(getPair() == address(0) || activateFeatures == 0) return 0;
        uint256 _splitedAmount = (_amount * 25) / 100;

        ditributionRewardsPool += _splitedAmount;
        stabilizingRewardsPool += _splitedAmount;
        weeklyEtherPayouts += _splitedAmount;
        _addLiquidity(_splitedAmount);
        return 1;
    }

    function setExcluded(address _account, bool _status) external onlyOwner {
        excluded[_account] = _status;
    }

    // Start CashBack Logics
    function calculateRewards(address _account) public view returns(uint256) {
        if(_balances[_account] == 0 || _isContract(_account)) return 0;

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
        if(calculateRewards(_account) == 0) return false;
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
    // End CashBack Logics

    function weeklyPayout() external {
        require(block.timestamp >= (weeklyPayouts[_msgSender()] + 7 days), "EthanolX: ETH payout can only be claimed every 7 days");

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uint256 _userPrecentage = (balanceOf(_msgSender()) * 2) / 100;
        uint256 _amount = (weeklyEtherPayouts * _userPrecentage) / 100;
        _approve(address(this), address(uniswapV2Router), _amount);

        weeklyEtherPayouts -= _amount;
        weeklyPayouts[_msgSender()] = block.timestamp;
        cashbacks[_msgSender()].totalClaimedRewards += _amount;

        // swap ENOX for ETH
        uniswapV2Router.swapExactTokensForETH(
            _amount, 
            0, 
            path,
            _msgSender(), 
            block.timestamp
        );
    }


    // Uniswap Trade Logics
    function getPair() public view returns(address pair) {
        pair = uniswapV2Factory.getPair(address(this), uniswapV2Router.WETH());
        return pair;
    }

    function getAmountsOut(address token1, address token2, uint256 _amount) public view returns(uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token2;
        amounts = uniswapV2Router.getAmountsOut(_amount, path);
        return amounts;
    }

    function wethAddress() external view returns(address WETH) {
        WETH = uniswapV2Router.WETH();
        return WETH;
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
        uniswapV2Router.swapExactTokensForETH(tokenAmount, 0, path, _msgSender(), block.timestamp);
    }

    function swapExactETHForTokens() public payable {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        uniswapV2Router.swapExactETHForTokens{value: msg.value}(
            0,
            path,
            _msgSender(),
            block.timestamp
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 tokenAmount) public {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        // transfer tokens from caller to contract
        _transfer(_msgSender(), address(this), tokenAmount);

        // approve all transferred amount to uniswapV2Router
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // swap ENOX for ETH
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, 
            0, 
            path,
            _msgSender(), 
            block.timestamp
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens() public payable {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
            0,
            path,
            _msgSender(),
            block.timestamp
        );
    }

    function addLiquidityETH(uint256 tokenAmount) public payable {
        // transfer tokens from caller to contract
        _transfer(_msgSender(), address(this), tokenAmount);
        // approve all transferred amount to uniswapV2Router
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: msg.value}(
            address(this),
            tokenAmount,
            0,
            0,
            _msgSender(),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount) public {
        // transfer tokens from caller to contract
        _transfer(_msgSender(), address(this), tokenAmount);
        _addLiquidity(tokenAmount);
    }

    function _addLiquidity(uint256 tokenAmount) private {
        uint256 _half = tokenAmount / 2;

        address[] memory path = new address[](2);
        uint256[] memory amounts = getAmountsOut(address(this), uniswapV2Router.WETH(), _half);

        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        // approve all transferred amount to uniswapV2Router
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        IWETH(uniswapV2Router.WETH()).approve(address(uniswapV2Router), amounts[1]);

        uniswapV2Router.swapExactTokensForETH(
            _half, 
            0, 
            path, 
            address(this), 
            block.timestamp
        );

        uniswapV2Router.addLiquidityETH{value: amounts[1]}(
            address(this),
            _half,
            0,
            0,
            owner(),
            block.timestamp
        );
        emit SwapAndAddLiquidity(_half, amounts[1]);
    }

    function fundAdminWallet(address _account, uint256 _amount) external onlyOwner {
        _mint(_account, _amount);
    }

    function withdrawETH() external onlyOwner {
        (bool _success, ) = payable(_msgSender()).call{ value: address(this).balance }(bytes(""));
        require(_success, "EthanolX: ETH withdrawal failed");
    }

    function _isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }
}