// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "hardhat/console.sol";

interface IPancakeRouter {
  function WETH() external pure returns (address);

  function factory() external pure returns (address);

  function addLiquidityETH(
    address token,
    uint256 amountTokenDesired,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline
  )
    external
    payable
    returns (
      uint256 amountToken,
      uint256 amountETH,
      uint256 liquidity
    );

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external;
}

interface IPancakeFactory {
  function createPair(address tokenA, address tokenB)
    external
    returns (address pair);
}

contract dGoldToken is ERC20, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  // bsc testnet
  IPancakeRouter router =
    IPancakeRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
  //  Uniswap v2 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
  // Pancake 0xD99D1c33F9fC3444f8101754aBC46c52416550D1

  // bsc mainnet
  // IPancakeRouter router = IPancakeRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);

  uint256 feeDenominator = 1000;
  address public pair;
  EnumerableSet.AddressSet dGoldTokenHolders;
  bool isSwapping;
  bool public enableTax = true;

  struct RewardDivision {
    address account;
    uint256 percentage;
    bool isExpired;
  }
  mapping(address => bool) public isExemptAccount;
  mapping(bool => RewardDivision[]) public rewardSetting;

  // tokenAmount / msg.value as Liquidity
  constructor() ERC20("Devious Licks dGOLD", "dGOLD13") {
    _mint(msg.sender, 1 * 10**8 * (10**decimals()));
    dGoldTokenHolders.add(msg.sender);
    console.log(router.factory());
    pair = IPancakeFactory(router.factory()).createPair(
      router.WETH(),
      address(this)
    );
    // fee settings (buy)
    rewardSetting[true].push(RewardDivision(address(this), 15, false));
    rewardSetting[true].push(
      RewardDivision(0x2C0b73164AF92a89d30Af163912B38F45b7f7b65, 5, false)
    ); // dev wallet
    rewardSetting[true].push(
      RewardDivision(0x2C0b73164AF92a89d30Af163912B38F45b7f7b65, 5, false)
    ); // marketing wallet
    rewardSetting[true].push(
      RewardDivision(0x2C0b73164AF92a89d30Af163912B38F45b7f7b65, 5, false)
    ); // staking pool wallet
    rewardSetting[true].push(RewardDivision(address(0), 20, false)); // burn
    // fee settings (sell)
    rewardSetting[false].push(RewardDivision(pair, 30, false)); // liquidity wallet
    rewardSetting[false].push(RewardDivision(address(this), 80, false));
    rewardSetting[false].push(
      RewardDivision(0x2C0b73164AF92a89d30Af163912B38F45b7f7b65, 10, false)
    ); // marketing wallet
    rewardSetting[false].push(
      RewardDivision(0x2C0b73164AF92a89d30Af163912B38F45b7f7b65, 10, false)
    ); // staking pool wallet
    rewardSetting[false].push(RewardDivision(address(0), 10, false)); // burn
  }

  receive() external payable {}

  function withdraw() external onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }

  function _transfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    bool isExempt = isExemptAccount[sender] || isExemptAccount[recipient];
    if (
      isExempt ||
      (sender != pair && recipient != pair) ||
      IERC20(pair).totalSupply() == 0 ||
      isSwapping ||
      !enableTax
    ) {
      super._transfer(sender, recipient, amount);
    } else {
      RewardDivision[] memory rewardForTx = rewardSetting[sender == pair];
      uint256 totalFeePercent;
      uint256 totalFee = 0;
      for (uint256 i = 0; i < rewardForTx.length; i++) {
        if (rewardForTx[i].isExpired && rewardForTx[i].percentage > 0) continue;
        // in case of distribute fee to token holders
        if (rewardForTx[i].account == address(this)) {
          uint256 countHolders = dGoldTokenHolders.length();
          uint256 balanceOfHolders = totalSupply() -
            balanceOf(address(this)) -
            balanceOf(pair);
          for (uint256 j = 0; j < countHolders; j++) {
            uint256 feeToHolders = (amount *
              rewardForTx[i].percentage *
              balanceOf(dGoldTokenHolders.at(j))) /
              (feeDenominator * balanceOfHolders);
            super._transfer(sender, dGoldTokenHolders.at(j), feeToHolders);
            totalFee += feeToHolders;
          }
        } else if (rewardForTx[i].account == pair) {
          super._transfer(
            sender,
            address(this),
            (amount * rewardForTx[i].percentage) / feeDenominator
          );
          totalFee += (amount * rewardForTx[i].percentage) / feeDenominator;
          _swapAndLiquify(
            (amount * rewardForTx[i].percentage) / feeDenominator
          );
        } else if (rewardForTx[i].account == address(0)) {
          _burn(sender, (amount * rewardForTx[i].percentage) / feeDenominator);
          totalFee += (amount * rewardForTx[i].percentage) / feeDenominator;
        } else {
          super._transfer(
            sender,
            rewardForTx[i].account,
            (amount * rewardForTx[i].percentage) / feeDenominator
          );
          totalFee += (amount * rewardForTx[i].percentage) / feeDenominator;
        }
        totalFeePercent += rewardForTx[i].percentage;
      }
      super._transfer(sender, recipient, (amount - totalFee));
    }

    if (
      recipient != address(this) &&
      recipient != address(pair) &&
      !dGoldTokenHolders.contains(recipient)
    ) dGoldTokenHolders.add(recipient);
  }

  function clearRewardAccount() external onlyOwner {
    delete rewardSetting[true];
    delete rewardSetting[false];
  }

  function setRewardAccount(
    address account,
    uint256 percent,
    bool isBuying
  ) external onlyOwner {
    RewardDivision[] memory rewardForTax = rewardSetting[isBuying];
    for (uint256 i = 0; i < rewardForTax.length; i++)
      if (rewardForTax[i].account == account) {
        rewardSetting[isBuying][i].percentage = percent;
        return;
      }
    rewardSetting[isBuying].push(RewardDivision(account, percent, isBuying));
  }

  function setExpireAccountForTax(address account, bool isBuying)
    external
    onlyOwner
  {
    RewardDivision[] memory rewardForTax = rewardSetting[isBuying];
    for (uint256 i = 0; i < rewardForTax.length; i++)
      if (rewardForTax[i].account == account)
        rewardSetting[isBuying][i].isExpired = true;
  }

  function setExempt(address account, bool isExempt) external onlyOwner {
    isExemptAccount[account] = isExempt;
  }

  function switchTax(bool _v) external onlyOwner {
    enableTax = _v;
    emit SwitchedTax(enableTax);
  }

  function _swapAndLiquify(uint256 contractTokenBalance) private {
    isSwapping = true;
    uint256 half = contractTokenBalance / 2;
    uint256 otherHalf = contractTokenBalance - half;

    uint256 initialBalance = address(this).balance;

    _swapTokensForBNB(half);

    uint256 newBalance = address(this).balance - initialBalance;

    _addLiquidity(otherHalf, newBalance);
    isSwapping = false;

    emit SwapAndLiquify(half, newBalance, otherHalf);
  }

  function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
    _approve(address(this), address(router), tokenAmount);
    router.addLiquidityETH{ value: bnbAmount }(
      address(this),
      tokenAmount,
      0,
      0,
      owner(),
      block.timestamp + 300
    );
  }

  function _swapTokensForBNB(uint256 tokenAmount) private {
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = router.WETH();

    _approve(address(this), address(router), tokenAmount);

    router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0,
      path,
      address(this),
      block.timestamp + 300
    );
  }

  function getHolderCount() external view returns (uint256) {
    return dGoldTokenHolders.length();
  }

  event SwapAndLiquify(
    uint256 tokensSwapped,
    uint256 bnbReceived,
    uint256 tokensIntoLiqudity
  );
  event SwitchedTax(bool enableTax);
}
