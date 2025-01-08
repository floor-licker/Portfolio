This is a two-step L2 arbitrage bot on Arbitrum written for one of my clients.

# L2ArbitrageBot

This repository contains a Solidity smart contract named **L2ArbitrageBot** designed to perform arbitrage on Arbitrum using Uniswap V3 and SushiSwap V3.

## Overview

The **L2ArbitrageBot** contract:
- Holds and manages WETH and USDT balances.
- Performs a two-step arbitrage (WETH → USDT → WETH).
- Enforces slippage and gas cost checks to ensure profitable trades.
- Allows the owner to withdraw tokens or Ether.

## Features Checklist

- [x] **Ownership**  
  - The contract has an `owner` address set at deployment.  
  - Functions that modify state or withdraw funds are restricted with the `onlyOwner` modifier.

- [x] **Router Initialization**  
  - Uniswap V3 Router and SushiSwap V3 Router addresses are set in the constructor.  
  - The contract interacts with these routers using their `exactInputSingle` methods.

- [x] **Token Pair Setup**  
  - `tokenIn` (WETH) and `tokenOut` (USDT) addresses are defined and immutable.  
  - Ensures clear distinction between the input and output tokens for the swaps.

- [x] **Unlimited Token Approvals**  
  - Both WETH (`tokenIn`) and USDT (`tokenOut`) are approved for Uniswap and SushiSwap.  
  - This allows the contract to swap without needing further approvals.

- [x] **Receiving Ether**  
  - The contract includes `receive()` and `fallback()` functions to accept ETH (useful if needed for wrapping).

- [x] **Withdraw Functions**  
  - `withdrawAllEther(address recipient)` and `withdrawAllEther()` let the owner withdraw any Ether.  
  - `withdrawAllWETH(address recipient)` and `withdrawAllWETH()` let the owner withdraw any WETH.  
  - `withdrawAllUSDT(address recipient)` and `withdrawAllUSDT()` let the owner withdraw any USDT.  
  - All functions emit relevant events and require a nonzero balance to proceed.

- [x] **Configurable Gas Multiplier**  
  - `gasMultiplier` is an integer factor used in profit checks (default is 2).  
  - The owner can update this value via `setGasMultiplier(uint256 newMultiplier)`.

- [x] **Configurable Slippage Tolerance**  
  - `slippageTolerance` is set to 2% by default (200 = 2%).  
  - The owner can update this value via `setSlippageTolerance(uint256 newTolerance)`.

- [x] **Balance Inquiry**  
  - `getContractBalances()` returns the current balances of WETH, USDT, and Ether in the contract.

- [x] **Arbitrage Execution**  
  - `executeArbitrage()`:
    1. Uses half of the contract’s WETH balance as the input amount.  
    2. Swaps WETH → USDT on Uniswap.  
    3. Swaps the resulting USDT → WETH on SushiSwap.  
    4. Calculates profit vs. gas cost.  
    5. Requires `profit > (gasUsed * tx.gasprice * gasMultiplier)` before finalizing.  
    6. Emits an `ArbitrageExecuted` event on success.  

- [x] **Profit Tracking**  
  - Accumulates total profit in the `totalProfit` state variable.  
  - Ensures trades only proceed if profitable relative to gas costs.

- [x] **Event Logging**  
  - Emits events on important actions: `ArbitrageExecuted`, `GasMultiplierUpdated`, `SlippageToleranceUpdated`, and token withdrawal events.  
  - Facilitates on-chain transparency and easier off-chain monitoring.

## Getting Started

1. **Clone the repository**  
   ```bash
   git clone https://github.com/yourusername/L2ArbitrageBot.git
   cd L2ArbitrageBot

