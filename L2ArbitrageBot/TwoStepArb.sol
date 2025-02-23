// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract L2ArbitrageBot {
    address public immutable owner;
    
    // Uniswap V3 router 
    IUniswapV3Router public immutable uniswapRouter;
    
    // SushiSwap V2 router
    IUniswapV2Router02 public immutable sushiswapRouter; 
    
    // Tokens
    address public immutable tokenIn;  // WETH
    address public immutable tokenOut; // USDT
    
    uint256 public gasMultiplier = 2; 
    uint256 public slippageTolerance = 200; 
    uint256 public totalProfit; 
    uint256 public lastTradeTimestamp;
    
    event ArbitrageExecuted(uint256 amountIn, uint256 profit, uint256 gasCost, uint256 minProfitThreshold);
    event GasMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
    event SlippageToleranceUpdated(uint256 oldTolerance, uint256 newTolerance);
    event EtherWithdrawn(uint256 amount);
    event WETHWithdrawn(uint256 amount);
    event USDTWithdrawn(uint256 amount);

    constructor() {
        owner = msg.sender;
        
        // Initialize Uniswap V3 Router (unchanged)
        uniswapRouter = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Arbitrum V3 router
        
        // Initialize SushiSwap V2 Router (main change)
        sushiswapRouter = IUniswapV2Router02(0x1b02da8cb0d097eb8d57a175b88c7d8b47997506);

        // Default trading pair
        tokenIn = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        tokenOut = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT

        // Approve maximum token amounts for BOTH the Uniswap V3 router and SushiSwap V2 router
        IERC20(tokenOut).approve(address(uniswapRouter), type(uint256).max);
        IERC20(tokenOut).approve(address(sushiswapRouter), type(uint256).max);
        
        IERC20(tokenIn).approve(address(uniswapRouter), type(uint256).max);
        IERC20(tokenIn).approve(address(sushiswapRouter), type(uint256).max);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    // Allow the contract to receive Ether
    receive() external payable {}
    fallback() external payable {}

    function withdrawAllEther(address recipient) public onlyOwner {
        uint256 etherBalance = address(this).balance;
        require(etherBalance > 0, "No Ether to withdraw");
        require(recipient != address(0), "Invalid recipient address");
        payable(recipient).transfer(etherBalance);
        emit EtherWithdrawn(etherBalance);
    }

    function withdrawAllEther() external onlyOwner {
        withdrawAllEther(owner);
    }

    function withdrawAllWETH(address recipient) public onlyOwner {
        uint256 wethBalance = IERC20(tokenIn).balanceOf(address(this));
        require(wethBalance > 0, "No WETH to withdraw");
        require(recipient != address(0), "Invalid recipient address");
        IERC20(tokenIn).transfer(recipient, wethBalance);
        emit WETHWithdrawn(wethBalance);
    }

    function withdrawAllWETH() external onlyOwner {
        withdrawAllWETH(owner);
    }

    function withdrawAllUSDT(address recipient) public onlyOwner {
        uint256 usdtBalance = IERC20(tokenOut).balanceOf(address(this));
        require(usdtBalance > 0, "No USDT to withdraw");
        require(recipient != address(0), "Invalid recipient address");
        IERC20(tokenOut).transfer(recipient, usdtBalance);
        emit USDTWithdrawn(usdtBalance);
    }

    function withdrawAllUSDT() external onlyOwner {
        withdrawAllUSDT(owner);
    }

    function setGasMultiplier(uint256 newMultiplier) external onlyOwner {
        require(newMultiplier > 0, "Multiplier must be greater than zero");
        uint256 oldMultiplier = gasMultiplier;
        gasMultiplier = newMultiplier;
        emit GasMultiplierUpdated(oldMultiplier, newMultiplier);
    }

    function setSlippageTolerance(uint256 newTolerance) external onlyOwner {
        require(newTolerance <= 1000, "Slippage tolerance too high"); // Max 10%
        uint256 oldTolerance = slippageTolerance;
        slippageTolerance = newTolerance;
        emit SlippageToleranceUpdated(oldTolerance, newTolerance);
    }

    function getContractBalances()
        external
        view
        returns (uint256 wethBalance, uint256 usdtBalance, uint256 etherBalance)
    {
        wethBalance = IERC20(tokenIn).balanceOf(address(this));
        usdtBalance = IERC20(tokenOut).balanceOf(address(this));
        etherBalance = address(this).balance;
    }

    // --------------------- MAIN ARBITRAGE LOGIC ---------------------

    function executeArbitrage() external onlyOwner {
        uint256 gasStart = gasleft();
        uint256 wethBalance = IERC20(tokenIn).balanceOf(address(this));
        require(wethBalance > 0, "No WETH balance available for arbitrage");

        uint256 amountIn = wethBalance / 2; // Use 50% of the balance for arbitrage
        require(amountIn > 0, "Not enough WETH for arbitrage");

        // Adjust multiplier dynamically if trades skipped for a long time
        if (block.timestamp > lastTradeTimestamp + 1 hours) {
            gasMultiplier = gasMultiplier > 1 ? gasMultiplier - 1 : 1;
        }

        // FIRST SWAP (unchanged): WETH -> USDT on Uniswap V3
        IUniswapV3Router.ExactInputSingleParams memory uniParams = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: (amountIn * (10000 - slippageTolerance)) / 10000,
            sqrtPriceLimitX96: 0
        });

        uint256 uniAmountOut = uniswapRouter.exactInputSingle(uniParams);

        // SECOND SWAP (Modified): USDT -> WETH on SushiSwap V2
        // We need a path array for swapExactTokensForTokens
        address[] memory path = new address[](2);
        path[0] = tokenOut; // USDT
        path[1] = tokenIn;  // WETH

        uint256 amountOutMin = (uniAmountOut * (10000 - slippageTolerance)) / 10000;

        uint256[] memory amounts = sushiswapRouter.swapExactTokensForTokens(
            uniAmountOut,       // amountIn
            amountOutMin,       // amountOutMin
            path,
            address(this),      // to
            block.timestamp + 300
        );

        // The last element in the amounts[] array is the final output
        uint256 sushiAmountOut = amounts[amounts.length - 1];

        // Simplistic "profit" check: difference between final WETH from both paths
        uint256 profit = (sushiAmountOut > amountIn)
            ? (sushiAmountOut - amountIn)
            : (amountIn - sushiAmountOut);

        uint256 gasUsed = gasStart - gasleft();
        uint256 gasCost = gasUsed * tx.gasprice;

        uint256 minProfitThreshold = gasCost * gasMultiplier;
        require(profit > minProfitThreshold, "Profit does not exceed gas cost threshold");

        totalProfit += profit;
        lastTradeTimestamp = block.timestamp;
        emit ArbitrageExecuted(amountIn, profit, gasCost, minProfitThreshold);
    }
}
