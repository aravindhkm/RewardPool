// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./DividendPayingToken.sol";
import "./IterableMapping.sol";

contract EnrollContract is Ownable, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address payable;

    uint256 public maximumDividendContracts = 10;
    uint256 public createPoolFee = 0.1e18;
    address payable public tresuryAddress;

    mapping (address => EnumerableSet.AddressSet) private _dividendContracts;

    constructor () {
        tresuryAddress = payable(_msgSender());
    }

    receive() external payable{}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function recoverLeftOverBNB(uint256 amount) external onlyOwner {
        payable(owner()).sendValue(amount);
    }

    function recoverLeftOverToken(address token,uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(),amount);
    }

    function setMaximumDividendContracts(uint256 _maximumDividendContracts) external onlyOwner {
        require(_maximumDividendContracts != 0, "RewardPool: Can't be Zero");
        maximumDividendContracts = _maximumDividendContracts;
    }

    function setCreatePoolFee(uint256 newFee) external onlyOwner {
        createPoolFee = newFee;
    }

    function setTresuryAddress(address payable _tresuryAddress) external onlyOwner {
        require(_tresuryAddress != address(0), "RewardPool: Can't be zero address");

        tresuryAddress = _tresuryAddress;
    }

    function createRewardPool(address nativeAsset,address rewardAsset) external payable whenNotPaused{
        require(_dividendContracts[nativeAsset].length() <= maximumDividendContracts, "RewardPool: Dividends Limit Exceed");
        require(!_dividendContracts[nativeAsset].contains(rewardAsset), "RewardPool: Dividends Already Created");
        require(createPoolFee <= msg.value, "RewardPool: Fee is required");

        _dividendContracts[nativeAsset].add(rewardAsset);
        tresuryAddress.sendValue(msg.value);
    }

    function remove(address nativeAsset,address rewardAsset) public onlyOwner{
        _dividendContracts[nativeAsset].remove(rewardAsset);
    }

    function contains(address nativeAsset,address rewardAsset) public view returns (bool) {
        return _dividendContracts[nativeAsset].contains(rewardAsset);
    }

    function length(address nativeAsset) public view returns (uint256) {
        return  _dividendContracts[nativeAsset].length();
    }

    function at(address nativeAsset,uint256 index) public view returns (address) {
        return  _dividendContracts[nativeAsset].at(index);
    }

    function totalDividends(address nativeAsset) public view returns (address[] memory) {
        return  _dividendContracts[nativeAsset].values();
    }
}

contract RewardDistributor is Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool private swapping;
    bool private isBurn;

    DividendTracker public dividendTracker;

    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD;

    address public rewardAsset;
    address public nativeAsset;

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event ExcludeFromMaxHold(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsMaxHold(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(
    	uint256 tokensSwapped,
    	uint256 amount
    );

    event ProcessedDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );

    event marketWalletUpdate(
        address indexed marketWallet
    );

    event BUSDRewardUpdate(
        uint256 newFee
    );

    event liquidityFeeUpdate(
        uint256 newFee
    );

    event managementFeeUpdate(
        uint256 newFee
    );

    event burnFeeUpdate(
        uint256 newFee
    );

    constructor() {

    	//dividendTracker = new DividendTracker(rewardAsset);

        // Mainnet
        // IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        
        // // Create a uniswap pair for this new token
        // address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

        // uniswapV2Router = _uniswapV2Router;
        // uniswapV2Pair = _uniswapV2Pair;

        // _setAutomatedMarketMakerPair(uniswapV2Pair, true);

        // // exclude from receiving dividends
        // dividendTracker.excludeFromDividends(address(dividendTracker));
        // dividendTracker.excludeFromDividends(address(this));
        // dividendTracker.excludeFromDividends(owner());
        // dividendTracker.excludeFromDividends(deadWallet);
        // dividendTracker.excludeFromDividends(address(uniswapV2Router));
    }

    receive() external payable {}

    function updateDividendTracker(address newAddress) external onlyOwner {
        require(newAddress != address(0), "RewarPool: newAddress is a zero address");
        require(newAddress != address(dividendTracker), "RewarPool: The dividend tracker already has that address");

        DividendTracker newDividendTracker = DividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "RewarPool: The new dividend tracker must be owned by the RewarPool token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(deadWallet);
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateUniswapV2Router(address newAddress) external onlyOwner {        
        require(newAddress != address(0), "RewarPool: newAddress is a zero address");
        require(newAddress != address(uniswapV2Router), "RewarPool: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != address(0), "RewarPool: newAddress is a zero address");
        require(pair != uniswapV2Pair, "RewarPool: The PanCakeSwap pair cannot be removed from automatedMarketMakerPairs");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "RewarPool: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }


    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "RewarPool: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "RewarPool: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function withdrawableDividendOf(address account) external view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
  	}

	function dividendTokenBalanceOf(address account) external view returns (uint256) {
		return dividendTracker.balanceOf(account);
	}

    function minimumTokenBalanceForDividends() public view returns (uint256) {
        return dividendTracker.minimumTokenBalanceForDividends();
    }

	function excludeFromDividends(address account) external onlyOwner{
	    dividendTracker.excludeFromDividends(account);
	}

    function setMinimumTokenBalanceForDividends(uint256 _minimumTokenBalanceForDividends) public onlyOwner {
        dividendTracker.setMinimumTokenBalanceForDividends(_minimumTokenBalanceForDividends);
    }

    function withdrawLeftOverBNB(address account) external onlyOwner {
        payable(account).transfer(address(this).balance);
    }

    function withdrawLeftOverToken(address token,address account) external onlyOwner {
        IERC20(token).transfer(account,IERC20(token).balanceOf(address(this)));
    }

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

	function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
		dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

		uint256 contractTokenBalance;

        bool canSwap; // 20000

        if( canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner() &&
            !isBurn
        ) {
            swapping = true;

       //     uint256 managementTokens = contractTokenBalance.mul(managementFee).div(totalFees);
       //     swapAndSendToFee(managementTokens);

//            uint256 swapTokens = contractTokenBalance.mul(liquidityFee).div(totalFees);
       //     swapAndLiquify(swapTokens);

         //   uint256 sellTokens = balanceOf(address(this));
         //   swapAndSendDividends(sellTokens);

            swapping = false;
        }


        // try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        // try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping && !isBurn) {
	    	uint256 gas = gasForProcessing;

	    	try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	}
	    	catch {

	    	}
        }
    }

    function swapAndSendToFee(uint256 tokens) private {
        uint256 initialBUSDBalance = IERC20(rewardAsset).balanceOf(address(this));
        swapTokensForBUSD(tokens);
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        uint256 initialBalance = address(this).balance;
		
        swapTokensForEth(half);
		
        uint256 newBalance = address(this).balance.sub(initialBalance);
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }


    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        IERC20(nativeAsset).approve(address(uniswapV2Router), tokenAmount);
		
        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

    }

    function swapTokensForBUSD(uint256 tokenAmount) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = rewardAsset;

        IERC20(nativeAsset).approve(address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        IERC20(nativeAsset).approve(address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

    }

    function swapAndSendDividends(uint256 tokens) private{
        swapTokensForBUSD(tokens);
        uint256 dividends = IERC20(rewardAsset).balanceOf(address(this));
        bool success = IERC20(rewardAsset).transfer(address(dividendTracker), dividends);
		
        if (success) {
            dividendTracker.distributeDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }
}

contract DividendTracker is Ownable, DividendPayingToken {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public minimumTokenBalanceForDividends;
    uint256 public maxEditableTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor(address _rewardAsset) DividendPayingToken("RewarPool_Dividen_Tracker", "RewarPool_Dividend_Tracker",_rewardAsset) {
    	claimWait = 3600;
        minimumTokenBalanceForDividends = 110000 * (1e18); //Default value 200000 tokens
        maxEditableTokenBalanceForDividends = 200000 * (1e18); //0.02% of total supply.  Owner can't change beyond this value.
    }

    function _transfer(address, address, uint256) internal override {
        require(false, "RewarPool_Dividend_Tracker: No transfers allowed");
    }
	
    function withdrawDividend() public override {
        require(false, "RewarPool_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main RewarPool contract.");
    }

    function setMinimumTokenBalanceForDividends(uint256 _minimumTokenBalanceForDividends) public onlyOwner {
        require(_minimumTokenBalanceForDividends <= maxEditableTokenBalanceForDividends, "Minimum Token Blance For Dividends Can't set above 0.01% of total supply");
        minimumTokenBalanceForDividends = _minimumTokenBalanceForDividends;
    }

    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account], "RewarPoolVision: account is already excluded");
    	excludedFromDividends[account] = true;

    	_setBalance(account, 0);
    	tokenHoldersMap.remove(account);

    	emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "RewarPool_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "RewarPool_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }
	
    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ? tokenHoldersMap.keys.length.sub(lastProcessedIndex) : 0;
                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ? lastClaimTime.add(claimWait) : 0;
        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ? nextClaimTime.sub(block.timestamp) : 0;
    }

    function getAccountAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	processAccount(account, true);
    }

    function process(uint256 gas) external returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];

    		if(canAutoClaim(lastClaimTimes[account])) {
    			if(processAccount(payable(account), true)) {
    				claims++;
    			}
    		}

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}