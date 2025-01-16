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

contract L2ArbitrageBot {
address public immutable owner;
IUniswapV3Router public immutable uniswapRouter;
IUniswapV3Router public immutable sushiswapRouter;
address public immutable tokenIn; // WETH
address public immutable tokenOut; // USDT

uint256 public gasMultiplier = 2; // Default gas multiplier
uint256 public slippageTolerance = 200; // Default 2% slippage tolerance
uint256 public totalProfit; // Track total profit
uint256 public lastTradeTimestamp;

event ArbitrageExecuted(uint256 amountIn, uint256 profit, uint256 gasCost, uint256 minProfitThreshold);
event GasMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
event SlippageToleranceUpdated(uint256 oldTolerance, uint256 newTolerance);
event EtherWithdrawn(uint256 amount);
event WETHWithdrawn(uint256 amount);
event USDTWithdrawn(uint256 amount);

constructor() {
owner = msg.sender;

// Initialize routers
uniswapRouter = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Uniswap V3 Router on Arbitrum (Verified)
sushiswapRouter = IUniswapV3Router(0x1af415a1EbA07a4986a52B6f2e7dE7003D82231e); // SushiSwap V3 Router on Arbitrum

// Default trading pair
tokenIn = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH (Verified)
tokenOut = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT (Verified)

// Approve maximum token amounts for BOTH tokenOut (USDT) AND tokenIn (WETH)
IERC20(tokenOut).approve(address(uniswapRouter), type(uint256).max);
IERC20(tokenOut).approve(address(sushiswapRouter), type(uint256).max);

// IMPORTANT FIX: Also approve WETH (tokenIn) so the routers can pull WETH from this contract
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

// Withdraw Ether with recipient parameter
function withdrawAllEther(address recipient) public onlyOwner {
uint256 etherBalance = address(this).balance;
require(etherBalance > 0, "No Ether to withdraw");
require(recipient != address(0), "Invalid recipient address");
payable(recipient).transfer(etherBalance);
emit EtherWithdrawn(etherBalance);
}

// Withdraw Ether to the owner's address
function withdrawAllEther() external onlyOwner {
withdrawAllEther(owner);
}

// Withdraw WETH with recipient parameter
function withdrawAllWETH(address recipient) public onlyOwner {
uint256 wethBalance = IERC20(tokenIn).balanceOf(address(this));
require(wethBalance > 0, "No WETH to withdraw");
require(recipient != address(0), "Invalid recipient address");
IERC20(tokenIn).transfer(recipient, wethBalance);
emit WETHWithdrawn(wethBalance);
}

// Withdraw WETH to the owner's address
function withdrawAllWETH() external onlyOwner {
withdrawAllWETH(owner);
}

// Withdraw USDT with recipient parameter
function withdrawAllUSDT(address recipient) public onlyOwner {
uint256 usdtBalance = IERC20(tokenOut).balanceOf(address(this));
require(usdtBalance > 0, "No USDT to withdraw");
require(recipient != address(0), "Invalid recipient address");
IERC20(tokenOut).transfer(recipient, usdtBalance);
emit USDTWithdrawn(usdtBalance);
}

// Withdraw USDT to the owner's address
function withdrawAllUSDT() external onlyOwner {
withdrawAllUSDT(owner);
}

// Update gas multiplier dynamically
function setGasMultiplier(uint256 newMultiplier) external onlyOwner {
require(newMultiplier > 0, "Multiplier must be greater than zero");
uint256 oldMultiplier = gasMultiplier;
gasMultiplier = newMultiplier;
emit GasMultiplierUpdated(oldMultiplier, newMultiplier);
}

// Update slippage tolerance dynamically
function setSlippageTolerance(uint256 newTolerance) external onlyOwner {
require(newTolerance <= 1000, "Slippage tolerance too high"); // Max 10%
uint256 oldTolerance = slippageTolerance;
slippageTolerance = newTolerance;
emit SlippageToleranceUpdated(oldTolerance, newTolerance);
}

// New function to display balances
function getContractBalances()
external
view
returns (uint256 wethBalance, uint256 usdtBalance, uint256 etherBalance)
{
wethBalance = IERC20(tokenIn).balanceOf(address(this));
usdtBalance = IERC20(tokenOut).balanceOf(address(this));
etherBalance = address(this).balance;
}

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

// FIRST SWAP: WETH -> USDT on Uniswap
IUniswapV3Router.ExactInputSingleParams memory uniParams = IUniswapV3Router.ExactInputSingleParams({
tokenIn: tokenIn, // WETH as input
tokenOut: tokenOut, // USDT as output
fee: 3000,
recipient: address(this),
deadline: block.timestamp + 300,
amountIn: amountIn,
amountOutMinimum: (amountIn * (10000 - slippageTolerance)) / 10000,
sqrtPriceLimitX96: 0
});

// ExactInputSingle swaps amountIn of one token for as much as possible of another token
uint256 uniAmountOut = uniswapRouter.exactInputSingle(uniParams);

// SECOND SWAP: USDT -> WETH on SushiSwap
IUniswapV3Router.ExactInputSingleParams memory sushiParams = IUniswapV3Router.ExactInputSingleParams({
tokenIn: tokenOut, // USDT as input
tokenOut: tokenIn, // WETH as output
fee: 3000,
recipient: address(this),
deadline: block.timestamp + 300,
amountIn: uniAmountOut, // use the USDT we just got from Uniswap
amountOutMinimum: (uniAmountOut * (10000 - slippageTolerance)) / 10000,
sqrtPriceLimitX96: 0
});

// ExactInputSingle swaps amountIn of one token for as much as possible of another token
uint256 sushiAmountOut = sushiswapRouter.exactInputSingle(sushiParams);

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
