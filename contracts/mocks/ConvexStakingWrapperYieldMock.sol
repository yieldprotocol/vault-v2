// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
struct Balances {
    uint128 art; // Debt amount
    uint128 ink; // Collateral amount
}

struct Vault {
    address owner;
    bytes6 seriesId; // Each vault is related to only one series, which also determines the underlying.
    bytes6 ilkId; // Asset accepted as collateral
}

interface ICauldron {
    /// @dev Each vault records debt and collateral balances_.
    function balances(bytes12 vault) external view returns (Balances memory);

    /// @dev A user can own one or more Vaults, with each vault being able to borrow from a single series.
    function vaults(bytes12 vault) external view returns (Vault memory);
}

contract ConvexStakingWrapperYieldMock is ERC20 {
    mapping(address => bytes12[]) public vaults;
    ICauldron cauldron;

    constructor() ERC20('StakedConvexToken', 'stkCvx') {}

    function deposit(uint256 _amount, address _to) external {
        if (_amount > 0) {
            _mint(_to, _amount);
            // IERC20(curveToken).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    function stake(uint256 _amount, address _to) external {
        if (_amount > 0) {
            _mint(_to, _amount);
            // IERC20(convexToken).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    function withdraw(uint256 _amount) external {
        if (_amount > 0) {
            _burn(msg.sender, _amount);
            // IRewardStaking(convexPool).withdraw(_amount, false);
            // IERC20(convexToken).safeTransfer(msg.sender, _amount);
        }
    }

    function withdrawAndUnwrap(uint256 _amount) external {
        if (_amount > 0) {
            _burn(msg.sender, _amount);
            // IRewardStaking(convexPool).withdrawAndUnwrap(_amount, false);
            // IERC20(curveToken).safeTransfer(msg.sender, _amount);
        }
    }

    function setCauldron(ICauldron _cauldron) external {
        cauldron = _cauldron;
    }

    // Set the locations of vaults where the user's funds have been deposited & the accounting is kept
    function addVault(bytes12 vault_) external {
        address account = cauldron.vaults(vault_).owner;
        require(account != address(0), 'No owner for the vault');
        bytes12[] storage userVault = vaults[account];
        for (uint256 i = 0; i < userVault.length; i++) {
            require(userVault[i] != vault_, 'already added');
        }
        userVault.push(vault_);
        vaults[account] = userVault;
    }
}
