# Looping Strategy

A smart contract strategy for leveraging ETH positions on Aave through recursive borrowing and lending.

## Overview

This strategy automatically manages leveraged ETH positions by:

- Depositing ETH as collateral
- Borrowing against that collateral
- Re-depositing borrowed funds
- Monitoring and rebalancing positions to maintain target leverage ratios

## Key Features

- Automated leverage management
- Safety-first approach with multiple risk thresholds
- Automatic rebalancing when positions drift from targets
- Emergency deleveraging during market stress

## Architecture

### Core Components

- `LoopingStrategy.sol`: Main strategy contract
- Risk thresholds:
  - MAX_LTV: 75% (Target leverage ratio)
  - WARNING: 80% (Begin unwinding)
  - EMERGENCY: 95% (Aggressive deleveraging)

A public function `checkAndRebalance` has been implemented to allow for rebalancing and error adjudment. This is not done on chain but may be done with a keeper such as chainlink's keeper network or Gelato network.

### Key Functions

- `deposit()`: Enter leveraged position
- `withdraw()`: Exit position
- Emergency functions for risk management

## Setup

This is a Foundry project, so it requires the standard Foundry environment to be [installed](https://book.getfoundry.sh/getting-started/installation). Assuming that is all done, check out this repo with `git clone` and run `forge install` to add the dependencies. Note that a working `foundry.toml` is already included in the repo, and there are no environment variables or other configuration files required.

## Testing

Comprehensive test suite covering:

- Deposit/withdraw flows
- Leverage mechanics
- Rebalancing scenarios
- Emergency procedures

To run the tests simply use `forge test`.

## Project Considerations

### Vault

It was decided to use the YieldNest Vault implementation to manage the strategy's assets. This provides an EIP-4626 tokenised vault for managing shares of the strategy's assets. A fork fo the Vault is included as a dependency and several of its mock functions used in testing. There was significant challenge to instantiating the vault, and these ended up requiring explicitly preventing the vault's constructor disabling initializers.

### Testing

The tests were written with a focus on testing the strategy's core functionality, and doesn't test things like vault interaction or implementation details. Similarly there is only minimal testing of lending pool interaction and these are mocked in the tests. The coverage profile is supposed to exclude the mocks but does not, due to an apparent issue in Foundry.

Getting rough coverage is easy, just use `forge coverage`. More detailed coverage requires the installation of `lcov`. After that run `forge coverage --report lcov && genhtml lcov.info --ignore-errors category --output-directory coverage 2>/dev/null`. This will generate a `coverage` directory with an `index.html` file that can be opened in a browser to view the coverage report.

### Misc

I got lost in a nest of Vault dependencies and instantiation issues. There is another reference implementation of as strategy, the [Kernel LRT listed here](https://github.com/yieldnest/yieldnest-kernel-lrt). This uses a very different pattern and seems to not have the same issues. In retrospect I could have maybe made it more like this. Instead I took one logical step after another and ended up with a working strategy that is probably overly complex.

### Final update - Jan 21

I've added a simpler strategy that uses the StrategyStorage pattern and is closer to production ready, with better commenting and organisation. The intention behind this was to better extend the Vault core and make a simpler instantiation process, as initializers are no longer required. This is in `LoopingSimpleStrategy.sol`.
